/// 回覆微調的每日免費額度。
///
/// 兩段式，因為兩段的角色完全不同：
///
/// 1. 打模型之前的 **投影**（`projectRefineFreeAllowance`）：純讀取，只用來
///    決定要不要跳過月/日額度預檢、以及先報一個剩餘次數給面板。**不是權威**，
///    因此讀不到／資料壞掉時一律樂觀當免費——最壞只是多打一次模型，
///    真正的授權在第 2 段，不可能因為投影樂觀而多扣錢。
/// 2. 拿到有效結果之後的 **授權**（`consume_refine_free_allowance` RPC＋
///    `classifyRefineFreeConsumption`）：在 row lock 內原子扣減，這一段說了算。
///
/// 兩段之間會有競態（投影說免費、授權說用完了），這是預期的：授權結果會覆蓋
/// 投影，計費以授權為準。

/// Eric 拍板 2026-07-29。Edge 常數，改數字不需要 migration。
export const REFINE_FREE_DAILY_LIMIT = 10;

export type RefineFreeAllowanceRow = {
  day_utc?: unknown;
  used_count?: unknown;
} | null;

export type RefineFreeProjection = {
  usedToday: number;
  remaining: number;
  willBeFree: boolean;
};

/// UTC 日界，與本專案其他每日窗（increment_model_usage、OCR 限流、練習室
/// hint 額度）一致。
export function utcDayString(now: Date): string {
  return now.toISOString().slice(0, 10);
}

export function projectRefineFreeAllowance({
  row,
  todayUtc,
  dailyLimit = REFINE_FREE_DAILY_LIMIT,
}: {
  row: RefineFreeAllowanceRow;
  todayUtc: string;
  dailyLimit?: number;
}): RefineFreeProjection {
  const rawDay = typeof row?.day_utc === "string"
    ? row.day_utc.slice(0, 10)
    : null;
  const rawUsed = row?.used_count;
  // 換日即歸零；讀不到列、跨日、或計數壞掉都視為今天還沒用過。
  const usedToday = rawDay === todayUtc &&
      typeof rawUsed === "number" && Number.isInteger(rawUsed) && rawUsed >= 0
    ? rawUsed
    : 0;
  const remaining = Math.max(0, dailyLimit - usedToday);
  return { usedToday, remaining, willBeFree: remaining > 0 };
}

export type RefineFreeConsumption =
  | { kind: "granted"; used: number; remaining: number }
  | { kind: "exhausted"; used: number; remaining: number }
  | { kind: "unavailable"; message: string };

/// 把 `consume_refine_free_allowance` 的回傳整理成三種結果。
/// `exhausted` 不是錯誤，是「這次改成扣 1 則」的正常訊號。
export function classifyRefineFreeConsumption(
  data: unknown,
  error: { message?: string } | null,
): RefineFreeConsumption {
  if (error) {
    return {
      kind: "unavailable",
      message: error.message ?? "consume_refine_free_allowance failed",
    };
  }
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    return {
      kind: "unavailable",
      message: "invalid refine allowance response",
    };
  }
  const record = data as Record<string, unknown>;
  if (typeof record.granted !== "boolean") {
    return {
      kind: "unavailable",
      message: "missing refine allowance grant flag",
    };
  }
  const used = typeof record.used === "number" && Number.isInteger(record.used)
    ? record.used
    : 0;
  const remaining =
    typeof record.remaining === "number" && Number.isInteger(record.remaining)
      ? Math.max(0, record.remaining)
      : 0;
  return record.granted
    ? { kind: "granted", used, remaining }
    : { kind: "exhausted", used, remaining };
}

/// 額度函式掛掉時**不扣費**。呼叫端分不出「額度已經被扣掉但回應中斷」與
/// 「完全沒扣到」，此時改為扣 1 則的風險是使用者同時被吃掉一次免費額度又
/// 被扣錢；反過來的風險只是這次白送。錢的方向永遠選對使用者安全的那邊。
export function shouldChargeAfterRefineConsumption(
  consumption: RefineFreeConsumption,
): boolean {
  return consumption.kind === "exhausted";
}

export type RefineQuotaOutcome = {
  shouldCharge: boolean;
  /// true=真的拿到免費授權；false=額度用完改扣費；null=RPC 故障，白送但
  /// **不是**授權。三態分開才看得出白送了幾次。
  granted: boolean | null;
  quotaReason: string;
};

/// `unavailable` 與 `granted` 都不扣費，但它們不是同一件事。混成同一個 true
/// 會讓 telemetry 把 RPC 故障記成正常的每日免費，故障率就永遠是 0。
export function refineQuotaOutcomeFor(
  consumption: RefineFreeConsumption,
): RefineQuotaOutcome {
  const shouldCharge = shouldChargeAfterRefineConsumption(consumption);
  if (consumption.kind === "unavailable") {
    return {
      shouldCharge,
      granted: null,
      quotaReason: "refine_free_allowance_unavailable",
    };
  }
  return {
    shouldCharge,
    granted: !shouldCharge,
    quotaReason: shouldCharge ? "refine_reply_fixed_1" : "refine_free_daily",
  };
}
