import { classifyQuotaRpcError } from "../_shared/quota.ts";
import {
  isValidKeyboardReplyRequestId,
  KEYBOARD_REPLY_STYLES,
  type KeyboardReplyStyle,
} from "./contract.ts";

export const KEYBOARD_REPLY_COST = 1;
export const KEYBOARD_REPLY_REPLAY_WINDOW_MS = 24 * 60 * 60 * 1000;

const SHA256_PATTERN = /^[0-9a-f]{64}$/;

export function isStrongKeyboardReplayHmacKey(value: unknown): value is string {
  if (typeof value !== "string" || value.length < 43) return false;
  if (!/^[A-Za-z0-9+/]+={0,2}$/.test(value)) return false;
  try {
    return atob(value).length >= 32;
  } catch {
    return false;
  }
}

export function keyboardReplyReplayCutoffIso(now = new Date()): string {
  return new Date(now.getTime() - KEYBOARD_REPLY_REPLAY_WINDOW_MS)
    .toISOString();
}

export async function computeKeyboardReplyInputHash(input: {
  userId: string;
  message: string;
  style: KeyboardReplyStyle;
  secret: string;
}): Promise<string> {
  const canonical = JSON.stringify([
    "keyboard-reply",
    1,
    input.userId,
    input.message,
    input.style,
  ]);
  const encoder = new TextEncoder();
  const derivedKey = await crypto.subtle.digest(
    "SHA-256",
    encoder.encode(`vibesync-keyboard-replay-v1\u0000${input.secret}`),
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

export type KeyboardReplyLedgerResult = {
  reply: string;
  style: KeyboardReplyStyle;
};

export type KeyboardReplyReplayRow = {
  input_hash: string;
  state: "pending" | "done";
  lease_expires_at: string;
  result_json: KeyboardReplyLedgerResult | null;
};

export type KeyboardReplyReplayPreflight =
  | { kind: "fresh" }
  | { kind: "mismatch" }
  | { kind: "pending"; retryAfterMs: number }
  | { kind: "replay"; result: KeyboardReplyLedgerResult };

export function isValidKeyboardReplyLedgerResult(
  value: unknown,
): value is KeyboardReplyLedgerResult {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const result = value as Record<string, unknown>;
  return Object.keys(result).length === 2 &&
    typeof result.reply === "string" &&
    result.reply.trim().length >= 1 && result.reply.length <= 100 &&
    typeof result.style === "string" &&
    KEYBOARD_REPLY_STYLES.includes(result.style as KeyboardReplyStyle);
}

export function classifyKeyboardReplyReplayPreflight(
  row: KeyboardReplyReplayRow | null,
  inputHash: string,
  now = new Date(),
): KeyboardReplyReplayPreflight {
  if (!row) return { kind: "fresh" };
  if (row.input_hash !== inputHash) return { kind: "mismatch" };
  if (row.state === "done") {
    if (!isValidKeyboardReplyLedgerResult(row.result_json)) {
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

export type KeyboardReplyClaim =
  | { kind: "claimed" }
  | { kind: "pending"; retryAfterMs: number }
  | { kind: "replay"; result: KeyboardReplyLedgerResult }
  | { kind: "mismatch" }
  | { kind: "retryable"; message: string }
  | { kind: "failed"; message: string };

export type KeyboardReplySettlement =
  | {
    kind: "settled";
    charged: boolean;
    result: KeyboardReplyLedgerResult;
  }
  | {
    kind: "quota_exceeded";
    reason: "monthly_limit_exceeded" | "daily_limit_exceeded";
  }
  | { kind: "mismatch" }
  | { kind: "retryable"; message: string }
  | { kind: "failed"; message: string };

export type KeyboardReplyRpc = (
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

export async function claimKeyboardReplyRequest(input: {
  rpc: KeyboardReplyRpc;
  userId: string;
  requestId: string;
  inputHash: string;
  ownerToken: string;
}): Promise<KeyboardReplyClaim> {
  if (
    !isValidKeyboardReplyRequestId(input.requestId) ||
    !isValidKeyboardReplyRequestId(input.ownerToken) ||
    !SHA256_PATTERN.test(input.inputHash)
  ) {
    return { kind: "failed", message: "invalid keyboard reply claim" };
  }

  let response: Awaited<ReturnType<KeyboardReplyRpc>>;
  try {
    response = await input.rpc("claim_keyboard_reply_request", {
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
      response.error.message?.includes("KEYBOARD_REPLY_REQUEST_REPLAY_MISMATCH")
    ) {
      return { kind: "mismatch" };
    }
    if (isAmbiguousRpcTransportFailure(response.error)) {
      return {
        kind: "retryable",
        message: response.error.message || "keyboard claim transport failed",
      };
    }
    return {
      kind: "failed",
      message: response.error.message || "keyboard claim failed",
    };
  }

  if (
    !response.data || typeof response.data !== "object" ||
    Array.isArray(response.data)
  ) {
    return { kind: "retryable", message: "invalid keyboard claim response" };
  }
  const data = response.data as Record<string, unknown>;
  if (data.kind === "claimed") return { kind: "claimed" };
  if (
    data.kind === "pending" && typeof data.retryAfterMs === "number" &&
    Number.isFinite(data.retryAfterMs) && data.retryAfterMs > 0
  ) {
    return { kind: "pending", retryAfterMs: Math.ceil(data.retryAfterMs) };
  }
  if (data.kind === "replay" && isValidKeyboardReplyLedgerResult(data.result)) {
    return { kind: "replay", result: data.result };
  }
  return { kind: "retryable", message: "invalid keyboard claim result" };
}

export async function releaseKeyboardReplyClaim(input: {
  rpc: KeyboardReplyRpc;
  userId: string;
  requestId: string;
  inputHash: string;
  ownerToken: string;
}): Promise<boolean> {
  if (
    !isValidKeyboardReplyRequestId(input.requestId) ||
    !isValidKeyboardReplyRequestId(input.ownerToken) ||
    !SHA256_PATTERN.test(input.inputHash)
  ) return false;

  try {
    const response = await input.rpc("release_keyboard_reply_claim", {
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

export async function settleKeyboardReplyRequest(input: {
  rpc: KeyboardReplyRpc;
  userId: string;
  requestId: string;
  inputHash: string;
  ownerToken: string;
  result: KeyboardReplyLedgerResult;
  monthlyLimit: number;
  dailyLimit: number;
  chargeQuota: boolean;
}): Promise<KeyboardReplySettlement> {
  if (
    !isValidKeyboardReplyRequestId(input.requestId) ||
    !isValidKeyboardReplyRequestId(input.ownerToken) ||
    !SHA256_PATTERN.test(input.inputHash) ||
    !isValidKeyboardReplyLedgerResult(input.result)
  ) {
    return { kind: "failed", message: "invalid keyboard reply settlement" };
  }

  let response: Awaited<ReturnType<KeyboardReplyRpc>>;
  try {
    response = await input.rpc("settle_keyboard_reply_request", {
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
      response.error.message?.includes("KEYBOARD_REPLY_REQUEST_REPLAY_MISMATCH")
    ) {
      return { kind: "mismatch" };
    }
    if (
      response.error.message?.includes("KEYBOARD_REPLY_REQUEST_OWNER_MISMATCH")
    ) {
      return {
        kind: "retryable",
        message: "keyboard reply lease ownership changed",
      };
    }
    if (isAmbiguousRpcTransportFailure(response.error)) {
      return {
        kind: "retryable",
        message: response.error.message ||
          "keyboard settlement transport failed",
      };
    }
    return {
      kind: "failed",
      message: response.error.message || "keyboard settlement failed",
    };
  }

  if (
    !response.data || typeof response.data !== "object" ||
    Array.isArray(response.data)
  ) {
    return {
      kind: "retryable",
      message: "invalid keyboard settlement response",
    };
  }
  const data = response.data as Record<string, unknown>;
  if (
    typeof data.charged !== "boolean" ||
    !isValidKeyboardReplyLedgerResult(data.result)
  ) {
    return { kind: "retryable", message: "invalid keyboard settlement result" };
  }
  return {
    kind: "settled",
    charged: data.charged,
    result: data.result,
  };
}
