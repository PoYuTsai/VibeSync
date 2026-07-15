import { classifyQuotaRpcError } from "../_shared/quota.ts";

export const OPTIMIZE_MESSAGE_COST = 1;
export const OPTIMIZE_MESSAGE_REPLAY_WINDOW_MS = 7 * 24 * 60 * 60 * 1000;

export function optimizeMessageReplayCutoffIso(
  now = new Date(),
): string {
  return new Date(
    now.getTime() - OPTIMIZE_MESSAGE_REPLAY_WINDOW_MS,
  ).toISOString();
}

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const SHA256_PATTERN = /^[0-9a-f]{64}$/;

export function isValidOptimizeMessageRequestId(
  value: unknown,
): value is string {
  return typeof value === "string" && UUID_PATTERN.test(value);
}

/**
 * Bind an idempotency key to every normalized input that can affect the
 * optimize-message answer. The client never supplies this hash; the Edge
 * function computes it after request validation.
 */
export async function computeOptimizeMessageInputHash(input: {
  messages: unknown;
  userDraft: string;
  sessionContext?: unknown;
  conversationSummary?: string | null;
  partnerSummary?: string | null;
  effectiveStyleContext?: string | null;
  knownContactName?: string | null;
  forceModel?: string | null;
}): Promise<string> {
  const canonical = JSON.stringify([
    input.messages,
    input.userDraft,
    input.sessionContext ?? null,
    input.conversationSummary ?? null,
    input.partnerSummary ?? null,
    input.effectiveStyleContext ?? null,
    input.knownContactName ?? null,
    input.forceModel ?? null,
  ]);
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(canonical),
  );
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

export type OptimizeMessageReplayRow = {
  input_hash: string;
  result_json: Record<string, unknown>;
  created_at?: string;
};

export type OptimizeMessageReplayPreflight =
  | { kind: "fresh" }
  | { kind: "mismatch" }
  | { kind: "replay"; result: Record<string, unknown> };

export function classifyOptimizeMessageReplayPreflight(
  row: OptimizeMessageReplayRow | null,
  inputHash: string,
): OptimizeMessageReplayPreflight {
  if (!row) return { kind: "fresh" };
  if (row.input_hash !== inputHash) return { kind: "mismatch" };
  return { kind: "replay", result: row.result_json };
}

export function hasUsableOptimizedMessage(
  result: Record<string, unknown>,
): boolean {
  const optimizedMessage = result.optimizedMessage;
  if (
    !optimizedMessage || typeof optimizedMessage !== "object" ||
    Array.isArray(optimizedMessage)
  ) {
    return false;
  }
  return typeof (optimizedMessage as Record<string, unknown>).optimized ===
      "string" &&
    ((optimizedMessage as Record<string, unknown>).optimized as string).trim()
        .length > 0;
}

/**
 * Persist only the generated fields needed for a lost-response replay. The
 * raw original-draft, conversation, context, usage, and telemetry fields never
 * enter this record. The generated text may still reflect those inputs.
 */
export function buildOptimizeMessageLedgerResult(
  result: Record<string, unknown>,
): Record<string, unknown> | null {
  if (!hasUsableOptimizedMessage(result)) return null;
  const optimizedMessage = result.optimizedMessage as Record<string, unknown>;
  return {
    optimizedMessage: {
      optimized: (optimizedMessage.optimized as string).trim(),
      reason: typeof optimizedMessage.reason === "string"
        ? optimizedMessage.reason
        : "",
    },
  };
}

/** Rebuild the client response from a minimal ledger snapshot plus this
 * request's hash-bound draft. The draft is never read from persistent data. */
export function hydrateOptimizeMessageReplayResult(
  ledgerResult: Record<string, unknown>,
  originalDraft: string,
): Record<string, unknown> | null {
  const minimal = buildOptimizeMessageLedgerResult(ledgerResult);
  if (!minimal) return null;
  const optimizedMessage = minimal.optimizedMessage as Record<string, unknown>;
  return {
    optimizedMessage: {
      original: originalDraft,
      optimized: optimizedMessage.optimized,
      reason: optimizedMessage.reason,
    },
  };
}

