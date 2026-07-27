import {
  KEYBOARD_ASSIST_CONTRACT_VERSION,
  type KeyboardAssistErrorCode,
  type KeyboardAssistLedgerResult,
  type KeyboardAssistSpeakerOverride,
  type KeyboardAssistV1Request,
} from "./contract.ts";
import {
  isGroundedKeyboardAssistCompilerOutput,
  isGroundedKeyboardAssistReadyResult,
} from "./grounding.ts";
import { normalizeKeyboardAssistCompilerOutput } from "./normalize.ts";
import { containsOwnPriorCandidates } from "./own_output_leak.ts";
import type {
  KeyboardAssistCompiler,
  KeyboardAssistImage,
  KeyboardAssistJudge,
} from "./provider.ts";
import { KeyboardAssistProviderError } from "./provider.ts";
import { validateKeyboardAssistLedgerResult } from "./validate.ts";

export type KeyboardAssistStageTiming = {
  compilerMs?: number;
  judgeMs?: number;
};

/// Why a screenshot was turned away, at a granularity that is safe to log.
/// Every member is a fixed token about our own pipeline's verdict, never
/// anything read out of the image, so it can travel to telemetry unredacted.
export type KeyboardAssistRejectDetail =
  | "group"
  | "social_feed"
  | "non_chat"
  | "own_prior_candidates"
  | "compiler_schema"
  | "compiler_grounding";

export class KeyboardAssistPipelineError extends Error {
  constructor(
    public readonly code: KeyboardAssistErrorCode | "stale_owner",
    message: string,
    public readonly detail?: KeyboardAssistRejectDetail,
  ) {
    super(message);
    this.name = "KeyboardAssistPipelineError";
  }
}

function mapProviderError(
  error: unknown,
  stage: "compiler" | "judge",
): KeyboardAssistPipelineError {
  if (error instanceof KeyboardAssistProviderError) {
    return new KeyboardAssistPipelineError(
      error.kind === "timeout"
        ? "provider_timeout"
        : error.kind === "unavailable"
        ? "service_unavailable"
        : "provider_invalid_output",
      `${stage}: ${error.message}`,
    );
  }
  return new KeyboardAssistPipelineError(
    "provider_invalid_output",
    error instanceof Error ? error.message : String(error),
  );
}

function phaseSignal(
  parent: AbortSignal,
  deadlineAtMs: number,
  nowMs: number,
): AbortSignal {
  return AbortSignal.any([
    parent,
    AbortSignal.timeout(Math.max(1, Math.ceil(deadlineAtMs - nowMs))),
  ]);
}

