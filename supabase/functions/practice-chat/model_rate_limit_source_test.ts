// 模型呼叫限流源碼契約（docs/plans/2026-07-03-model-rate-limit-design.md）。
// practice-chat 有兩個 scope：practice_turn（三道 gate 後、DeepSeek 前）與
// practice_hint（replay preflight／quota gate 後、claim latch 前）。

import { assert } from "https://deno.land/std@0.168.0/testing/asserts.ts";

const source = await Deno.readTextFile(
  new URL("./handler.ts", import.meta.url),
);

function indexOfRequired(snippet: string, from = 0): number {
  const index = source.indexOf(snippet, from);
  assert(index >= 0, `Expected handler.ts to contain: ${snippet}`);
  return index;
}

Deno.test("practice_turn 限流：在 chat 三道 gate 後、模型呼叫前", () => {
  const chatGateAt = indexOfRequired("decideChatGate({");
  const scopeAt = indexOfRequired('scope: "practice_turn"');
  const learningReadyAt = indexOfRequired(
    "await assertPracticeLearningReady",
    chatGateAt,
  );
  assert(
    scopeAt > chatGateAt,
    "practice_turn 限流必須在續聊 402／session cap 409／quota 429 三道 gate 之後",
  );
  assert(
    scopeAt < learningReadyAt,
    "practice_turn 限流必須在 DeepSeek 呼叫路徑（learning ready 檢查）之前",
  );
});

Deno.test("practice_hint 限流：在 hint replay preflight 後、claim latch 前", () => {
  const preflightAt = indexOfRequired('source: "preflight"');
  const scopeAt = indexOfRequired('scope: "practice_hint"');
  // 注意：裸字串 "claim_practice_hint_generation" 在 mapLedgerError（前段）
  // 也出現，錨定必須用實際 RPC 呼叫行。
  const claimAt = indexOfRequired(
    "claimHintError } = await supabase.rpc(",
  );
  assert(
    scopeAt > preflightAt,
    "practice_hint 限流必須在 replay preflight 之後（replay 回放不打模型不計限流）",
  );
  assert(
    scopeAt < claimAt,
    "practice_hint 限流必須在 claim latch 之前（被限流的請求不得占用 in-flight latch）",
  );
});

Deno.test("practice_debrief 限流：在 debrief gate 403 後、claim（吃名額）前", () => {
  // Codex R1 P2：debrief 也打 DeepSeek，必須有 per-user backstop。
  const debriefGateAt = indexOfRequired("decideDebriefGate({");
  const scopeAt = indexOfRequired('scope: "practice_debrief"');
  const claimAt = indexOfRequired('"claim_practice_debrief"');
  assert(
    scopeAt > debriefGateAt,
    "practice_debrief 限流必須在 debrief 資格 gate（403）之後",
  );
  assert(
    scopeAt < claimAt,
    "practice_debrief 限流必須在 claim_practice_debrief 之前（被限流不得吃 MAX_DEBRIEFS 名額）",
  );
});

Deno.test("practice 限流：enforceModelRateLimit＋fail-open telemetry", () => {
  assert(source.includes("enforceModelRateLimit("));
  assert(
    source.includes('logError("model_rate_limit_check_failed"'),
    "限流 RPC infra 錯誤必須 logError 後放行（fail-open），不得靜默",
  );
});
