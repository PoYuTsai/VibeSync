import {
  assertAlmostEquals,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  aggregate,
  type AiLogRow,
  MISSING_FIELDS,
  type SessionRow,
} from "./aggregate.ts";

const SESSIONS: SessionRow[] = [
  {
    practice_mode: "standard",
    ai_count: 3,
    sessions: 2,
    hints: 3,
    debriefs: 1,
    charged: 2,
  },
  {
    practice_mode: "standard",
    ai_count: 20,
    sessions: 1,
    hints: 5,
    debriefs: 1,
    charged: 1,
  },
  {
    practice_mode: "game",
    ai_count: 1,
    sessions: 4,
    hints: 0,
    debriefs: 0,
    charged: 3,
  },
  // 上限之外（未來若放寬 MAX_AI_REPLIES，落進溢位桶而不是消失）。
  {
    practice_mode: "game",
    ai_count: 25,
    sessions: 1,
    hints: 0,
    debriefs: 0,
    charged: 1,
  },
];

const AI_LOGS: AiLogRow[] = [
  {
    mode: "hint",
    practice_mode: "standard",
    model: "claude-sonnet-5",
    status: "success",
    fallback_used: false,
    call_rows: 8,
    retries: 2,
  },
  {
    mode: "debrief",
    practice_mode: "standard",
    model: "claude-sonnet-5",
    status: "success",
    fallback_used: false,
    call_rows: 2,
    retries: 0,
  },
  {
    mode: "hint",
    practice_mode: "game",
    model: "claude-haiku-4-5-20251001",
    status: "failed",
    fallback_used: true,
    call_rows: 1,
    retries: 0,
  },
  {
    mode: "debrief",
    practice_mode: "game",
    model: "deepseek-v4-flash",
    status: "success",
    fallback_used: false,
    call_rows: 3,
    retries: 0,
  },
];

Deno.test("場次按 practiceMode 匯總", () => {
  const stats = aggregate({
    range: { from: "2026-08-29", to: "2026-09-05" },
    sessions: SESSIONS,
    aiLogs: AI_LOGS,
  });
  assertEquals(stats.sessions.total, 8);
  assertEquals(stats.sessions.byMode, { standard: 3, game: 5 });
  assertEquals(stats.sessions.charged, 7);
  assertEquals(stats.hintTotal, 8);
  assertEquals(stats.debriefTotal, 2);
});

Deno.test("回合直方圖固定 1–20 並保留溢位桶", () => {
  const stats = aggregate({
    range: { from: "2026-08-29", to: "2026-09-05" },
    sessions: SESSIONS,
    aiLogs: [],
  });
  assertEquals(stats.turnHistogram.length, 20);
  assertEquals(stats.turnHistogram[0], { turns: 1, sessions: 4 });
  assertEquals(stats.turnHistogram[2], { turns: 3, sessions: 2 });
  assertEquals(stats.turnHistogram[19], { turns: 20, sessions: 1 });
  assertEquals(stats.turnOverflowSessions, 1);
  assertEquals(stats.zeroTurnSessions, 0);
});

Deno.test("成本：Sonnet 提示／檢討單次估價對得回 D14 成本表", () => {
  const stats = aggregate({
    range: { from: "2026-08-29", to: "2026-09-05" },
    sessions: [],
    aiLogs: [
      {
        mode: "hint",
        practice_mode: "standard",
        model: "claude-sonnet-5",
        status: "success",
        fallback_used: false,
        call_rows: 1,
        retries: 0,
      },
      {
        mode: "debrief",
        practice_mode: "standard",
        model: "claude-sonnet-5",
        status: "success",
        fallback_used: false,
        call_rows: 1,
        retries: 0,
      },
    ],
  });
  const hint = stats.generation.find((row) => row.mode === "hint")!;
  const debrief = stats.generation.find((row) => row.mode === "debrief")!;
  assertAlmostEquals(hint.costUsd!, 0.0074, 0.0001);
  assertAlmostEquals(debrief.costUsd!, 0.0154, 0.0001);
});

