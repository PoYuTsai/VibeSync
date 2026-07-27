import {
  classifyKeyboardAssistReplayPreflight,
  classifyKeyboardAssistStatus,
  computeKeyboardAssistInputHash,
  isRetainedKeyboardAssistReplayRow,
  type KeyboardAssistClaim,
  type KeyboardAssistHmacKeyring,
  type KeyboardAssistReplayRow,
  type KeyboardAssistSettlement,
  resolveKeyboardAssistHmacKey,
} from "./billing.ts";
import {
  isValidKeyboardAssistRequestId,
  KEYBOARD_ASSIST_CONTRACT_VERSION,
  type KeyboardAssistErrorCode,
  type KeyboardAssistLedgerResult,
  type KeyboardAssistRetryDisposition,
} from "./contract.ts";
import { KeyboardAssistPipelineError } from "./pipeline.ts";
import {
  KeyboardAssistValidationError,
  validateKeyboardAssistLedgerResult,
  validateKeyboardAssistRequest,
} from "./validate.ts";
import { sanitizeKeyboardAssistTelemetry } from "./telemetry.ts";

const MAX_BODY_BYTES = 2 * 1024 * 1024;
const REQUEST_DEADLINE_MS = 40_000;

export const keyboardAssistCorsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "Authorization, Content-Type, x-client-info, apikey",
};

export type KeyboardAssistUser = {
  id: string;
  email: string | null;
};

type LedgerIdentity = {
  userId: string;
  requestId: string;
  inputHash: string;
  ownerToken: string;
};

export type KeyboardAssistHandlerDependencies = {
  authenticate(request: Request): Promise<KeyboardAssistUser | null>;
  ledger: {
    lookup(
      userId: string,
      requestId: string,
    ): Promise<KeyboardAssistReplayRow | null>;
    claim(
      input: LedgerIdentity & {
        hmacKeyVersion: number;
      },
    ): Promise<KeyboardAssistClaim>;
    renew(input: LedgerIdentity): Promise<boolean>;
    release(input: LedgerIdentity): Promise<boolean>;
    settle(
      input: LedgerIdentity & {
        result: KeyboardAssistLedgerResult;
        monthlyLimit: number;
        dailyLimit: number;
        chargeQuota: boolean;
      },
    ): Promise<KeyboardAssistSettlement>;
    expire(userId: string, requestId: string): Promise<boolean>;
  };
  quota: {
    check(
      user: KeyboardAssistUser,
    ): Promise<
      | {
        kind: "allowed";
        monthlyLimit: number;
        dailyLimit: number;
        chargeQuota: boolean;
      }
      | { kind: "limited"; message: string }
      | { kind: "unavailable"; message: string }
    >;
  };
  rateLimit(
    user: KeyboardAssistUser,
  ): Promise<
    | { kind: "allowed" }
    | { kind: "limited"; retryAfterMs?: number }
    | { kind: "unavailable"; message: string }
  >;
  runPipeline(input: {
    request: ReturnType<typeof validateKeyboardAssistRequest>["request"];
    imageBytes: Uint8Array;
    signal: AbortSignal;
    compilerDeadlineAtMs: number;
    judgeDeadlineAtMs: number;
    deadlineAtMs: number;
    renewLease: (
      stage: "after_compiler" | "after_judge",
    ) => Promise<boolean>;
    recordStageTiming: (
      timing: { compilerMs?: number; judgeMs?: number },
    ) => void;
  }): Promise<KeyboardAssistLedgerResult>;
  recordTelemetry?(
    record: Record<string, string | number | boolean>,
  ): void;
  featureEnabled(user: KeyboardAssistUser): boolean | Promise<boolean>;
  keyring: KeyboardAssistHmacKeyring;
  pipelineVersion: string;
  now(): Date;
  monotonicNow?(): number;
  randomUuid(): string;
};

function jsonResponse(value: unknown, status: number): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
      ...keyboardAssistCorsHeaders,
    },
  });
}

function errorResponse(
  status: number,
  code: KeyboardAssistErrorCode,
  retryDisposition: KeyboardAssistRetryDisposition,
  options: { retryAfterMs?: number; message?: string } = {},
): Response {
  return jsonResponse({
    error: {
      code,
      retryDisposition,
      ...(options.retryAfterMs === undefined
        ? {}
        : { retryAfterMs: Math.max(250, Math.ceil(options.retryAfterMs)) }),
      ...(options.message === undefined ? {} : { message: options.message }),
    },
  }, status);
}

function resultResponse(
  result: KeyboardAssistLedgerResult,
  requestId: string,
): Response {
  return jsonResponse({ ...result, requestId }, 200);
}

