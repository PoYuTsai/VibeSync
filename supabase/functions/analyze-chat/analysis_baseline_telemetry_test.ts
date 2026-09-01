import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  type AnalysisBaselineSummary,
  formatAnalysisBaseline,
  summarizeAnalysisBaseline,
} from "./analysis_baseline_telemetry.ts";

function option(
  segments: Array<{ sourceIndex?: number; reply: string }>,
): Record<string, unknown> {
  return {
    approach: "接法",
    messages: segments.map((segment) => ({
      label: "建議訊息",
      sourceMessage: "她說的話",
      reason: "接球",
      ...segment,
    })),
  };
}

Deno.test("summarizeAnalysisBaseline 量出盤點、覆蓋與問句", () => {
  const summary = summarizeAnalysisBaseline({
    ballInventory: {
      balls: [
        { sourceIndex: 1, disposition: "接" },
        { sourceIndex: 2, disposition: "併" },
        { sourceIndex: 3, disposition: "接" },
        { sourceIndex: 4, disposition: "略" },
      ],
    },
    enthusiasm: { score: 68, level: "hot" },
    replyOptions: {
      extend: option([
        { sourceIndex: 1, reply: "練完那種腿不是自己的" },
        { sourceIndex: 3, reply: "然後直接去吃火鍋，妳是補回來派？" },
      ]),
      tease: option([
        { sourceIndex: 1, reply: "看來今天有認真" },
        { sourceIndex: 3, reply: "火鍋已經在終點等妳" },
      ]),
    },
  });

  assertEquals(summary.inventory, {
    catch: 2,
    merge: 1,
    skip: 1,
    truncated: false,
  });
  assertEquals(summary.cardsShown, 2);
  assertEquals(summary.coverage, { extend: [1, 3], tease: [1, 3] });
  assertEquals(summary.sameBallSetAcrossStyles, true);
  assertEquals(summary.questionCounts, { extend: 1, tease: 0 });
  assertEquals(summary.maxQuestionCount, 1);
  assertEquals(summary.enthusiasmScore, 68);
  assertEquals(summary.coldScoreWithCards, false);
  assertEquals(summary.giveUpBannerWithCards, false);
});

Deno.test("summarizeAnalysisBaseline 抓得到五卡球集合不一致", () => {
  const summary = summarizeAnalysisBaseline({
    replyOptions: {
      extend: option([
        { sourceIndex: 1, reply: "接第一顆" },
        { sourceIndex: 3, reply: "接第三顆" },
      ]),
      // 漏接了第三顆：使用者橫滑到這張就少一段內容。
      humor: option([{ sourceIndex: 1, reply: "只接第一顆" }]),
    },
  });

  assertEquals(summary.coverage, { extend: [1, 3], humor: [1] });
  assertEquals(summary.sameBallSetAcrossStyles, false);
});

Deno.test("summarizeAnalysisBaseline 少於兩張可比卡片時不謊報一致", () => {
  const single = summarizeAnalysisBaseline({
    replyOptions: { extend: option([{ sourceIndex: 1, reply: "只有一張" }]) },
  });
  assertEquals(single.sameBallSetAcrossStyles, null);

  // 有卡片但完全沒有 sourceIndex：無從比較，不能算成「一致」。
  const noSource = summarizeAnalysisBaseline({
    replyOptions: {
      extend: option([{ reply: "沒有來源" }]),
      tease: option([{ reply: "也沒有來源" }]),
    },
  });
  assertEquals(noSource.coverage, { extend: [], tease: [] });
  assertEquals(noSource.sameBallSetAcrossStyles, null);
});

Deno.test("summarizeAnalysisBaseline 量出冷局仍出卡的矛盾", () => {
  const summary = summarizeAnalysisBaseline({
    enthusiasm: { score: 27, level: "cold" },
    warnings: ["對方投入偏低，建議放棄這段追求"],
    replyOptions: { extend: option([{ sourceIndex: 1, reply: "還是回一句" }]) },
  });

  assertEquals(summary.coldScoreWithCards, true);
  assertEquals(summary.giveUpBannerWithCards, true);
});

Deno.test("summarizeAnalysisBaseline 沒有卡片時矛盾指標不得成立", () => {
  const summary = summarizeAnalysisBaseline({
    enthusiasm: { score: 12, level: "cold" },
    warnings: ["建議放棄"],
    replyOptions: {},
    replies: {},
  });

  assertEquals(summary.cardsShown, 0);
  assertEquals(summary.coldScoreWithCards, false);
  assertEquals(summary.giveUpBannerWithCards, false);
});

Deno.test("summarizeAnalysisBaseline 只有 legacy replies 時仍算得到卡片", () => {
  const summary = summarizeAnalysisBaseline({
    replies: { extend: "舊版備援文字，有問題嗎？" },
  });

  assertEquals(summary.cardsShown, 1);
  assertEquals(summary.questionCounts, { extend: 1 });
  assertEquals(summary.coverage, { extend: [] });
});

Deno.test("summarizeAnalysisBaseline 永遠不 throw", () => {
  // 觀測程式炸掉不得害一次已扣費的分析失敗。
  const hostile: unknown[] = [
    null,
    undefined,
    "string",
    42,
    [],
    { replyOptions: "not-a-record", replies: 7, enthusiasm: [] },
    { replyOptions: { extend: { messages: "nope" } } },
    { replyOptions: { extend: { messages: [null, 3, { reply: 5 }] } } },
    { ballInventory: { balls: "nope" } },
    { ballInventory: { balls: [null, "x", { disposition: 9 }] } },
    { warnings: { not: "an array" }, enthusiasm: { level: "cold" } },
    {
      warnings: [null, { type: "safety_filter" }],
      enthusiasm: { level: "cold" },
    },
  ];

  for (const input of hostile) {
    const summary = summarizeAnalysisBaseline(input);
    assert(typeof summary.cardsShown === "number");
    // 格式化同樣不得炸。
    assert(formatAnalysisBaseline(summary).startsWith("[analysis_baseline]"));
  }
});

Deno.test("formatAnalysisBaseline 不得帶出訊息原文", () => {
  const secret = "她說的私人內容不該進 log";
  const summary = summarizeAnalysisBaseline({
    ballInventory: {
      balls: [{ sourceIndex: 1, sourceMessage: secret, disposition: "接" }],
    },
    replyOptions: {
      extend: option([{ sourceIndex: 1, reply: `${secret}，我這樣回` }]),
    },
    enthusiasm: { score: 55 },
  });

  const line = formatAnalysisBaseline(summary);
  assertEquals(line.includes(secret), false);
  assert(line.includes("inventory=接1/併0/略0"));
  assert(line.includes("coverage={extend:[1]}"));
});

Deno.test("formatAnalysisBaseline 標記被截斷的盤點", () => {
  const summary: AnalysisBaselineSummary = summarizeAnalysisBaseline({
    ballInventory: {
      balls: [{ sourceIndex: 1, disposition: "接" }],
      truncated: true,
    },
  });

  assertEquals(summary.inventory?.truncated, true);
  assert(formatAnalysisBaseline(summary).includes("inventory=接1/併0/略0+"));
});
