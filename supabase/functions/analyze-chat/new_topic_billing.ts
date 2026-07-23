// 新話題 exactly-once billing helpers（鏡像 coach-chat/billing.ts，
// ADR #22 範本；canonical 欄位序見計畫 §11.3）。
import { classifyQuotaRpcError } from "../_shared/quota.ts";
import {
  isValidNewTopicLedgerResult,
  type NewTopicLedgerResult,
  type NewTopicSituation,
} from "./new_topic_payload.ts";

export const NEW_TOPIC_CONTRACT_VERSION = "new-topic-exactly-once-v1";
export const NEW_TOPIC_REPLAY_WINDOW_MS = 24 * 60 * 60 * 1000;
export const NEW_TOPIC_REPLAY_HMAC_SECRET_NAME = "NEW_TOPIC_REPLAY_HMAC_KEY";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function normalizeNewTopicRequestId(value: unknown): string | null {
  if (typeof value !== "string" || !UUID_PATTERN.test(value)) return null;
  return value.toLowerCase();
}

export function newTopicReplayCutoffIso(now = new Date()): string {
  return new Date(now.getTime() - NEW_TOPIC_REPLAY_WINDOW_MS).toISOString();
}

/** Base64 至少 32 random bytes 才算 strong key（同 coach/keyboard 範本）。 */
export function isStrongNewTopicReplayHmacKey(
  value: unknown,
): value is string {
  if (typeof value !== "string" || value.length < 43) return false;
  if (!/^[A-Za-z0-9+/]+={0,2}$/.test(value)) return false;
  try {
    return atob(value).length >= 32;
  } catch {
    return false;
  }
}

/**
 * Server-keyed HMAC-SHA256（§11.3）。
 * Canonical serialization＝length-safe JSON array（絕不用分隔符串接）：
 * ["vibesync-new-topic-replay-v1", userId, partnerSummaryOrNull,
 *  effectiveStyleContextOrNull, situationOrNull]
 * 不納入 expectedTier / RevenueCat hint / quota counter / owner token。
 */
