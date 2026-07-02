// supabase/functions/analyze-chat/ocr_rate_limit_test.ts
//
// recognizeOnly OCR 限流純 helper 契約（設計文件：
// docs/plans/2026-07-02-ocr-rate-limit-design.md）。
// DB 語義（FOR UPDATE / RAISE / 窗口重置）在 migration，由 Codex 雙審把關。

import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  buildOcrRateLimitedPayload,
  classifyOcrRateLimitError,
  OCR_RATE_LIMIT_PER_DAY,
  OCR_RATE_LIMIT_PER_MINUTE,
} from "./ocr_rate_limit.ts";

// ---------------------------------------------------------------------------
// 常數（I7：權威在 Edge，Eric 拍板 6/分、60/天）
// ---------------------------------------------------------------------------

Deno.test("rate limit constants match Eric's decision (6/min, 60/day)", () => {
  assertEquals(OCR_RATE_LIMIT_PER_MINUTE, 6);
  assertEquals(OCR_RATE_LIMIT_PER_DAY, 60);
});

// ---------------------------------------------------------------------------
// classifyOcrRateLimitError — PostgREST 包裝訊息用 includes 抓
// （同 classifyQuotaRpcError / PRACTICE_DRAW_* 慣例）
// ---------------------------------------------------------------------------

Deno.test("classify - minute RAISE wrapped by PostgREST is detected", () => {
  assertEquals(
    classifyOcrRateLimitError(
      'unhandled exception: "OCR_RATE_LIMITED_MINUTE" (SQLSTATE P0001)',
    ),
    "minute",
  );
});

Deno.test("classify - daily RAISE wrapped by PostgREST is detected", () => {
  assertEquals(
    classifyOcrRateLimitError("OCR_RATE_LIMITED_DAILY"),
    "daily",
  );
});

Deno.test("classify - unrelated / infra errors return null (I6 fail-open)", () => {
  assertEquals(
    classifyOcrRateLimitError(
      "Could not find the function public.increment_ocr_usage in the schema cache",
    ),
    null,
  );
  assertEquals(classifyOcrRateLimitError("connection refused"), null);
});

Deno.test("classify - null / undefined / empty return null", () => {
  assertEquals(classifyOcrRateLimitError(null), null);
  assertEquals(classifyOcrRateLimitError(undefined), null);
  assertEquals(classifyOcrRateLimitError(""), null);
});

Deno.test("classify - QUOTA_EXCEEDED_* (訂閱額度) is NOT ours (I3)", () => {
  assertEquals(classifyOcrRateLimitError("QUOTA_EXCEEDED_MONTHLY"), null);
  assertEquals(classifyOcrRateLimitError("QUOTA_EXCEEDED_DAILY"), null);
});

// ---------------------------------------------------------------------------
// buildOcrRateLimitedPayload — 429 payload 形狀
// ---------------------------------------------------------------------------

Deno.test("payload - carries OCR_RATE_LIMITED code and readable zh-TW message", () => {
  const minute = buildOcrRateLimitedPayload("minute");
  assertEquals(minute.code, "OCR_RATE_LIMITED");
  assertEquals(minute.error, "OCR rate limited");
  assert(minute.message.includes("太頻繁"));

  const daily = buildOcrRateLimitedPayload("daily");
  assertEquals(daily.code, "OCR_RATE_LIMITED");
  assert(daily.message.includes("今日"));
  assert(daily.message.includes("早上 8 點"));
});

Deno.test("payload - retryable=false so clients never auto-retry (I5)", () => {
  assertEquals(buildOcrRateLimitedPayload("minute").retryable, false);
  assertEquals(buildOcrRateLimitedPayload("daily").retryable, false);
});

Deno.test("payload - NEVER carries monthlyLimit/dailyLimit keys (I4: no paywall misfire)", () => {
  for (const reason of ["minute", "daily"] as const) {
    const payload = buildOcrRateLimitedPayload(reason) as Record<
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
