// 模型呼叫限流源碼契約（docs/plans/2026-07-03-model-rate-limit-design.md）。
// practice-chat 有兩個 scope：practice_turn（三道 gate 後、DeepSeek 前）與
// practice_hint（replay preflight／quota gate／fresh claim 後、DeepSeek 前）。

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

Deno.test("practice_hint 限流：fresh claim 後、DeepSeek 前", () => {
  const preflightAt = indexOfRequired('.from("practice_hint_requests")');
  // 注意：裸字串 "claim_practice_hint_generation" 在 mapLedgerError（前段）
  // 也出現，錨定必須用實際 RPC 呼叫行。
  const claimAt = indexOfRequired(
    '.rpc("claim_practice_hint_generation", claimHintParams)',
  );
  const scopeAt = indexOfRequired('scope: "practice_hint"', claimAt);
  const generationAt = indexOfRequired(
    "const baseHintMessages = buildHintMessages({",
    scopeAt,
  );
  assert(
    scopeAt > preflightAt,
    "practice_hint 限流必須在 replay preflight 之後（replay 回放不打模型不計限流）",
  );
  assert(
    scopeAt > claimAt,
    "practice_hint 限流必須只計 fresh claim；claim-level replay 不得誤算",
  );
  assert(
    scopeAt < generationAt,
    "practice_hint 限流仍必須在 DeepSeek 生成之前",
  );
  assert(
    source.slice(scopeAt, generationAt).includes("releaseHintGeneration({"),
    "被限流的 fresh claim 必須釋放 request-aware latch",
  );
});

Deno.test("practice_debrief 限流：fresh claim 後、DeepSeek 前，replay 不誤算", () => {
  // Codex R1 P2：debrief 也打 DeepSeek，必須有 per-user backstop。
  const debriefGateAt = indexOfRequired("decideDebriefGate({");
  const scopeAt = indexOfRequired('scope: "practice_debrief"');
  // 裸函式名也會出現在 missing-RPC classifier，錨定實際呼叫。
  const claimAt = indexOfRequired(
    "claimData, error: claimError } = await supabase.rpc(",
  );
  const generationAt = indexOfRequired(
    "const baseDebriefMessages = buildDebriefMessages(",
    scopeAt,
  );
  assert(
    scopeAt > debriefGateAt,
    "practice_debrief 限流必須在 debrief 資格 gate（403）之後",
  );
  assert(
    scopeAt > claimAt,
    "practice_debrief 限流只計 fresh claim；claim-level replay 不得白吃限流槽",
  );
  assert(
    scopeAt < generationAt,
    "practice_debrief 限流仍必須在 DeepSeek 生成之前",
  );
  assert(
    source.slice(scopeAt, generationAt).includes(
      "releaseDebriefGeneration({",
    ),
    "被限流的 fresh claim 必須釋放 token-fenced reservation",
  );
});

Deno.test("practice 限流：enforceModelRateLimit＋fail-open telemetry", () => {
  assert(source.includes("enforceModelRateLimit("));
  assert(
    source.includes('logError("model_rate_limit_check_failed"'),
    "限流 RPC infra 錯誤必須 logError 後放行（fail-open），不得靜默",
  );
});