export async function computeNewTopicInputHash(input: {
  userId: string;
  partnerSummary: string | null;
  effectiveStyleContext: string | null;
  situation: NewTopicSituation | null;
  secret: string;
}): Promise<string> {
  const canonical = JSON.stringify([
    "vibesync-new-topic-replay-v1",
    input.userId,
    input.partnerSummary,
    input.effectiveStyleContext,
    input.situation,
  ]);
  const encoder = new TextEncoder();
  const derivedKey = await crypto.subtle.digest(
    "SHA-256",
    encoder.encode(`vibesync-new-topic-replay-v1\u0000${input.secret}`),
  );
  const key = await crypto.subtle.importKey(
    "raw",
    derivedKey,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const digest = await crypto.subtle.sign(
    "HMAC",
    key,
    encoder.encode(canonical),
  );
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

const SHA256_PATTERN = /^[0-9a-f]{64}$/;

export type NewTopicReplayRow = {
  input_hash: string;
  state: "pending" | "done";
  lease_expires_at: string;
  result_json: NewTopicLedgerResult | null;
};

export type NewTopicReplayPreflight =
  | { kind: "fresh" }
  | { kind: "mismatch" }
  | { kind: "pending"; retryAfterMs: number }
  | { kind: "replay"; result: NewTopicLedgerResult };

export function classifyNewTopicReplayPreflight(
  row: NewTopicReplayRow | null,
  inputHash: string,
  now = new Date(),
): NewTopicReplayPreflight {
  if (!row) return { kind: "fresh" };
  if (row.input_hash !== inputHash) return { kind: "mismatch" };
  if (row.state === "done") {
    if (!isValidNewTopicLedgerResult(row.result_json)) {
      return { kind: "mismatch" };
    }
    return { kind: "replay", result: row.result_json };
  }
  if (row.state !== "pending" || row.result_json !== null) {
    return { kind: "mismatch" };
  }
  const leaseExpiresAt = Date.parse(row.lease_expires_at);
  if (!Number.isFinite(leaseExpiresAt)) return { kind: "mismatch" };
  const retryAfterMs = leaseExpiresAt - now.getTime();
  return retryAfterMs > 0
    ? { kind: "pending", retryAfterMs: Math.max(250, retryAfterMs) }
    : { kind: "fresh" };
}

export type NewTopicClaim =
  | { kind: "claimed" }
  | { kind: "pending"; retryAfterMs: number }
  | { kind: "replay"; result: NewTopicLedgerResult }
  | { kind: "mismatch" }
  | { kind: "retryable"; message: string }
  | { kind: "failed"; message: string };

export type NewTopicSettlement =
  | {
    kind: "settled";
    charged: boolean;
    result: NewTopicLedgerResult;
  }
  | {
    kind: "quota_exceeded";
    reason: "monthly_limit_exceeded" | "daily_limit_exceeded";
  }
  | { kind: "mismatch" }
  | { kind: "retryable"; message: string }
  | { kind: "failed"; message: string };

export type NewTopicRpc = (
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

export async function claimNewTopicRequest(input: {
  rpc: NewTopicRpc;
  userId: string;
  requestId: string;
  inputHash: string;
  ownerToken: string;
}): Promise<NewTopicClaim> {
  if (
    normalizeNewTopicRequestId(input.requestId) === null ||
    normalizeNewTopicRequestId(input.ownerToken) === null ||
    !SHA256_PATTERN.test(input.inputHash)
  ) {
    return { kind: "failed", message: "invalid new-topic claim" };
  }

  let response: Awaited<ReturnType<NewTopicRpc>>;
  try {
    response = await input.rpc("claim_new_topic_request", {
      p_user_id: input.userId,
      p_request_id: input.requestId,
      p_input_hash: input.inputHash,
      p_owner_token: input.ownerToken,
    });
  } catch (error) {
    return {
      kind: "retryable",
      message: error instanceof Error ? error.message : String(error),
    };
  }

  if (response.error) {
    if (
      response.error.message?.includes("NEW_TOPIC_REQUEST_REPLAY_MISMATCH")
    ) {
      return { kind: "mismatch" };
    }
    if (isAmbiguousRpcTransportFailure(response.error)) {
      return {
        kind: "retryable",
        message: response.error.message || "new-topic claim transport failed",
      };
    }
    return {
      kind: "failed",
      message: response.error.message || "new-topic claim failed",
    };
  }

  if (
    !response.data || typeof response.data !== "object" ||
    Array.isArray(response.data)
  ) {
    return { kind: "retryable", message: "invalid new-topic claim response" };
  }
  const data = response.data as Record<string, unknown>;
  if (data.kind === "claimed") return { kind: "claimed" };
  if (
    data.kind === "pending" && typeof data.retryAfterMs === "number" &&
    Number.isFinite(data.retryAfterMs) && data.retryAfterMs > 0
  ) {
    return { kind: "pending", retryAfterMs: Math.ceil(data.retryAfterMs) };
  }
  if (data.kind === "replay" && isValidNewTopicLedgerResult(data.result)) {
    return { kind: "replay", result: data.result };
  }
  return { kind: "retryable", message: "invalid new-topic claim result" };
}

export async function releaseNewTopicClaim(input: {
  rpc: NewTopicRpc;
  userId: string;
  requestId: string;
  inputHash: string;
  ownerToken: string;
}): Promise<boolean> {
  if (
    normalizeNewTopicRequestId(input.requestId) === null ||
    normalizeNewTopicRequestId(input.ownerToken) === null ||
    !SHA256_PATTERN.test(input.inputHash)
  ) return false;

  try {
    const response = await input.rpc("release_new_topic_claim", {
      p_user_id: input.userId,
      p_request_id: input.requestId,
      p_input_hash: input.inputHash,
      p_owner_token: input.ownerToken,
    });
    return response.error === null && response.data === true;
  } catch {
    return false;
  }
}

export async function settleNewTopicRequest(input: {
  rpc: NewTopicRpc;
  userId: string;
  requestId: string;
  inputHash: string;
  ownerToken: string;
  result: NewTopicLedgerResult;
  monthlyLimit: number;
  dailyLimit: number;
  chargeQuota: boolean;
}): Promise<NewTopicSettlement> {
  if (
    normalizeNewTopicRequestId(input.requestId) === null ||
    normalizeNewTopicRequestId(input.ownerToken) === null ||
    !SHA256_PATTERN.test(input.inputHash) ||
    !isValidNewTopicLedgerResult(input.result)
  ) {
    return { kind: "failed", message: "invalid new-topic settlement" };
  }

  let response: Awaited<ReturnType<NewTopicRpc>>;
  try {
    response = await input.rpc("settle_new_topic_request", {
      p_user_id: input.userId,
      p_request_id: input.requestId,
      p_input_hash: input.inputHash,
      p_owner_token: input.ownerToken,
      p_result_json: input.result,
      p_monthly_limit: input.monthlyLimit,
      p_daily_limit: input.dailyLimit,
      p_charge_quota: input.chargeQuota,
    });
  } catch (error) {
    return {
      kind: "retryable",
      message: error instanceof Error ? error.message : String(error),
    };
  }

  if (response.error) {
    const quotaReason = classifyQuotaRpcError(response.error.message);
    if (quotaReason) return { kind: "quota_exceeded", reason: quotaReason };
    if (
      response.error.message?.includes("NEW_TOPIC_REQUEST_REPLAY_MISMATCH")
    ) {
      return { kind: "mismatch" };
    }
    if (response.error.message?.includes("NEW_TOPIC_REQUEST_OWNER_MISMATCH")) {
      return {
        kind: "retryable",
        message: "new-topic lease ownership changed",
      };
    }
    if (isAmbiguousRpcTransportFailure(response.error)) {
      return {
        kind: "retryable",
        message: response.error.message ||
          "new-topic settlement transport failed",
      };
    }
    return {
      kind: "failed",
      message: response.error.message || "new-topic settlement failed",
    };
  }

  if (
    !response.data || typeof response.data !== "object" ||
    Array.isArray(response.data)
  ) {
    return {
      kind: "retryable",
      message: "invalid new-topic settlement response",
    };
  }
  const data = response.data as Record<string, unknown>;
  if (
    typeof data.charged !== "boolean" ||
    !isValidNewTopicLedgerResult(data.result)
  ) {
    return {
      kind: "retryable",
      message: "invalid new-topic settlement result",
    };
  }
  return {
    kind: "settled",
    charged: data.charged,
    result: data.result,
  };
}
