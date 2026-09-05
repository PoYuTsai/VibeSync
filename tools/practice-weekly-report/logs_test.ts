import {
  assertAlmostEquals,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { aggregateLogs, type LogRow, logTimestampToIso } from "./aggregate.ts";

/** 一行 log ＝ `logger.ts` 的 `JSON.stringify({level, event, ...data})`。 */
function line(payload: Record<string, unknown>): string {
  return JSON.stringify({
    level: "info",
    event: "practice_chat_succeeded",
    ...payload,
  });
}

function row(timestamp: string, message: string): LogRow {
  return { timestamp, event_message: message };
}

const ROWS: LogRow[] = [
  // 介入、Haiku、有 usage、check_out 結構後檢查命中且帶改寫指令。
  row(
    "2026-08-30T01:00:00Z",
    line({
      practiceMode: "game",
      chatModel: "haiku",
      chatModelCalls: { haiku: 2, deepseek: 0 },
      chatModelFallback: true,
      chatModelUsage: {
        inputTokens: 900,
        cacheReadInputTokens: 8100,
        cacheCreationInputTokens: 0,
        outputTokens: 200,
      },
      conversationAgency: {
        applied: true,
        checkOutRewriteInjected: true,
        checkOutStructuralFail: true,
      },
    }),
  ),
  // 沒介入、DeepSeek。
  row(
    "2026-08-31T02:00:00Z",
    line({
      practiceMode: "standard",
      chatModel: "deepseek",
      chatModelCalls: { haiku: 0, deepseek: 1 },
      conversationAgency: { applied: false },
    }),
  ),
  // 介入、forced read_only：一支模型都沒打。
  row(
    "2026-09-01T03:00:00Z",
    line({
      practiceMode: "game",
      chatModel: "none",
      chatModelCalls: { haiku: 0, deepseek: 0 },
      conversationAgency: { applied: true, readOnlyReply: true },
    }),
  ),
  // 帶改寫指令但第二發過了（交叉比率的分母，不是分子）。
  row(
    "2026-09-02T04:00:00Z",
    line({
      practiceMode: "game",
      chatModel: "haiku",
      chatModelCalls: { haiku: 1, deepseek: 1 },
      chatModelUsage: {
        inputTokens: 100,
        cacheReadInputTokens: 0,
        cacheCreationInputTokens: 0,
        outputTokens: 100,
      },
      conversationAgency: { applied: true, checkOutRewriteInjected: true },
    }),
  ),
  // 旗標全關：連 chatModel／conversationAgency 兩個 key 都不存在。
  row("2026-09-03T05:00:00Z", line({ practiceMode: "standard" })),
  // 別的事件、壞 JSON、空行——都要跳過。
  row(
    "2026-09-03T06:00:00Z",
    JSON.stringify({ level: "info", event: "practice_chat_failed" }),
  ),
  row("2026-09-03T07:00:00Z", "not json at all"),
  row("2026-09-03T08:00:00Z", ""),
];

Deno.test("只吃 practice_chat_succeeded，壞行跳過並計數", () => {
  const logs = aggregateLogs(ROWS);
  assertEquals(logs.rowsReturned, 8);
  assertEquals(logs.turns, 5);
  assertEquals(logs.skippedOtherEvent, 1);
  assertEquals(logs.skippedUnparsable, 2);
});

Deno.test("涵蓋範圍印最早／最晚 timestamp（保留期看得出來）", () => {
  const logs = aggregateLogs(ROWS);
  assertEquals(logs.earliest, "2026-08-30T01:00:00Z");
  assertEquals(logs.latest, "2026-09-03T08:00:00Z");
});

Deno.test("空結果不當錯誤：全部歸零、涵蓋範圍是 null", () => {
  const logs = aggregateLogs([]);
  assertEquals(logs.rowsReturned, 0);
  assertEquals(logs.turns, 0);
  assertEquals(logs.earliest, null);
  assertEquals(logs.latest, null);
  assertEquals(logs.agencyAppliedRate, null);
  assertEquals(logs.chatCostUsd, 0);
});

Deno.test("agency 介入率的分母只算帶 conversationAgency 的輪", () => {
  const logs = aggregateLogs(ROWS);
  assertEquals(logs.agencyTurns, 4);
  assertEquals(logs.agencyApplied, 3);
  assertAlmostEquals(logs.agencyAppliedRate!, 3 / 4, 1e-9);
});

Deno.test("chatModel 分佈與 fallback 比率只算帶 chatModel 的輪", () => {
  const logs = aggregateLogs(ROWS);
  assertEquals(logs.chatModelTurns, 4);
  assertEquals(logs.chatModelDistribution, {
    haiku: 2,
    deepseek: 1,
    none: 1,
  });
  assertEquals(logs.chatModelCalls, { haiku: 3, deepseek: 2 });
  assertEquals(logs.chatModelFallbackTurns, 1);
  assertAlmostEquals(logs.chatModelFallbackRate!, 1 / 4, 1e-9);
});

Deno.test("聊天成本＝Haiku usage 累加估價 ＋ DeepSeek 每次觀測單價", () => {
  const logs = aggregateLogs(ROWS);
  assertEquals(logs.chatModelUsage, {
    inputTokens: 1000,
    cacheReadInputTokens: 8100,
    cacheCreationInputTokens: 0,
    outputTokens: 300,
  });
  // (1000×$1 + 300×$5 + 8100×$0.1)／1M ＋ 2 次 DeepSeek × $0.0000294
  const expected = (1000 * 1 + 300 * 5 + 8100 * 0.1) / 1_000_000 +
    2 * 0.0000294;
  assertAlmostEquals(logs.chatCostUsd, expected, 1e-12);
});

Deno.test("check_out 結構後檢查與交叉比率、readOnlyReply 比率", () => {
  const logs = aggregateLogs(ROWS);
  assertEquals(logs.checkOutStructuralFail, 1);
  assertAlmostEquals(logs.checkOutStructuralFailRate!, 1 / 4, 1e-9);
  assertEquals(logs.checkOutRewriteInjected, 2);
  assertEquals(logs.checkOutRewriteAndFail, 1);
  assertAlmostEquals(logs.checkOutRewriteFailRate!, 1 / 2, 1e-9);
  assertEquals(logs.readOnlyReply, 1);
  assertAlmostEquals(logs.readOnlyReplyRate!, 1 / 4, 1e-9);
});

Deno.test("沒有任何帶旗標的輪時比率是 null 而不是 0/0", () => {
  const logs = aggregateLogs([
    row("2026-09-03T05:00:00Z", line({ practiceMode: "standard" })),
  ]);
  assertEquals(logs.agencyAppliedRate, null);
  assertEquals(logs.chatModelFallbackRate, null);
  assertEquals(logs.checkOutRewriteFailRate, null);
  assertEquals(logs.readOnlyReplyRate, null);
});

Deno.test("Logs Explorer 的微秒整數 timestamp 換算成 ISO", () => {
  assertEquals(logTimestampToIso(1788558109700000), "2026-09-04T21:41:49.700Z");
  assertEquals(
    logTimestampToIso("2026-09-01T00:00:00Z"),
    "2026-09-01T00:00:00Z",
  );
  assertEquals(logTimestampToIso(null), null);
  assertEquals(logTimestampToIso(0), null);
  assertEquals(logTimestampToIso("nonsense"), "nonsense");
});

Deno.test("涵蓋範圍吃得下微秒 timestamp", () => {
  const logs = aggregateLogs([
    { timestamp: 1788558109700000, event_message: line({}) },
    { timestamp: 1788471709700000, event_message: line({}) },
  ]);
  assertEquals(logs.earliest, "2026-09-03T21:41:49.700Z");
  assertEquals(logs.latest, "2026-09-04T21:41:49.700Z");
});

Deno.test("被限流的日子原樣帶進統計", () => {
  const logs = aggregateLogs([], ["2026-09-01", "2026-09-02"]);
  assertEquals(logs.missingDays, ["2026-09-01", "2026-09-02"]);
});
