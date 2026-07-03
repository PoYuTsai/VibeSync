// supabase/functions/_shared/model_rate_limit.ts
//
// 全面模型呼叫 per-user 限流共用 helper（docs/plans/2026-07-03-model-rate-limit-design.md）。
// 六個會打模型（或會扣費）的入口共用一層與訂閱額度完全獨立的節流：計數在
// DB RPC `increment_model_usage`（(user_id, scope) 複合鍵、FOR UPDATE＋超限
// RAISE），這裡只放 Edge 側的常數、訊息判別與回包。既有 recognizeOnly OCR
// 限流（ocr_rate_limit.ts）已上線不動、不遷入。

/** Eric 拍板（2026-07-03）：各面差異化上限。權威在 Edge，SQL 不寫死。 */
export const MODEL_RATE_LIMITS = {
  opener: { perMinute: 3, perDay: 30 },
  analyze: { perMinute: 6, perDay: 60 },
  coach_chat: { perMinute: 10, perDay: 300 },
  coach_follow_up: { perMinute: 6, perDay: 60 },
  practice_turn: { perMinute: 12, perDay: 400 },
  practice_hint: { perMinute: 4, perDay: 40 },
} as const;

export type ModelRateLimitScope = keyof typeof MODEL_RATE_LIMITS;

export type ModelRateLimitReason = "minute" | "daily";

/**
 * increment_model_usage RAISE 訊息的 Edge 側偵測。PostgREST 會把 RAISE 訊息
 * 包進較長字串，用 includes 抓（同 classifyOcrRateLimitError 慣例）。
 * 非超限錯誤回 null → 呼叫端 fail-open 放行。
 */
export function classifyModelRateLimitError(
  message: string | null | undefined,
): ModelRateLimitReason | null {
  if (!message) return null;
  if (message.includes("MODEL_RATE_LIMITED_MINUTE")) return "minute";
  if (message.includes("MODEL_RATE_LIMITED_DAILY")) return "daily";
  return null;
}

/**
 * 429 回包。絕不帶 monthlyLimit/dailyLimit（含 remaining/quotaNeeded）等訂閱
 * 額度鍵——client `_quotaExceptionFrom429` 靠那些鍵判 paywall 例外，帶了會把
 * 限流誤導成升級 CTA。retryable=false 防自動重試風暴。
 */
export function buildModelRateLimitedPayload(reason: ModelRateLimitReason): {
  error: string;
  code: "MODEL_RATE_LIMITED";
  message: string;
  retryable: false;
} {
  return {
    error: "Model rate limited",
    code: "MODEL_RATE_LIMITED",
    message: reason === "minute"
      ? "操作太頻繁，請稍等一分鐘再試。"
      : "今日使用次數已達上限，明天早上 8 點恢復。",
    retryable: false,
  };
}

type RpcClient = {
  rpc(
    fn: string,
    args: Record<string, unknown>,
  ): PromiseLike<{ error: { message?: string } | null }>;
};

export type ModelRateLimitResult =
  | { kind: "allowed" }
  | {
    kind: "limited";
    reason: ModelRateLimitReason;
    payload: ReturnType<typeof buildModelRateLimitedPayload>;
  }
  | { kind: "failOpen"; errorMessage: string };

/**
 * 共用限流入口：測試帳號 bypass、計 attempt 不計 success（超限 RAISE 令
 * RPC 整筆 TX rollback）。infra 錯誤（非超限 RAISE）回 failOpen——RPC 失敗
 * 非用戶可誘發，漏計一次成本上界仍近似成立；呼叫端必留 telemetry。
 */
export async function enforceModelRateLimit(opts: {
  supabase: RpcClient;
  userId: string;
  scope: ModelRateLimitScope;
  isTestAccount: boolean;
}): Promise<ModelRateLimitResult> {
  if (opts.isTestAccount) return { kind: "allowed" };
  const limits = MODEL_RATE_LIMITS[opts.scope];
  const { error } = await opts.supabase.rpc("increment_model_usage", {
    p_user_id: opts.userId,
    p_scope: opts.scope,
    p_minute_limit: limits.perMinute,
    p_daily_limit: limits.perDay,
  });
  if (!error) return { kind: "allowed" };
  const reason = classifyModelRateLimitError(error.message);
  if (reason) {
    return {
      kind: "limited",
      reason,
      payload: buildModelRateLimitedPayload(reason),
    };
  }
  return { kind: "failOpen", errorMessage: error.message ?? "unknown" };
}
