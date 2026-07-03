// 模型呼叫限流源碼契約（docs/plans/2026-07-03-model-rate-limit-design.md）。
// coach_follow_up scope：quota gate 429 之後、runCoachFollowUp（模型呼叫）之前。

import { assert } from "https://deno.land/std@0.168.0/testing/asserts.ts";

const source = await Deno.readTextFile(
  new URL("./index.ts", import.meta.url),
);

function indexOfRequired(snippet: string): number {
  const index = source.indexOf(snippet);
  assert(index >= 0, `Expected index.ts to contain: ${snippet}`);
  return index;
}

Deno.test("coach_follow_up 限流：在 quota gate 後、runCoachFollowUp 模型呼叫前", () => {
  const scopeAt = indexOfRequired('scope: "coach_follow_up"');
  const quotaGateAt = indexOfRequired(
    'logWarn("coach_follow_up_quota_exceeded"',
  );
  const modelCallAt = indexOfRequired("runCoachFollowUp(");
  assert(
    scopeAt > quotaGateAt,
    "coach_follow_up 限流必須在 quota gate 之後（額度 429 語義優先）",
  );
  assert(
    scopeAt < modelCallAt,
    "coach_follow_up 限流必須在 runCoachFollowUp（模型呼叫）之前",
  );
});

Deno.test("coach_follow_up 限流：enforceModelRateLimit＋fail-open telemetry", () => {
  assert(source.includes("enforceModelRateLimit("));
  assert(
    source.includes('logError("model_rate_limit_check_failed"'),
    "限流 RPC infra 錯誤必須 logError 後放行（fail-open），不得靜默",
  );
});
