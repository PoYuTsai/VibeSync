// Coach 1:1 exactly-once billing helpers（鏡像 keyboard-reply/billing.ts，
// ADR #22 範本；canonical 欄位序見設計檔 §Phase C）。
import { classifyQuotaRpcError } from "../_shared/quota.ts";
import type { CoachScope, LifecyclePhase } from "./schemas.ts";

export const COACH_CONTRACT_VERSION = "coach-exactly-once-v1";
export const COACH_REPLAY_WINDOW_MS = 24 * 60 * 60 * 1000;

// 與 keyboard 範本相同的 UUID 樣式；zod .uuid() 之外的雙保險，
// 大小寫混寫在此正規化成小寫再進帳本。
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function normalizeCoachRequestId(value: unknown): string | null {
  if (typeof value !== "string" || !UUID_PATTERN.test(value)) return null;
  return value.toLowerCase();
}

export function isStrongCoachReplayHmacKey(value: unknown): value is string {
  if (typeof value !== "string" || value.length < 43) return false;
  if (!/^[A-Za-z0-9+/]+={0,2}$/.test(value)) return false;
  try {
    return atob(value).length >= 32;
  } catch {
    return false;
  }
}

export function coachReplayCutoffIso(now = new Date()): string {
  return new Date(now.getTime() - COACH_REPLAY_WINDOW_MS).toISOString();
}

export function deriveCoachScopeKey(input: {
  scope: CoachScope | null | undefined;
  conversationId: string | null | undefined;
}): string {
  if (input.scope?.type === "conversation") {
    return `conversation:${input.scope.conversationId}`;
  }
  if (input.scope?.type === "partner") {
    return `partner:${input.scope.partnerId}`;
  }
  if (typeof input.conversationId === "string" && input.conversationId !== "") {
    return `conversation:${input.conversationId}`;
  }
  return "none";
}

