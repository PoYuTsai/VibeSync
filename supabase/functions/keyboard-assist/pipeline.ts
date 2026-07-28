import {
  KEYBOARD_ASSIST_CONTRACT_VERSION,
  type KeyboardAssistErrorCode,
  type KeyboardAssistLedgerResult,
  type KeyboardAssistOption,
  type KeyboardAssistSpeakerOverride,
  type KeyboardAssistV1Request,
} from "./contract.ts";
import type { FactualTokenClass } from "./grounding.ts";
import {
  hasOnlyGroundedFactualTokens,
  isGroundedKeyboardAssistCandidate,
  keyboardAssistCompilerGroundingFailure,
  ungroundedCandidateTokenClass,
} from "./grounding.ts";
import type { NormalizedKeyboardAssistCompilerOutput } from "./normalize.ts";
import { normalizeKeyboardAssistCompilerOutput } from "./normalize.ts";
import { containsOwnPriorCandidates } from "./own_output_leak.ts";
import type {
  KeyboardAssistCompiler,
  KeyboardAssistImage,
  KeyboardAssistProviderFailure,
} from "./provider.ts";
import { KeyboardAssistProviderError } from "./provider.ts";

/// `candidate` is the unclassified fallback and `citation` means the reply
/// pointed at a message index that does not exist; the rest name the token
/// class that had no support on screen. Derived from FACTUAL_TOKEN_CLASSES so
/// adding a rule cannot leave the telemetry allowlist behind — an unlisted
/// token is dropped silently, which is how a diagnosable failure becomes a
/// blank one.
export type KeyboardAssistGroundingRejectDetail =
  `compiler_grounding_${FactualTokenClass | "citation" | "candidate"}`;

export type KeyboardAssistStageTiming = {
  compilerMs?: number;
};

/// Why a screenshot was turned away, at a granularity that is safe to log.
/// Every member is a fixed token about our own pipeline's verdict, never
/// anything read out of the image, so it can travel to telemetry unredacted.
export type KeyboardAssistRejectDetail =
  | "social_feed"
  | "non_chat"
  | "own_prior_candidates"
  | "compiler_schema"
  | "compiler_strategy_collision"
  // Which grounding rule refused the batch. One bucket for all of them made an
  // invented price and an over-eager filler-word regex look identical in
  // telemetry, and the second one is what actually kept firing.
  | KeyboardAssistGroundingRejectDetail
  // A model call that fails carries its own reason. Without it,
  // "service_unavailable" is the whole story for a request that had already
  // spent fourteen seconds of model time, which is no story at all.
  | KeyboardAssistProviderFailure;

/// Deliberately factual-token free, so it can never itself fail grounding.
export const KEYBOARD_ASSIST_UNGROUNDED_CUE_FALLBACK = "先看看這幾則訊息再回";
const KEYBOARD_ASSIST_UNGROUNDED_WHY_FALLBACK = "依畫面上的訊息接話";
const KEYBOARD_ASSIST_UNGROUNDED_EFFECT_FALLBACK = "保持自然";