Deno.test("成本：重試算進呼叫數，DeepSeek 提示／檢討列不套聊天單價", () => {
  const stats = aggregate({
    range: { from: "2026-08-29", to: "2026-09-05" },
    sessions: SESSIONS,
    aiLogs: AI_LOGS,
  });
  const sonnetHint = stats.generation.find(
    (row) => row.mode === "hint" && row.model === "claude-sonnet-5",
  )!;
  assertEquals(sonnetHint.calls, 10);
  assertAlmostEquals(sonnetHint.costUsd!, 0.0742, 0.0002);

  const deepseek = stats.generation.find(
    (row) => row.model === "deepseek-v4-flash",
  )!;
  // 聊天輪的觀測單價不適用於 debrief（prompt／輸出長度差一個量級）。
  assertEquals(deepseek.mode, "debrief");
  assertEquals(deepseek.model.startsWith("deepseek"), true);
  assertEquals(deepseek.costUsd, null);
  assertEquals(stats.unpricedCalls, 3);
  // 8 場、Sonnet 提示 10 次＋檢討 2 次＋Haiku 提示 1 次（DeepSeek 3 次未估）。
  assertAlmostEquals(stats.totalCostUsd, 0.0742 + 0.0308 + 0.00371, 0.0005);
  assertAlmostEquals(stats.costPerSessionUsd!, stats.totalCostUsd / 8, 1e-9);
});

Deno.test("fallback 比率只看 ai_logs.fallback_used", () => {
  const stats = aggregate({
    range: { from: "2026-08-29", to: "2026-09-05" },
    sessions: SESSIONS,
    aiLogs: AI_LOGS,
  });
  assertEquals(stats.generationFallbackCalls, 1);
  assertEquals(stats.generationTotalCalls, 16);
});

Deno.test("沒有場次時每場成本為 null 而不是除以零", () => {
  const stats = aggregate({
    range: { from: "2026-08-29", to: "2026-09-05" },
    sessions: [],
    aiLogs: AI_LOGS,
  });
  assertEquals(stats.costPerSessionUsd, null);
});

Deno.test("損益：沒給付費人數就不算", () => {
  const stats = aggregate({
    range: { from: "2026-08-29", to: "2026-09-05" },
    sessions: SESSIONS,
    aiLogs: AI_LOGS,
  });
  assertEquals(stats.economics, null);
});

Deno.test("損益：有付費人數時算月營收與成本佔比", () => {
  const stats = aggregate({
    range: { from: "2026-08-29", to: "2026-09-05" },
    sessions: SESSIONS,
    aiLogs: AI_LOGS,
    payers: { starter: 10, essential: 5 },
  });
  const economics = stats.economics!;
  assertEquals(economics.monthlyRevenueTwd, 10 * 590 + 5 * 1290);
  assertAlmostEquals(
    economics.weeklyCostTwd,
    stats.totalCostUsd * 32,
    1e-9,
  );
  assertAlmostEquals(
    economics.monthlyCostTwd,
    economics.weeklyCostTwd * 52 / 12,
    1e-9,
  );
  assertAlmostEquals(
    economics.costShareOfRevenue!,
    economics.monthlyCostTwd / economics.monthlyRevenueTwd,
    1e-9,
  );
});

Deno.test("計畫要求但 DB 沒有、只能靠 function logs 的欄位逐條列出來", () => {
  const names = MISSING_FIELDS.map((field) => field.field);
  for (
    const expected of [
      "agency 介入率",
      "chatModel 分佈",
      "chatModelFallback 比率",
      "checkOutStructuralFail 比率",
      "checkOutRewriteInjected × checkOutStructuralFail 交叉比率",
      "readOnlyReply 比率",
    ]
  ) {
    assertEquals(names.includes(expected), true, expected);
  }
});