function isStatusLookupRequest(request: Request): boolean {
  if (request.method !== "GET") return false;
  const url = new URL(request.url);
  const keys = [...url.searchParams.keys()];
  return keys.length === 1 &&
    keys[0] === "requestId" &&
    isValidKeyboardAssistRequestId(url.searchParams.get("requestId"));
}

async function parseBody(request: Request): Promise<unknown> {
  const contentLength = Number(request.headers.get("content-length"));
  if (
    Number.isFinite(contentLength) && contentLength > MAX_BODY_BYTES
  ) {
    throw new KeyboardAssistValidationError(
      "image_too_large",
      "HTTP body exceeds 2 MiB",
    );
  }
  const text = await request.text();
  if (new TextEncoder().encode(text).length > MAX_BODY_BYTES) {
    throw new KeyboardAssistValidationError(
      "image_too_large",
      "HTTP body exceeds 2 MiB",
    );
  }
  try {
    return JSON.parse(text);
  } catch {
    throw new KeyboardAssistValidationError(
      "invalid_request",
      "body must be JSON",
    );
  }
}

export function createKeyboardAssistHandler(
  deps: KeyboardAssistHandlerDependencies,
): (request: Request) => Promise<Response> {
  return async (request) => {
    let claimAcquired = false;
    const statusLookup = isStatusLookupRequest(request);
    const monotonicNow = deps.monotonicNow ?? (() => performance.now());
    const startedAtMs = monotonicNow();
    const compilerDeadlineAtMs = startedAtMs + 27_000;
    const judgeDeadlineAtMs = startedAtMs + 35_000;
    const requestDeadlineAtMs = startedAtMs + REQUEST_DEADLINE_MS;
    const stageTimings: { compilerMs?: number; judgeMs?: number } = {};
    let pipelineAttempted = false;
    let telemetryStatus:
      | "ready"
      | "needs_speaker_confirmation"
      | undefined;
    let telemetryErrorCode: KeyboardAssistErrorCode | undefined;
    try {
      if (request.method === "OPTIONS") {
        return new Response("ok", { headers: keyboardAssistCorsHeaders });
      }
      if (request.method !== "GET" && request.method !== "POST") {
        return errorResponse(
          405,
          "invalid_request",
          "terminal_clear",
        );
      }

      const user = await deps.authenticate(request);
      if (!user) {
        return errorResponse(401, "unauthorized", "terminal_clear");
      }

      if (request.method === "GET") {
        const url = new URL(request.url);
        const keys = [...url.searchParams.keys()];
        if (
          keys.length === 1 && keys[0] === "capability" &&
          url.searchParams.get("capability") === "1"
        ) {
          return jsonResponse({
            contractVersion: KEYBOARD_ASSIST_CONTRACT_VERSION,
            enabled: await deps.featureEnabled(user),
            pipelineVersion: deps.pipelineVersion,
          }, 200);
        }
        const requestId = url.searchParams.get("requestId");
        if (
          keys.length !== 1 || keys[0] !== "requestId" ||
          !isValidKeyboardAssistRequestId(requestId)
        ) {
          return errorResponse(400, "invalid_request", "terminal_clear");
        }
        const row = await deps.ledger.lookup(user.id, requestId);
        const status = classifyKeyboardAssistStatus(row, deps.now());
        if (status.kind === "done") {
          return resultResponse(status.result, requestId);
        }
        if (status.kind === "pending") {
          return errorResponse(
            425,
            "request_pending",
            "lookup_same_request",
            { retryAfterMs: status.retryAfterMs },
          );
        }
        if (status.kind === "expired") {
          const expired = await deps.ledger.expire(user.id, requestId);
          if (expired) {
            return errorResponse(
              410,
              "request_expired_no_charge",
              "new_request_after_user_change",
            );
          }
          // A concurrent worker may have renewed or settled after our lookup.
          const latest = classifyKeyboardAssistStatus(
            await deps.ledger.lookup(user.id, requestId),
            deps.now(),
          );
          if (latest.kind === "done") {
            return resultResponse(latest.result, requestId);
          }
          if (latest.kind === "pending") {
            return errorResponse(
              425,
              "request_pending",
              "lookup_same_request",
              { retryAfterMs: latest.retryAfterMs },
            );
          }
          if (latest.kind === "missing") {
            return errorResponse(
              404,
              "request_not_found",
              "new_request_after_user_change",
            );
          }
        }
        if (status.kind === "missing") {
          return errorResponse(
            404,
            "request_not_found",
            "new_request_after_user_change",
          );
        }
        return errorResponse(
          503,
          "service_unavailable",
          "lookup_same_request",
        );
      }

      let validated: ReturnType<typeof validateKeyboardAssistRequest>;
      try {
        validated = validateKeyboardAssistRequest(await parseBody(request));
      } catch (error) {
        if (error instanceof KeyboardAssistValidationError) {
          return errorResponse(
            error.code === "image_too_large" ? 413 : 400,
            error.code,
            "terminal_clear",
          );
        }
        return errorResponse(400, "invalid_request", "terminal_clear");
      }

      const { request: payload, imageBytes } = validated;
      const rawExisting = await deps.ledger.lookup(user.id, payload.requestId);
      const existing = isRetainedKeyboardAssistReplayRow(
          rawExisting,
          deps.now(),
        )
        ? rawExisting
        : null;
      const resolvedKey = resolveKeyboardAssistHmacKey(existing, deps.keyring);
      if (!resolvedKey) {
        return errorResponse(
          503,
          "service_unavailable",
          "retry_same_payload",
        );
      }

      const inputHash = await computeKeyboardAssistInputHash({
        userId: user.id,
        imageBytes,
        mediaType: payload.image.mediaType,
        speakerOverride: payload.speakerOverride,
        voice: payload.voice,
        secret: resolvedKey.secret,
      });
      const preflight = classifyKeyboardAssistReplayPreflight(
        existing,
        inputHash,
        deps.now(),
      );
      if (preflight.kind === "replay") {
        return resultResponse(preflight.result, payload.requestId);
      }
      if (preflight.kind === "mismatch") {
        return errorResponse(
          409,
          "request_replay_mismatch",
          "new_request_after_user_change",
        );
      }
      if (preflight.kind === "pending") {
        return errorResponse(
          425,
          "request_pending",
          "lookup_same_request",
          { retryAfterMs: preflight.retryAfterMs },
        );
      }

      if (!await deps.featureEnabled(user)) {
        return errorResponse(
          503,
          "service_unavailable",
          "terminal_clear",
        );
      }

      const ownerToken = deps.randomUuid();
      const identity = {
        userId: user.id,
        requestId: payload.requestId,
        inputHash,
        ownerToken,
      };
      const claim = await deps.ledger.claim({
        ...identity,
        hmacKeyVersion: resolvedKey.version,
      });
      if (claim.kind === "replay") {
        return resultResponse(claim.result, payload.requestId);
      }
      if (claim.kind === "pending") {
        return errorResponse(
          425,
          "request_pending",
          "lookup_same_request",
          { retryAfterMs: claim.retryAfterMs },
        );
      }
      if (claim.kind === "mismatch") {
        return errorResponse(
          409,
          "request_replay_mismatch",
          "new_request_after_user_change",
        );
      }
      if (claim.kind !== "claimed") {
        return errorResponse(
          503,
          "service_unavailable",
          claim.kind === "uncertain"
            ? "lookup_same_request"
            : "retry_same_payload",
        );
      }
      claimAcquired = true;

      const releaseOrLookup = async (
        status: number,
        code: KeyboardAssistErrorCode,
        disposition: KeyboardAssistRetryDisposition,
        options: { retryAfterMs?: number; message?: string } = {},
      ) => {
        return await deps.ledger.release(identity)
          ? errorResponse(status, code, disposition, options)
          : errorResponse(
            503,
            "settlement_uncertain",
            "lookup_same_request",
          );
      };

      let quota = await deps.quota.check(user);
      if (quota.kind === "limited") {
        return await releaseOrLookup(
          429,
          "quota_exhausted",
          "terminal_clear",
          { message: quota.message },
        );
      }
      if (quota.kind === "unavailable") {
        return await releaseOrLookup(
          503,
          "service_unavailable",
          "retry_same_payload",
        );
      }

      const rate = await deps.rateLimit(user);
      if (rate.kind === "limited") {
        return await releaseOrLookup(
          429,
          "model_rate_limited",
          "terminal_clear",
          { retryAfterMs: rate.retryAfterMs },
        );
      }
      if (rate.kind === "unavailable") {
        return await releaseOrLookup(
          503,
          "service_unavailable",
          "retry_same_payload",
        );
      }

      let result: KeyboardAssistLedgerResult;
      try {
        const remainingMs = requestDeadlineAtMs - monotonicNow();
        if (remainingMs <= 0) {
          throw new KeyboardAssistPipelineError(
            "provider_timeout",
            "request deadline reached before pipeline",
          );
        }
        pipelineAttempted = true;
        result = await deps.runPipeline({
          request: payload,
          imageBytes,
          signal: AbortSignal.any([
            request.signal,
            AbortSignal.timeout(Math.max(1, Math.ceil(remainingMs))),
          ]),
          compilerDeadlineAtMs,
          judgeDeadlineAtMs,
          deadlineAtMs: requestDeadlineAtMs,
          renewLease: () => deps.ledger.renew(identity),
          recordStageTiming: (timing) => Object.assign(stageTimings, timing),
        });
        if (!validateKeyboardAssistLedgerResult(result)) {
          throw new KeyboardAssistPipelineError(
            "provider_invalid_output",
            "pipeline returned an invalid result",
          );
        }
      } catch (error) {
        if (error instanceof KeyboardAssistPipelineError) {
          if (error.code === "stale_owner") {
            telemetryErrorCode = "settlement_uncertain";
            return errorResponse(
              503,
              "settlement_uncertain",
              "lookup_same_request",
            );
          }
          telemetryErrorCode = error.code;
          return await releaseOrLookup(
            error.code === "unsupported_conversation" ? 422 : 503,
            error.code,
            error.code === "unsupported_conversation"
              ? "terminal_clear"
              : "retry_same_payload",
          );
        }
        telemetryErrorCode = "provider_invalid_output";
        return await releaseOrLookup(
          503,
          "provider_invalid_output",
          "retry_same_payload",
        );
      }

      if (!await deps.ledger.renew(identity)) {
        telemetryErrorCode = "settlement_uncertain";
        return errorResponse(
          503,
          "settlement_uncertain",
          "lookup_same_request",
        );
      }

      if (result.status === "ready") {
        quota = await deps.quota.check(user);
        if (quota.kind === "limited") {
          telemetryErrorCode = "quota_exhausted";
          return await releaseOrLookup(
            429,
            "quota_exhausted",
            "terminal_clear",
            { message: quota.message },
          );
        }
        if (quota.kind === "unavailable") {
          telemetryErrorCode = "service_unavailable";
          return await releaseOrLookup(
            503,
            "service_unavailable",
            "retry_same_payload",
          );
        }
      }

      if (monotonicNow() >= requestDeadlineAtMs) {
        telemetryErrorCode = "provider_timeout";
        return await releaseOrLookup(
          503,
          "provider_timeout",
          "retry_same_payload",
        );
      }

      const settlement = await deps.ledger.settle({
        ...identity,
        result,
        monthlyLimit: quota.monthlyLimit,
        dailyLimit: quota.dailyLimit,
        chargeQuota: result.status === "ready" && quota.chargeQuota,
      });
      if (settlement.kind === "settled") {
        telemetryStatus = settlement.result.status;
        return resultResponse(settlement.result, payload.requestId);
      }
      if (settlement.kind === "quota_exceeded") {
        telemetryErrorCode = "quota_exhausted";
        return await releaseOrLookup(
          429,
          "quota_exhausted",
          "terminal_clear",
        );
      }
      if (settlement.kind === "mismatch") {
        telemetryErrorCode = "request_replay_mismatch";
        return errorResponse(
          409,
          "request_replay_mismatch",
          "new_request_after_user_change",
        );
      }
      if (
        settlement.kind === "stale_owner" ||
        settlement.kind === "uncertain"
      ) {
        telemetryErrorCode = "settlement_uncertain";
        return errorResponse(
          503,
          "settlement_uncertain",
          "lookup_same_request",
        );
      }
      telemetryErrorCode = "service_unavailable";
      return await releaseOrLookup(
        503,
        "service_unavailable",
        "retry_same_payload",
      );
    } catch {
      if (pipelineAttempted && !telemetryErrorCode) {
        telemetryErrorCode = claimAcquired
          ? "settlement_uncertain"
          : "service_unavailable";
      }
      const mustLookupSameRequest = claimAcquired || statusLookup;
      return errorResponse(
        503,
        claimAcquired ? "settlement_uncertain" : "service_unavailable",
        mustLookupSameRequest ? "lookup_same_request" : "retry_same_payload",
      );
    } finally {
      if (pipelineAttempted && deps.recordTelemetry) {
        try {
          const record = sanitizeKeyboardAssistTelemetry({
            event: telemetryStatus
              ? "keyboard_assist_succeeded"
              : "keyboard_assist_failed",
            contractVersion: KEYBOARD_ASSIST_CONTRACT_VERSION,
            pipelineVersion: deps.pipelineVersion,
            status: telemetryStatus ?? "failed",
            errorCode: telemetryErrorCode,
            ...stageTimings,
            totalMs: Math.max(0, Math.round(monotonicNow() - startedAtMs)),
            replay: false,
          });
          deps.recordTelemetry(record);
        } catch {
          // Telemetry is best-effort and must never alter request semantics.
        }
      }
    }
  };
}
