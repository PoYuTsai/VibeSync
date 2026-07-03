// supabase/functions/_shared/model_rate_limit_test.ts
//
// 全面模型呼叫 per-user 限流共用 helper 契約（設計文件：
// docs/plans/2026-07-03-model-rate-limit-design.md）。
// DB 語義（FOR UPDATE / RAISE / 窗口重置 / scope 隔離）在 migration
// `increment_model_usage`，由 prod SQL 實測＋Codex 雙審把關。

import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  buildModelRateLimitedPayload,
  classifyModelRateLimitError,
  enforceModelRateLimit,
  MODEL_RATE_LIMITS,
  type ModelRateLimitScope,
} from "./model_rate_limit.ts";

// ---------------------------------------------------------------------------
// 常數（權威在 Edge，Eric 拍板 2026-07-03 差異化預設組）
// ---------------------------------------------------------------------------

Deno.test("limits match Eric's decision per scope", () => {
  assertEquals(MODEL_RATE_LIMITS.opener, { perMinute: 3, perDay: 30 });
  assertEquals(MODEL_RATE_LIMITS.analyze, { perMinute: 6, perDay: 60 });
  assertEquals(MODEL_RATE_LIMITS.coach_chat, { perMinute: 10, perDay: 300 });
  assertEquals(MODEL_RATE_LIMITS.coach_follow_up, { perMinute: 6, perDay: 60 });
  assertEquals(MODEL_RATE_LIMITS.practice_turn, { perMinute: 12, perDay: 400 });
  assertEquals(MODEL_RATE_LIMITS.practice_hint, { perMinute: 4, perDay: 40 });
});

// ---------------------------------------------------------------------------
// classifyModelRateLimitError — PostgREST 包裝訊息用 includes 抓
// （同 classifyOcrRateLimitError 慣例）
// ---------------------------------------------------------------------------

Deno.test("classify - minute RAISE wrapped by PostgREST is detected", () => {
  assertEquals(
    classifyModelRateLimitError(
      'unhandled exception: "MODEL_RATE_LIMITED_MINUTE" (SQLSTATE P0001)',
    ),
    "minute",
  );
});

Deno.test("classify - daily RAISE is detected", () => {
  assertEquals(
    classifyModelRateLimitError("MODEL_RATE_LIMITED_DAILY"),
    "daily",
  );
});

Deno.test("classify - unrelated / infra errors return null (fail-open)", () => {
  assertEquals(
    classifyModelRateLimitError(
      "Could not find the function public.increment_model_usage in the schema cache",
    ),
    null,
  );
  assertEquals(classifyModelRateLimitError("connection refused"), null);
  assertEquals(classifyModelRateLimitError(null), null);
  assertEquals(classifyModelRateLimitError(undefined), null);
  assertEquals(classifyModelRateLimitError(""), null);
});

Deno.test("classify - QUOTA_EXCEEDED_* / OCR_RATE_LIMITED_* are NOT ours", () => {
  assertEquals(classifyModelRateLimitError("QUOTA_EXCEEDED_MONTHLY"), null);
  assertEquals(classifyModelRateLimitError("QUOTA_EXCEEDED_DAILY"), null);
  assertEquals(classifyModelRateLimitError("OCR_RATE_LIMITED_MINUTE"), null);
  assertEquals(classifyModelRateLimitError("OCR_RATE_LIMITED_DAILY"), null);
});

// ---------------------------------------------------------------------------
// buildModelRateLimitedPayload — 429 payload 形狀
// ---------------------------------------------------------------------------

Deno.test("payload - carries MODEL_RATE_LIMITED code and readable zh-TW message", () => {
  const minute = buildModelRateLimitedPayload("minute");
  assertEquals(minute.code, "MODEL_RATE_LIMITED");
  assertEquals(minute.error, "Model rate limited");
  assert(minute.message.includes("太頻繁"));

  const daily = buildModelRateLimitedPayload("daily");
  assertEquals(daily.code, "MODEL_RATE_LIMITED");
  assert(daily.message.includes("今日"));
  assert(daily.message.includes("早上 8 點"));
});

