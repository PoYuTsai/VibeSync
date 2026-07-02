// supabase/functions/analyze-chat/opener_charge.ts
//
// opener 扣費 idempotency 純 helper（docs/plans/2026-07-03-opener-idempotency-design.md）。
// 傳輸層重試雙扣窗口的修補：client 帶 requestId → 走 increment_usage_idempotent
// （同 TX 內 ledger INSERT ON CONFLICT 去重＋呼叫現有 increment_usage）；
// 不帶或形狀不合法（舊 client）→ 走舊 increment_usage，行為與修補前完全相同。
// dedup 不是錯誤：呼叫端照常回 200，只記 telemetry。

import { classifyQuotaRpcError } from "../_shared/quota.ts";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** 只收 canonical UUID；其他形狀一律當舊 client 走舊路（fail-open 相容）。 */
export function isValidOpenerRequestId(value: unknown): value is string {
  return typeof value === "string" && UUID_PATTERN.test(value);
}

/**
 * Codex R2 P2a：同 id 同 payload 的 dedup 重試上限。合法傳輸層重試一兩次
 * 就夠；超過＝改造 client 付一次刷無限新產出，直接擋。權威在 Edge 傳入
 * RPC（I7 慣例），SQL 不寫死。
 */
export const OPENER_REPLAY_LIMIT = 3;

export type OpenerPreflightVerdict = "proceed" | "mismatch" | "exhausted";

/**
 * Codex R2 P2b：模型呼叫前的 replay 護欄——mismatch/超限在燒 Claude 成本
 * 之前就擋。讀取非原子、fail-open；最終權威仍在扣費 RPC 的同款檢查。
 */
export function classifyOpenerReplayPreflight(args: {
  row: Record<string, unknown> | null;
  inputHash: string;
  replayLimit: number;
}): OpenerPreflightVerdict {
  if (!args.row) return "proceed";
  const storedHash = typeof args.row.input_hash === "string"
    ? args.row.input_hash
    : "";
  if (storedHash !== args.inputHash) return "mismatch";
  const replays = typeof args.row.replay_count === "number"
    ? args.row.replay_count
    : 0;
  if (replays + 1 > args.replayLimit) return "exhausted";
  return "proceed";
}

export type OpenerChargeOutcome =
  | { kind: "charged"; idempotent: boolean }
  | { kind: "dedup" }
  | { kind: "replay_mismatch" }
  | { kind: "replay_exhausted" }
  | {
    kind: "quota_exceeded";
    reason: "monthly_limit_exceeded" | "daily_limit_exceeded";
  }
  | { kind: "failed"; message: string };

/**
 * Codex P2：requestId 必須綁 payload——ledger 存 input hash，同 id 換輸入
 * 會被 RPC RAISE 擋下，防改造 client 付一次後無限免費重生成。
 * 對相同 body 決定性；不同 client 序列化差異只會讓 hash 不同 → 被擋，
 * 攻擊者玩 key 順序只會害到自己。
 */
export async function computeOpenerInputHash(args: {
  images: unknown;
  profileInfo: unknown;
}): Promise<string> {
  const canonical = JSON.stringify([
    args.images ?? null,
    args.profileInfo ?? null,
  ]);
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(canonical),
  );
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

export type OpenerChargeRpc = (
  fn: string,
  params: Record<string, unknown>,
) => Promise<{ data: unknown; error: { message?: string } | null }>;

export async function chargeOpenerQuota(args: {
  rpc: OpenerChargeRpc;
  userId: string;
  cost: number;
  monthlyLimit: number;
  dailyLimit: number;
  requestId: string | null;
  inputHash: string | null;
}): Promise<OpenerChargeOutcome> {
  const useIdempotent = args.requestId !== null;

  const { data, error } = useIdempotent
    ? await args.rpc("increment_usage_idempotent", {
      p_user_id: args.userId,
      p_messages: args.cost,
      p_monthly_limit: args.monthlyLimit,
      p_daily_limit: args.dailyLimit,
      p_request_id: args.requestId,
      p_input_hash: args.inputHash,
      p_replay_limit: OPENER_REPLAY_LIMIT,
    })
    : await args.rpc("increment_usage", {
      p_user_id: args.userId,
      p_messages: args.cost,
      p_monthly_limit: args.monthlyLimit,
      p_daily_limit: args.dailyLimit,
    });

  if (error) {
    const reason = classifyQuotaRpcError(error.message);
    if (reason) return { kind: "quota_exceeded", reason };
    if (error.message?.includes("OPENER_REQUEST_REPLAY_MISMATCH")) {
      return { kind: "replay_mismatch" };
    }
    if (error.message?.includes("OPENER_REQUEST_REPLAY_EXHAUSTED")) {
      return { kind: "replay_exhausted" };
    }
    return {
      kind: "failed",
      message: error.message || "opener charge rpc failed without message",
    };
  }

  // RPC 無錯時只有 `false` 明確代表 dedup；其餘（true / 驅動層怪形狀）一律
  // 視為已扣——兩者對用戶的回應相同，差別只在 telemetry。
  if (useIdempotent && data === false) {
    return { kind: "dedup" };
  }

  return { kind: "charged", idempotent: useIdempotent };
}
