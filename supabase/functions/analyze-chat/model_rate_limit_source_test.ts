// 模型呼叫限流源碼契約（docs/plans/2026-07-03-model-rate-limit-design.md）。
// analyze-chat 有兩個 scope：opener（preflight 後、quota gate 前、dedup replay
// 跳過）與 analyze（projected quota gate 後、所有模型呼叫前）。

import { assert } from "https://deno.land/std@0.168.0/testing/asserts.ts";

const source = await Deno.readTextFile(
  new URL("./index.ts", import.meta.url),
);

function indexOfRequired(snippet: string, from = 0): number {
  const index = source.indexOf(snippet, from);
  assert(index >= 0, `Expected index.ts to contain: ${snippet}`);
  return index;
}

Deno.test("opener 限流：在 replay preflight 後、opener quota gate 前，dedup replay 跳過", () => {
  const scopeAt = indexOfRequired('scope: "opener"');
  const preflightResolvedAt = indexOfRequired(
    "openerKnownDedupReplay = replayRow !== null",
  );
  const quotaGateAt = indexOfRequired("// Quota check for opener");
  assert(
    scopeAt > preflightResolvedAt,
    "opener 限流必須在 replay preflight 判定之後（mismatch/exhausted 400 不佔名額）",
  );
  assert(
    scopeAt < quotaGateAt,
    "opener 限流必須在 opener quota gate 之前（storm 在額度檢查前就封頂）",
  );

  // dedup replay（已扣過費、不打模型）絕不得計限流——cap 邊緣重試才活得下來
  const gateWindow = source.slice(preflightResolvedAt, scopeAt + 200);
  assert(
    gateWindow.includes("!openerKnownDedupReplay"),
    "opener 限流 gate 必須帶 !openerKnownDedupReplay（dedup replay 不打模型不計限流）",
  );
});

Deno.test("analyze 限流：在 projected quota gate 後、最早的模型呼叫前，recognizeOnly 不重複計", () => {
  const scopeAt = indexOfRequired('scope: "analyze"');
  const dailyGateAt = indexOfRequired('reason: "daily_limit_exceeded"');
  const earliestModelCallAt = indexOfRequired(
    "quickClaude = await callClaudeWithFallback(",
  );
  assert(
    scopeAt > dailyGateAt,
    "analyze 限流必須在 projected daily quota gate 之後（額度 429 語義優先）",
  );
  assert(
    scopeAt < earliestModelCallAt,
    "analyze 限流必須在最早的模型呼叫（quick）之前",
  );

  // recognizeOnly 已有 increment_ocr_usage 限流，analyze scope 不得重複計
  const gateWindow = source.slice(dailyGateAt, scopeAt + 200);
  assert(
    gateWindow.includes("!recognizeOnly"),
    "analyze 限流 gate 必須帶 !recognizeOnly（OCR 已有獨立限流，不重複計）",
  );
});

Deno.test("限流共用 helper 接線：enforceModelRateLimit＋fail-open telemetry", () => {
  assert(
    source.includes("enforceModelRateLimit("),
    "必須走 _shared/model_rate_limit.ts 的 enforceModelRateLimit",
  );
  assert(
    source.includes('logError("model_rate_limit_check_failed"'),
    "限流 RPC infra 錯誤必須 logError 後放行（fail-open），不得靜默",
  );
});