export type OptimizeMessageSettlement =
  | {
    kind: "settled";
    charged: boolean;
    result: Record<string, unknown>;
    monthlyUsed: number;
    dailyUsed: number;
  }
  | {
    kind: "quota_exceeded";
    reason: "monthly_limit_exceeded" | "daily_limit_exceeded";
  }
  | { kind: "mismatch" }
  | { kind: "retryable"; message: string }
  | { kind: "failed"; message: string };

export type OptimizeMessageRpc = (
  fn: string,
  params: Record<string, unknown>,
) => PromiseLike<{
  data: unknown;
  error: { message?: string; code?: string } | null;
}>;

function isAmbiguousRpcTransportFailure(error: {
  message?: string;
  code?: string;
}): boolean {
  const code = error.code?.trim() ?? "";
  const message = error.message?.toLowerCase() ?? "";
  return code === "" || code.startsWith("08") || code.startsWith("PGRST0") ||
    /(fetch|network|connection|socket|timeout|timed out|reset)/.test(message);
}

/**
 * Atomically stores the first successful result and, for non-test accounts,
 * increments quota by exactly one. A replay returns the stored result and
 * never increments usage again.
 */
export async function settleOptimizeMessageRequest(input: {
  rpc: OptimizeMessageRpc;
  userId: string;
  requestId: string;
  inputHash: string;
  result: Record<string, unknown>;
  monthlyLimit: number;
  dailyLimit: number;
  chargeQuota: boolean;
}): Promise<OptimizeMessageSettlement> {
  if (
    !isValidOptimizeMessageRequestId(input.requestId) ||
    !SHA256_PATTERN.test(input.inputHash)
  ) {
    return { kind: "failed", message: "invalid optimize request identity" };
  }

  let rpcResponse: Awaited<ReturnType<OptimizeMessageRpc>>;
  try {
    rpcResponse = await input.rpc(
      "settle_optimize_message_request",
      {
        p_user_id: input.userId,
        p_request_id: input.requestId,
        p_input_hash: input.inputHash,
        p_result_json: input.result,
        p_monthly_limit: input.monthlyLimit,
        p_daily_limit: input.dailyLimit,
        p_charge_quota: input.chargeQuota,
      },
    );
  } catch (error) {
    return {
      kind: "retryable",
      message: error instanceof Error ? error.message : String(error),
    };
  }
  const { data, error } = rpcResponse;

  if (error) {
    const quotaReason = classifyQuotaRpcError(error.message);
    if (quotaReason) {
      return { kind: "quota_exceeded", reason: quotaReason };
    }
    if (error.message?.includes("OPTIMIZE_MESSAGE_REQUEST_REPLAY_MISMATCH")) {
      return { kind: "mismatch" };
    }
    if (isAmbiguousRpcTransportFailure(error)) {
      return {
        kind: "retryable",
        message: error.message || "optimize settlement transport failed",
      };
    }
    return {
      kind: "failed",
      message: error.message ||
        "settle_optimize_message_request failed without message",
    };
  }

  if (!data || typeof data !== "object" || Array.isArray(data)) {
    return {
      kind: "retryable",
      message: "invalid optimize settlement response",
    };
  }
  const record = data as Record<string, unknown>;
  const result = record.result;
  if (!result || typeof result !== "object" || Array.isArray(result)) {
    return {
      kind: "retryable",
      message: "missing optimize settlement result",
    };
  }
  if (!hasUsableOptimizedMessage(result as Record<string, unknown>)) {
    return {
      kind: "retryable",
      message: "invalid optimize settlement result",
    };
  }
  if (typeof record.charged !== "boolean") {
    return {
      kind: "retryable",
      message: "missing optimize settlement charge state",
    };
  }
  if (
    typeof record.monthlyUsed !== "number" ||
    !Number.isInteger(record.monthlyUsed) || record.monthlyUsed < 0 ||
    typeof record.dailyUsed !== "number" ||
    !Number.isInteger(record.dailyUsed) || record.dailyUsed < 0
  ) {
    return {
      kind: "retryable",
      message: "missing optimize settlement usage counters",
    };
  }

  return {
    kind: "settled",
    charged: record.charged === true,
    result: result as Record<string, unknown>,
    monthlyUsed: record.monthlyUsed,
    dailyUsed: record.dailyUsed,
  };
}