Deno.test("payload - retryable=false so clients never auto-retry", () => {
  assertEquals(buildModelRateLimitedPayload("minute").retryable, false);
  assertEquals(buildModelRateLimitedPayload("daily").retryable, false);
});

Deno.test("payload - NEVER carries quota keys (no paywall misfire)", () => {
  for (const reason of ["minute", "daily"] as const) {
    const payload = buildModelRateLimitedPayload(reason) as Record<
      string,
      unknown
    >;
    assertFalse("monthlyLimit" in payload);
    assertFalse("dailyLimit" in payload);
    assertFalse("monthlyRemaining" in payload);
    assertFalse("dailyRemaining" in payload);
    assertFalse("quotaNeeded" in payload);
  }
});

// ---------------------------------------------------------------------------
// enforceModelRateLimit — RPC 呼叫＋判定的共用入口
// ---------------------------------------------------------------------------

type RpcCall = { fn: string; args: Record<string, unknown> };

function fakeSupabase(errorMessage: string | null) {
  const calls: RpcCall[] = [];
  return {
    calls,
    client: {
      rpc(fn: string, args: Record<string, unknown>) {
        calls.push({ fn, args });
        return Promise.resolve({
          error: errorMessage === null ? null : { message: errorMessage },
        });
      },
    },
  };
}

Deno.test("enforce - test account bypasses without touching RPC", async () => {
  const fake = fakeSupabase(null);
  const result = await enforceModelRateLimit({
    supabase: fake.client,
    userId: "u1",
    scope: "opener",
    isTestAccount: true,
  });
  assertEquals(result.kind, "allowed");
  assertEquals(fake.calls.length, 0);
});

Deno.test("enforce - calls increment_model_usage with scope's own limits", async () => {
  const fake = fakeSupabase(null);
  const result = await enforceModelRateLimit({
    supabase: fake.client,
    userId: "u1",
    scope: "practice_turn",
    isTestAccount: false,
  });
  assertEquals(result.kind, "allowed");
  assertEquals(fake.calls, [{
    fn: "increment_model_usage",
    args: {
      p_user_id: "u1",
      p_scope: "practice_turn",
      p_minute_limit: 12,
      p_daily_limit: 400,
    },
  }]);
});

Deno.test("enforce - minute RAISE maps to limited with 429 payload", async () => {
  const fake = fakeSupabase(
    'unhandled exception: "MODEL_RATE_LIMITED_MINUTE" (SQLSTATE P0001)',
  );
  const result = await enforceModelRateLimit({
    supabase: fake.client,
    userId: "u1",
    scope: "coach_chat",
    isTestAccount: false,
  });
  assert(result.kind === "limited");
  assertEquals(result.reason, "minute");
  assertEquals(result.payload.code, "MODEL_RATE_LIMITED");
});

Deno.test("enforce - daily RAISE maps to limited daily", async () => {
  const fake = fakeSupabase("MODEL_RATE_LIMITED_DAILY");
  const result = await enforceModelRateLimit({
    supabase: fake.client,
    userId: "u1",
    scope: "analyze",
    isTestAccount: false,
  });
  assert(result.kind === "limited");
  assertEquals(result.reason, "daily");
});

Deno.test("enforce - infra error fails open with errorMessage for telemetry", async () => {
  const fake = fakeSupabase("connection refused");
  const result = await enforceModelRateLimit({
    supabase: fake.client,
    userId: "u1",
    scope: "coach_follow_up",
    isTestAccount: false,
  });
  assert(result.kind === "failOpen");
  assertEquals(result.errorMessage, "connection refused");
});

Deno.test("enforce - every scope in MODEL_RATE_LIMITS is accepted", async () => {
  for (const scope of Object.keys(MODEL_RATE_LIMITS) as ModelRateLimitScope[]) {
    const fake = fakeSupabase(null);
    const result = await enforceModelRateLimit({
      supabase: fake.client,
      userId: "u1",
      scope,
      isTestAccount: false,
    });
    assertEquals(result.kind, "allowed");
    assertEquals(fake.calls[0].args.p_scope, scope);
  }
});