export async function runKeyboardAssistPipeline(input: {
  image: KeyboardAssistImage;
  speakerOverride: KeyboardAssistSpeakerOverride;
  voice: KeyboardAssistV1Request["voice"];
  priorTurn: KeyboardAssistV1Request["priorTurn"];
  pipelineVersion: string;
  signal: AbortSignal;
  compiler: KeyboardAssistCompiler;
  judge: KeyboardAssistJudge;
  renewLease: (
    stage: "after_compiler" | "after_judge",
  ) => Promise<boolean>;
  recordStageTiming?: (timing: KeyboardAssistStageTiming) => void;
  nowMs: () => number;
  compilerDeadlineAtMs?: number;
  judgeDeadlineAtMs?: number;
  deadlineAtMs: number;
}): Promise<KeyboardAssistLedgerResult> {
  const compilerDeadlineAtMs = input.compilerDeadlineAtMs ??
    input.deadlineAtMs;
  const judgeDeadlineAtMs = input.judgeDeadlineAtMs ?? input.deadlineAtMs;
  if (
    input.signal.aborted || input.nowMs() >= compilerDeadlineAtMs ||
    compilerDeadlineAtMs > input.deadlineAtMs
  ) {
    throw new KeyboardAssistPipelineError(
      "provider_timeout",
      "request deadline reached before compiler",
    );
  }

  let rawCompiler: unknown;
  const compilerStartedAtMs = input.nowMs();
  try {
    rawCompiler = await input.compiler({
      image: input.image,
      speakerOverride: input.speakerOverride,
      voice: input.voice,
      priorTurn: input.priorTurn,
      signal: phaseSignal(
        input.signal,
        compilerDeadlineAtMs,
        input.nowMs(),
      ),
      pipelineVersion: input.pipelineVersion,
    });
  } catch (error) {
    input.recordStageTiming?.({
      compilerMs: Math.max(
        0,
        Math.round(input.nowMs() - compilerStartedAtMs),
      ),
    });
    if (input.signal.aborted || error instanceof DOMException) {
      throw new KeyboardAssistPipelineError(
        "provider_timeout",
        "compiler was aborted",
      );
    }
    throw mapProviderError(error, "compiler");
  }
  input.recordStageTiming?.({
    compilerMs: Math.max(0, Math.round(input.nowMs() - compilerStartedAtMs)),
  });
  if (input.signal.aborted || input.nowMs() >= compilerDeadlineAtMs) {
    throw new KeyboardAssistPipelineError(
      "provider_timeout",
      "compiler exceeded its absolute deadline",
    );
  }

  const normalized = normalizeKeyboardAssistCompilerOutput(rawCompiler);
  if (!normalized) {
    throw new KeyboardAssistPipelineError(
      "provider_invalid_output",
      "compiler output failed schema",
      "compiler_schema",
    );
  }
  if (normalized.conversationType !== "chat") {
    throw new KeyboardAssistPipelineError(
      "unsupported_conversation",
      "screenshot is not a supported one-to-one chat",
      normalized.conversationType,
    );
  }
  if (containsOwnPriorCandidates(normalized, input.priorTurn)) {
    // The transcript is describing our own panel, not the conversation, so it
    // cannot be judged and must not be charged for.
    throw new KeyboardAssistPipelineError(
      "unsupported_conversation",
      "screenshot transcript contains this keyboard's own prior candidates",
      "own_prior_candidates",
    );
  }
  if (!isGroundedKeyboardAssistCompilerOutput(normalized)) {
    throw new KeyboardAssistPipelineError(
      "provider_invalid_output",
      "compiler output failed grounding",
      "compiler_grounding",
    );
  }

  if (
    normalized.sideConfidence === "low" &&
    input.speakerOverride === "none"
  ) {
    return {
      contractVersion: KEYBOARD_ASSIST_CONTRACT_VERSION,
      status: "needs_speaker_confirmation",
      suggestedMySide: normalized.suggestedMySide,
      sideConfidence: "low",
    };
  }

  if (!await input.renewLease("after_compiler")) {
    throw new KeyboardAssistPipelineError(
      "stale_owner",
      "request lease ownership changed after compiler",
    );
  }
  // The judge call has an 8-second cap and needs at least four seconds of
  // useful budget. The provider implementation applies the tighter call cap.
  if (
    input.signal.aborted ||
    judgeDeadlineAtMs - input.nowMs() < 4_000 ||
    judgeDeadlineAtMs > input.deadlineAtMs
  ) {
    throw new KeyboardAssistPipelineError(
      "provider_timeout",
      "insufficient deadline budget to start judge",
    );
  }

  const effectiveMySide = input.speakerOverride === "left_is_me"
    ? "left"
    : input.speakerOverride === "right_is_me"
    ? "right"
    : normalized.suggestedMySide;
  let rawJudged: unknown;
  const judgeStartedAtMs = input.nowMs();
  try {
    rawJudged = await input.judge({
      conversation: normalized,
      effectiveMySide,
      voice: input.voice,
      signal: phaseSignal(input.signal, judgeDeadlineAtMs, input.nowMs()),
      pipelineVersion: input.pipelineVersion,
    });
  } catch (error) {
    input.recordStageTiming?.({
      judgeMs: Math.max(0, Math.round(input.nowMs() - judgeStartedAtMs)),
    });
    if (input.signal.aborted || error instanceof DOMException) {
      throw new KeyboardAssistPipelineError(
        "provider_timeout",
        "judge was aborted",
      );
    }
    throw mapProviderError(error, "judge");
  }
  input.recordStageTiming?.({
    judgeMs: Math.max(0, Math.round(input.nowMs() - judgeStartedAtMs)),
  });
  if (input.signal.aborted || input.nowMs() >= judgeDeadlineAtMs) {
    throw new KeyboardAssistPipelineError(
      "provider_timeout",
      "judge exceeded its absolute deadline",
    );
  }
  if (!validateKeyboardAssistLedgerResult(rawJudged)) {
    throw new KeyboardAssistPipelineError(
      "provider_invalid_output",
      "judge output failed final schema",
    );
  }
  if (rawJudged.status !== "ready") {
    throw new KeyboardAssistPipelineError(
      "provider_invalid_output",
      "judge may only return a ready result",
    );
  }
  if (
    !isGroundedKeyboardAssistReadyResult(
      rawJudged,
      normalized,
      input.voice,
    )
  ) {
    throw new KeyboardAssistPipelineError(
      "provider_invalid_output",
      "judge output drifted from compiler evidence",
    );
  }
  if (!await input.renewLease("after_judge")) {
    throw new KeyboardAssistPipelineError(
      "stale_owner",
      "request lease ownership changed after judge",
    );
  }
  return rawJudged;
}
