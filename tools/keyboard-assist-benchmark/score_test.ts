import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  aggregateBenchmark,
  latencyPercentile,
  quoteLeakUpperBound95,
  validateAssistResult,
  validateReadyResult,
} from "./score.ts";

Deno.test("latencyPercentile uses nearest-rank so launch p95 is not understated", () => {
  const samples = Array.from({ length: 20 }, (_, index) => (index + 1) * 100);

  assertEquals(latencyPercentile(samples, 0.5), 1000);
  assertEquals(latencyPercentile(samples, 0.95), 1900);
  assertEquals(latencyPercentile([], 0.95), null);
});

Deno.test("quoteLeakUpperBound95 reports uncertainty even when no leak was observed", () => {
  const upperBound = quoteLeakUpperBound95(0, 100);

  assert(upperBound !== null);
  assert(upperBound > 0);
  assert(upperBound < 0.03);
  assertEquals(quoteLeakUpperBound95(0, 0), null);
});

Deno.test("validateReadyResult accepts the frozen three-strategy public contract", () => {
  const result = {
    contractVersion: "keyboard-assist-v1",
    requestId: "550e8400-e29b-41d4-a716-446655440000",
    status: "ready",
    source: {
      scope: "screenshot_only",
      messageCount: 4,
      confidence: "high",
      sideConfidence: "high",
    },
    turnState: "reply_due",
    cue: "對方分享週末安排，適合輕鬆延伸。",
    uncertainty: null,
    options: [
      {
        strategy: "keep_pace",
        text: "聽起來很充實，哪一段是你最期待的？",
        why: "先接住情緒，再用開放問題延伸。",
        effect: "自然延續話題",
      },
      {
        strategy: "build_connection",
        text: "這行程表有點強，我先預約一個精華版心得 😄",
        why: "以輕鬆調侃增加互動感。",
        effect: "提高互動溫度",
      },
      {
        strategy: "move_forward",
        text: "你週日如果有空，要不要一起喝杯咖啡？",
        why: "在對方提到週末後，清楚提出低壓邀請。",
        effect: "直接測試見面意願",
      },
    ],
  };

  assertEquals(validateReadyResult(result), []);
});

Deno.test("validateReadyResult rejects duplicate strategies, unsupported facts, and markdown", () => {
  const result = {
    contractVersion: "keyboard-assist-v1",
    requestId: "550e8400-e29b-41d4-a716-446655440000",
    status: "ready",
    source: {
      scope: "screenshot_only",
      messageCount: 4,
      confidence: "high",
      sideConfidence: "high",
    },
    turnState: "reply_due",
    cue: "**她一定很喜歡你**",
    uncertainty: null,
    options: [
      {
        strategy: "keep_pace",
        text: "可以呀",
        why: "因為她說過你住台北。",
        effect: "自然",
      },
      {
        strategy: "keep_pace",
        text: "可以呀",
        why: "同一個策略。",
        effect: "自然",
      },
      {
        strategy: "move_forward",
        text: "```json\n{}\n```",
        why: "raw JSON",
        effect: "推進",
      },
    ],
  };

  const issues = validateReadyResult(result, {
    forbiddenSubstrings: ["住台北"],
  });

  assert(issues.includes("markdown_not_allowed"));
  assert(issues.includes("strategy_not_distinct"));
  assert(issues.includes("text_not_distinct"));
  assert(issues.includes("unsupported_fact"));
});

Deno.test("v1 ready result cannot claim linked-partner scope", () => {
  const result = {
    contractVersion: "keyboard-assist-v1",
    requestId: "550e8400-e29b-41d4-a716-446655440000",
    status: "ready",
    source: {
      scope: "linked_partner",
      messageCount: 4,
      confidence: "high",
      sideConfidence: "high",
    },
    turnState: "reply_due",
    cue: "只根據這張截圖。",
    uncertainty: null,
    options: [
      {
        strategy: "keep_pace",
        text: "好呀",
        why: "接住話題",
        effect: "自然",
      },
      {
        strategy: "build_connection",
        text: "聽起來不錯耶",
        why: "增加溫度",
        effect: "親近",
      },
      {
        strategy: "move_forward",
        text: "那週日見？",
        why: "明確推進",
        effect: "直接",
      },
    ],
  };

  assert(validateReadyResult(result).includes("invalid_source_scope"));
});

Deno.test("speaker confirmation requires exact no-transcript v1 shape", () => {
  const valid = {
    contractVersion: "keyboard-assist-v1",
    requestId: "550e8400-e29b-41d4-a716-446655440000",
    status: "needs_speaker_confirmation",
    suggestedMySide: "right",
    sideConfidence: "low",
  };
  assertEquals(validateAssistResult(valid), []);

  const missingNullable = { ...valid };
  delete (missingNullable as Record<string, unknown>).suggestedMySide;
  assert(
    validateAssistResult(missingNullable).includes(
      "invalid_speaker_confirmation_shape",
    ),
  );

  assert(
    validateAssistResult({ ...valid, suggestedMySide: null }).includes(
      "invalid_suggested_side",
    ),
  );

  const leaked = { ...valid, transcript: "must never be returned or stored" };
  assert(
    validateAssistResult(leaked).includes(
      "invalid_speaker_confirmation_shape",
    ),
  );
});

Deno.test("aggregateBenchmark keeps ready rate, latency, leak bound, and violations separate", () => {
  const summary = aggregateBenchmark([
    {
      caseId: "a",
      runId: "a-1",
      durationMs: 8000,
      status: "ready",
      automatedIssues: [],
      quotedPreviewLeaks: 0,
      quotedPreviewInstances: 4,
    },
    {
      caseId: "b",
      runId: "b-1",
      durationMs: 18000,
      status: "ready",
      automatedIssues: ["unsupported_fact"],
      quotedPreviewLeaks: 0,
      quotedPreviewInstances: 6,
    },
    {
      caseId: "c",
      runId: "c-1",
      durationMs: 25000,
      status: "timeout",
      automatedIssues: [],
      quotedPreviewLeaks: 0,
      quotedPreviewInstances: 0,
    },
  ]);

  assertEquals(summary.totalRuns, 3);
  assertEquals(summary.readyRuns, 2);
  assertEquals(summary.readyRate, 2 / 3);
  assertEquals(summary.freshLatencyMs.p50, 18000);
  assertEquals(summary.freshLatencyMs.p95, 25000);
  assertEquals(summary.automatedViolationRuns, 1);
  assertEquals(summary.quotedPreview.instances, 10);
  assertEquals(summary.quotedPreview.observedLeaks, 0);
  assert(summary.quotedPreview.upperBound95! > 0);
});
