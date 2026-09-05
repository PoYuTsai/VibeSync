import {
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { aggregate } from "./aggregate.ts";
import { renderReport } from "./render.ts";

const RANGE = { from: "2026-08-29", to: "2026-09-05" };

const STATS = aggregate({
  range: RANGE,
  sessions: [
    {
      practice_mode: "standard",
      ai_count: 3,
      sessions: 2,
      hints: 3,
      debriefs: 1,
      charged: 2,
    },
    {
      practice_mode: "game",
      ai_count: 1,
      sessions: 4,
      hints: 0,
      debriefs: 0,
      charged: 3,
    },
  ],
  aiLogs: [
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
      model: "deepseek-v4-flash",
      status: "success",
      fallback_used: true,
      call_rows: 1,
      retries: 0,
    },
  ],
});

Deno.test("報告含時間窗、場次、直方圖與生成成本表", () => {
  const md = renderReport(STATS);
  assertStringIncludes(md, "# 練習室週報 2026-08-29 ～ 2026-09-05");
  assertStringIncludes(md, "| standard | 2 |");
  assertStringIncludes(md, "| game | 4 |");
  assertStringIncludes(md, "## 回合分佈");
  assertStringIncludes(md, "| 1 | 4 |");
  assertStringIncludes(md, "claude-sonnet-5");
  assertStringIncludes(md, "$0.0308");
});

Deno.test("DeepSeek 無單價的列印「未估」而不是 0", () => {
  const md = renderReport(STATS);
  assertStringIncludes(md, "| deepseek-v4-flash |");
  assertStringIncludes(md, "| 未估 |");
  assertEquals(md.includes("| $0.0000 |"), false);
});

Deno.test("缺欄位逐條印出且不讓報告失敗", () => {
  const md = renderReport(STATS);
  assertStringIncludes(md, "## 欄位不存在");
  assertStringIncludes(md, "agency 介入率");
  assertStringIncludes(md, "practice_chat_succeeded");
});

Deno.test("沒給付費人數時損益段印未提供", () => {
  assertStringIncludes(renderReport(STATS), "未提供付費人數");
});

Deno.test("有付費人數時印月營收與成本佔比", () => {
  const md = renderReport(
    aggregate({
      range: RANGE,
      sessions: [
        {
          practice_mode: "standard",
          ai_count: 3,
          sessions: 2,
          hints: 0,
          debriefs: 0,
          charged: 2,
        },
      ],
      aiLogs: [],
      payers: { starter: 10, essential: 5 },
    }),
  );
  assertStringIncludes(md, "Starter 10 人");
  assertStringIncludes(md, "Essential 5 人");
  assertStringIncludes(md, "NT$12,350");
});
