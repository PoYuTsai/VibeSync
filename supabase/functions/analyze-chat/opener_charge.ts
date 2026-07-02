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

export type OpenerChargeOutcome =
  | { kind: "charged"; idempotent: boolean }
  | { kind: "dedup" }
  | {
    kind: "quota_exceeded";
    reason: "monthly_limit_exceeded" | "daily_limit_exceeded";
  }
  | { kind: "failed"; message: string };

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
}): Promise<OpenerChargeOutcome> {
  const useIdempotent = args.requestId !== null;

  const { data, error } = useIdempotent
    ? await args.rpc("increment_usage_idempotent", {
      p_user_id: args.userId,
      p_messages: args.cost,
      p_monthly_limit: args.monthlyLimit,
      p_daily_limit: args.dailyLimit,
      p_request_id: args.requestId,
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