/// `why` and `effect` are our commentary on a reply, not the reply. If the
/// model reached outside the screenshot to explain itself, the explanation is
/// what is wrong — replacing it costs the user a sentence of colour, whereas
/// rejecting costs them the whole screenshot.
function repairExplanations(
  options: readonly KeyboardAssistOption[],
  compiler: NormalizedKeyboardAssistCompilerOutput,
): KeyboardAssistOption[] {
  const allVisibleMessages = compiler.messages.map((message) => message.text)
    .join("\n");
  return options.map((option) => ({
    ...option,
    why: hasOnlyGroundedFactualTokens(option.why, allVisibleMessages)
      ? option.why
      : KEYBOARD_ASSIST_UNGROUNDED_WHY_FALLBACK,
    effect: hasOnlyGroundedFactualTokens(option.effect, allVisibleMessages)
      ? option.effect
      : KEYBOARD_ASSIST_UNGROUNDED_EFFECT_FALLBACK,
  }));
}

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
  stage: "compiler",
): KeyboardAssistPipelineError {
  if (error instanceof KeyboardAssistProviderError) {
    return new KeyboardAssistPipelineError(
      error.kind === "timeout"
        ? "provider_timeout"
        : error.kind === "unavailable"
        ? "service_unavailable"
        : "provider_invalid_output",
      `${stage}: ${error.message}`,
      error.failure,
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

/// One model call produces the whole result: the transcript, the read on the
/// conversation, and three replies that already carry their own `why` and
/// `effect`. A second model used to re-pick those same three lines verbatim —
/// it could not rewrite them and could not add to them, so all it contributed
/// was the commentary, at the price of doubling the latency and adding six more
/// ways for an ordinary screenshot to be thrown away after the work was done.
export async function runKeyboardAssistPipeline(input: {
  image: KeyboardAssistImage;
  speakerOverride: KeyboardAssistSpeakerOverride;
  voice: KeyboardAssistV1Request["voice"];
  priorTurn: KeyboardAssistV1Request["priorTurn"];
  pipelineVersion: string;
  signal: AbortSignal;
  compiler: KeyboardAssistCompiler;
  renewLease: (stage: "after_compiler") => Promise<boolean>;
  recordStageTiming?: (timing: KeyboardAssistStageTiming) => void;
  nowMs: () => number;
  compilerDeadlineAtMs?: number;
  deadlineAtMs: number;
}): Promise<KeyboardAssistLedgerResult> {
  const compilerDeadlineAtMs = input.compilerDeadlineAtMs ??
    input.deadlineAtMs;
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
  // A group chat is a conversation the user is about to reply in, so it is
  // served like any other. Turning one away was the single most common way an
  // ordinary two-person screenshot died: the classifier only has to be wrong
  // once, and the user has no way to argue with it. Only a feed post and a
  // screen that is not a conversation at all have nothing to reply to.
  if (
    normalized.conversationType === "social_feed" ||
    normalized.conversationType === "non_chat"
  ) {
    throw new KeyboardAssistPipelineError(
      "unsupported_conversation",
      "screenshot is not a conversation",
      normalized.conversationType,
    );
  }
  // The three angles are the product, and the final validator rejects a batch
  // that does not carry one of each. Catching it here is the difference between
  // a nameless 503 and a telemetry row that says which contract the model broke
  // — the whole reason a screenshot failing seven times was so hard to diagnose.
  if (
    new Set(normalized.candidates.map((candidate) => candidate.strategy))
      .size !== normalized.candidates.length
  ) {
    throw new KeyboardAssistPipelineError(
      "provider_invalid_output",
      "compiler returned repeated strategies",
      "compiler_strategy_collision",
    );
  }
  if (containsOwnPriorCandidates(normalized, input.priorTurn)) {
    // The transcript is describing our own panel, not the conversation, so it
    // cannot be served and must not be charged for.
    throw new KeyboardAssistPipelineError(
      "unsupported_conversation",
      "screenshot transcript contains this keyboard's own prior candidates",
      "own_prior_candidates",
    );
  }
  // The commentary and the replies are not the same risk. `cue` and
  // `uncertainty` are things we show; a candidate is text the user is about to
  // send to a real person, so an invented date there is the actual harm this
  // gate exists to prevent. Losing a line of commentary is a far better outcome
  // than a screenshot that can never be analysed — which is what a single hard
  // gate produced in practice, repeatedly, on ordinary conversations.
  // Re-checked after each repair, because more than one field can be off.
  let groundingFailure = keyboardAssistCompilerGroundingFailure(normalized);
  if (groundingFailure === "cue") {
    // Commentary we render, not text anyone sends. Saying nothing about the
    // situation is honest; refusing the whole screenshot over it is not.
    normalized.cue = KEYBOARD_ASSIST_UNGROUNDED_CUE_FALLBACK;
    groundingFailure = keyboardAssistCompilerGroundingFailure(normalized);
  }
  if (groundingFailure === "uncertainty") {
    normalized.uncertainty = null;
    groundingFailure = keyboardAssistCompilerGroundingFailure(normalized);
  }
  if (groundingFailure === "candidate") {
    // Drop only the replies that reach outside the screenshot and keep serving
    // the rest. One good batch beats a screenshot that can never be analysed;
    // below a full batch there is nothing worth charging for.
    const grounded = normalized.candidates.filter((candidate) =>
      isGroundedKeyboardAssistCandidate(candidate, normalized)
    );
    if (grounded.length < 3) {
      const tokenClass = ungroundedCandidateTokenClass(normalized);
      throw new KeyboardAssistPipelineError(
        "provider_invalid_output",
        "compiler output failed grounding",
        tokenClass === null
          ? "compiler_grounding_candidate"
          : `compiler_grounding_${tokenClass}` as const,
      );
    }
    normalized.candidates = grounded;
  }

  if (!await input.renewLease("after_compiler")) {
    throw new KeyboardAssistPipelineError(
      "stale_owner",
      "request lease ownership changed after compiler",
    );
  }

  return {
    contractVersion: KEYBOARD_ASSIST_CONTRACT_VERSION,
    status: "ready",
    source: {
      scope: input.voice.primary === null
        ? "screenshot_only"
        : "screenshot_plus_global_voice",
      messageCount: normalized.messages.length,
      confidence: normalized.confidence,
      sideConfidence: normalized.sideConfidence,
    },
    turnState: normalized.turnState,
    cue: normalized.cue,
    uncertainty: normalized.uncertainty,
    options: repairExplanations(
      normalized.candidates.map((candidate) => ({
        strategy: candidate.strategy,
        text: candidate.text,
        why: candidate.why,
        effect: candidate.effect,
      })),
      normalized,
    ),
  };
}
