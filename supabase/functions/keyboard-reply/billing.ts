import { classifyQuotaRpcError } from "../_shared/quota.ts";
import type { KeyboardReplyStyle } from "./validate.ts";

export const KEYBOARD_REPLY_COST = 1;
export const KEYBOARD_REPLY_REPLAY_WINDOW_MS = 24 * 60 * 60 * 1000;

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const SHA256_PATTERN = /^[0-9a-f]{64}$/;

export function keyboardReplyReplayCutoffIso(now = new Date()): string {
  return new Date(now.getTime() - KEYBOARD_REPLY_REPLAY_WINDOW_MS)
    .toISOString();
}

export function isValidKeyboardReplyRequestId(
  value: unknown,
): value is string {
  return typeof value === "string" && UUID_PATTERN.test(value);
}

export async function computeKeyboardReplyInputHash(input: {
  message: string;
  style: KeyboardReplyStyle;
}): Promise<string> {
  const canonical = JSON.stringify([input.message, input.style]);
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(canonical),
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
  result_json: KeyboardReplyLedgerResult;
};

export type KeyboardReplyReplayPreflight =
  | { kind: "fresh" }
  | { kind: "mismatch" }
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
    ["extend", "resonate", "tease", "humor", "coldRead"].includes(
      result.style,
    );
}

export function classifyKeyboardReplyReplayPreflight(
  row: KeyboardReplyReplayRow | null,
  inputHash: string,
): KeyboardReplyReplayPreflight {
  if (!row) return { kind: "fresh" };
  if (row.input_hash !== inputHash) return { kind: "mismatch" };
  if (!isValidKeyboardReplyLedgerResult(row.result_json)) {
    return { kind: "mismatch" };
  }
  return { kind: "replay", result: row.result_json };
}

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

export async function settleKeyboardReplyRequest(input: {
  rpc: KeyboardReplyRpc;
  userId: string;
  requestId: string;
  inputHash: string;
  result: KeyboardReplyLedgerResult;
  monthlyLimit: number;
  dailyLimit: number;
  chargeQuota: boolean;
}): Promise<KeyboardReplySettlement> {
  if (
    !isValidKeyboardReplyRequestId(input.requestId) ||
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