export async function computeCoachInputHash(input: {
  userId: string;
  userQuestion: string;
  sessionId?: string | null;
  activeSessionTurns?: ReadonlyArray<Record<string, unknown>>;
  forceAnswer?: boolean;
  scopeKey: string;
  lifecyclePhase?: LifecyclePhase | null;
  secret: string;
}): Promise<string> {
  const canonical = JSON.stringify([
    "coach-chat",
    1,
    input.userId,
    input.userQuestion,
    input.sessionId ?? null,
    input.activeSessionTurns ?? [],
    input.forceAnswer === true,
    input.scopeKey,
    input.lifecyclePhase ?? null,
  ]);
  const encoder = new TextEncoder();
  const derivedKey = await crypto.subtle.digest(
    "SHA-256",
    encoder.encode(`vibesync-coach-replay-v1\u0000${input.secret}`),
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

const COACH_RESULT_ENVELOPE_KEYS = [
  "card",
  "sessionId",
  "provider",
  "model",
  "generatedAt",
] as const;

// 現行 ResponseCardSchema 全欄位白名單；多任何一鍵即拒（設計鐵律 8，
// 與 migration 的 result_json CHECK 同組）。
const COACH_CARD_ALLOWED_KEYS = new Set([
  "responseType",
  "mode",
  "headline",
  "answer",
  "userTruth",
  "userState",
  "frictionType",
  "nextStep",
  "suggestedLine",
  "rewriteDecision",
  "rewriteReason",
  "boundaryReminder",
  "needsReflection",
  "reflectionQuestion",
  "costDeducted",
]);

export type CoachLedgerResult = {
  card: Record<string, unknown>;
  sessionId: string | null;
  provider: "claude";
  model: string;
  generatedAt: string;
};

export function isValidCoachLedgerResult(
  value: unknown,
): value is CoachLedgerResult {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const body = value as Record<string, unknown>;
  const keys = Object.keys(body);
  if (keys.length !== COACH_RESULT_ENVELOPE_KEYS.length) return false;
  for (const key of COACH_RESULT_ENVELOPE_KEYS) {
    if (!(key in body)) return false;
  }
  if (body.provider !== "claude") return false;
  if (typeof body.model !== "string" || body.model.length === 0) return false;
  if (typeof body.generatedAt !== "string" || body.generatedAt.length === 0) {
    return false;
  }
  if (body.sessionId !== null && typeof body.sessionId !== "string") {
    return false;
  }
  const card = body.card;
  if (!card || typeof card !== "object" || Array.isArray(card)) return false;
  const cardRecord = card as Record<string, unknown>;
  for (const key of Object.keys(cardRecord)) {
    if (!COACH_CARD_ALLOWED_KEYS.has(key)) return false;
  }
  if (
    cardRecord.responseType !== "coachAnswer" &&
    cardRecord.responseType !== "clarifyingQuestion"
  ) return false;
  if (cardRecord.costDeducted !== 0 && cardRecord.costDeducted !== 1) {
    return false;
  }
  return true;
}

export type CoachReplayRow = {
  input_hash: string;
  state: "pending" | "done";
  lease_expires_at: string;
  result_json: CoachLedgerResult | null;
};

export type CoachReplayPreflight =
  | { kind: "fresh" }
  | { kind: "mismatch" }
  | { kind: "pending"; retryAfterMs: number }
  | { kind: "replay"; result: CoachLedgerResult };

export function classifyCoachReplayPreflight(
  row: CoachReplayRow | null,
  inputHash: string,
  now = new Date(),
): CoachReplayPreflight {
  if (!row) return { kind: "fresh" };
  if (row.input_hash !== inputHash) return { kind: "mismatch" };
  if (row.state === "done") {
    if (!isValidCoachLedgerResult(row.result_json)) {
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

export type CoachClaim =
  | { kind: "claimed" }
  | { kind: "pending"; retryAfterMs: number }
  | { kind: "replay"; result: CoachLedgerResult }
  | { kind: "mismatch" }
  | { kind: "retryable"; message: string }
  | { kind: "failed"; message: string };

export type CoachSettlement =
  | {
    kind: "settled";
    charged: boolean;
    result: CoachLedgerResult;
  }
  | {
    kind: "quota_exceeded";
    reason: "monthly_limit_exceeded" | "daily_limit_exceeded";
  }
  | { kind: "mismatch" }
  | { kind: "retryable"; message: string }
  | { kind: "failed"; message: string };

export type CoachRpc = (
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

export async function claimCoachRequest(input: {
  rpc: CoachRpc;
  userId: string;
  requestId: string;
  inputHash: string;
  ownerToken: string;
}): Promise<CoachClaim> {
  if (
    normalizeCoachRequestId(input.requestId) === null ||
    normalizeCoachRequestId(input.ownerToken) === null ||
    !SHA256_PATTERN.test(input.inputHash)
  ) {
    return { kind: "failed", message: "invalid coach claim" };
  }

  let response: Awaited<ReturnType<CoachRpc>>;
  try {
    response = await input.rpc("claim_coach_request", {
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
    if (response.error.message?.includes("COACH_REQUEST_REPLAY_MISMATCH")) {
      return { kind: "mismatch" };
    }
    if (isAmbiguousRpcTransportFailure(response.error)) {
      return {
        kind: "retryable",
        message: response.error.message || "coach claim transport failed",
      };
    }
    return {
      kind: "failed",
      message: response.error.message || "coach claim failed",
    };
  }

  if (
    !response.data || typeof response.data !== "object" ||
    Array.isArray(response.data)
  ) {
    return { kind: "retryable", message: "invalid coach claim response" };
  }
  const data = response.data as Record<string, unknown>;
  if (data.kind === "claimed") return { kind: "claimed" };
  if (
    data.kind === "pending" && typeof data.retryAfterMs === "number" &&
    Number.isFinite(data.retryAfterMs) && data.retryAfterMs > 0
  ) {
    return { kind: "pending", retryAfterMs: Math.ceil(data.retryAfterMs) };
  }
  if (data.kind === "replay" && isValidCoachLedgerResult(data.result)) {
    return { kind: "replay", result: data.result };
  }
  return { kind: "retryable", message: "invalid coach claim result" };
}

export async function releaseCoachClaim(input: {
  rpc: CoachRpc;
  userId: string;
  requestId: string;
  inputHash: string;
  ownerToken: string;
}): Promise<boolean> {
  if (
    normalizeCoachRequestId(input.requestId) === null ||
    normalizeCoachRequestId(input.ownerToken) === null ||
    !SHA256_PATTERN.test(input.inputHash)
  ) return false;

  try {
    const response = await input.rpc("release_coach_claim", {
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

export async function settleCoachRequest(input: {
  rpc: CoachRpc;
  userId: string;
  requestId: string;
  inputHash: string;
  ownerToken: string;
  result: CoachLedgerResult;
  monthlyLimit: number;
  dailyLimit: number;
  chargeQuota: boolean;
}): Promise<CoachSettlement> {
  if (
    normalizeCoachRequestId(input.requestId) === null ||
    normalizeCoachRequestId(input.ownerToken) === null ||
    !SHA256_PATTERN.test(input.inputHash) ||
    !isValidCoachLedgerResult(input.result)
  ) {
    return { kind: "failed", message: "invalid coach settlement" };
  }

  let response: Awaited<ReturnType<CoachRpc>>;
  try {
    response = await input.rpc("settle_coach_request", {
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
    if (response.error.message?.includes("COACH_REQUEST_REPLAY_MISMATCH")) {
      return { kind: "mismatch" };
    }
    if (response.error.message?.includes("COACH_REQUEST_OWNER_MISMATCH")) {
      return {
        kind: "retryable",
        message: "coach lease ownership changed",
      };
    }
    if (isAmbiguousRpcTransportFailure(response.error)) {
      return {
        kind: "retryable",
        message: response.error.message || "coach settlement transport failed",
      };
    }
    return {
      kind: "failed",
      message: response.error.message || "coach settlement failed",
    };
  }

  if (
    !response.data || typeof response.data !== "object" ||
    Array.isArray(response.data)
  ) {
    return {
      kind: "retryable",
      message: "invalid coach settlement response",
    };
  }
  const data = response.data as Record<string, unknown>;
  if (
    typeof data.charged !== "boolean" ||
    !isValidCoachLedgerResult(data.result)
  ) {
    return { kind: "retryable", message: "invalid coach settlement result" };
  }
  return {
    kind: "settled",
    charged: data.charged,
    result: data.result,
  };
}
