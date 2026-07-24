// 公式回覆共用 normalizer 測試（2026-07-24 公式回覆計畫 §11.1）。
import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  FORMULA_INTERNAL_LABELS,
  FORMULA_PROMPT_EXAMPLE_LINES,
  FORMULA_REPLY_CAPS,
  formulaDedupeKey,
  normalizeFormulaReplies,
  normalizeFormulaRepliesDetailed,
} from "./formula_reply.ts";

function item(n: number): Record<string, unknown> {
  return {
    openingLine: `公式開場${n}：抓她一個具體線索，放一點我的當下反應。`,
    whyItWorks: `這句好接因為她只要補一個細節就能回（${n}）。`,
  };
}

Deno.test("缺席／null／非 array → []（droppedCount 0）", () => {
  for (const value of [undefined, null, "not-array", 42, { a: 1 }]) {
    const outcome = normalizeFormulaRepliesDetailed(value);
    assertEquals(outcome.replies, []);
    assertEquals(outcome.droppedCount, 0);
  }
});

Deno.test("兩則合法 → 兩則；canonical 值是 trim 後字串", () => {
  const replies = normalizeFormulaReplies([
    { openingLine: "  第一句開場  ", whyItWorks: " 理由一 " },
    item(2),
  ]);
  assertEquals(replies.length, 2);
  assertEquals(replies[0], { openingLine: "第一句開場", whyItWorks: "理由一" });
});

Deno.test("前兩筆壞、第三筆合法 → 繼續掃到收滿；不是 slice(0,2) 再驗", () => {
  const outcome = normalizeFormulaRepliesDetailed([
    { openingLine: "", whyItWorks: "理由" },
    "not-object",
    item(3),
    item(4),
    item(5),
  ]);
  assertEquals(outcome.replies.length, 2);
  assertEquals(
    outcome.replies[0].openingLine,
    (item(3).openingLine as string),
  );
  // 5 筆進來、2 筆進 canonical → dropped 3（含超過兩則的第五筆）。
  assertEquals(outcome.droppedCount, 3);
});

Deno.test("缺欄、非 string、空白、超長 → 丟整則", () => {
  const tooLong = "長".repeat(FORMULA_REPLY_CAPS.openingLine + 1);
  const whyTooLong = "長".repeat(FORMULA_REPLY_CAPS.whyItWorks + 1);
  const replies = normalizeFormulaReplies([
    { openingLine: "只有一欄" },
    { openingLine: 42, whyItWorks: "理由" },
    { openingLine: "   ", whyItWorks: "理由" },
    { openingLine: tooLong, whyItWorks: "理由" },
    { openingLine: "句子", whyItWorks: whyTooLong },
    null,
  ]);
  assertEquals(replies, []);
});

Deno.test("code fence／raw JSON／schema key 洩漏 → 丟整則", () => {
  for (
    const leaked of [
      "```json 開頭",
      "{\"openingLine\":\"x\"}",
      "[1,2,3]",
      '這裡出現 "formulaopeners" 字樣',
      '這裡出現 "formulaTopics" 字樣',
      '這裡出現 "openingLine" 字樣',
      '這裡出現 "whyItWorks" 字樣',
      '這裡出現 "openers" 字樣',
      '這裡出現 "topics" 字樣',
    ]
  ) {
    assertEquals(
      normalizeFormulaReplies([{ openingLine: leaked, whyItWorks: "理由" }]),
      [],
      `openingLine 洩漏應丟：${leaked}`,
    );
    assertEquals(
      normalizeFormulaReplies([{ openingLine: "正常句子", whyItWorks: leaked }]),
      [],
      `whyItWorks 洩漏應丟：${leaked}`,
    );
  }
});

Deno.test("cap 以 Unicode code points 計：astral emoji 邊界對齊 TS/Dart/SQL", () => {
  const emoji = "🀄"; // astral：UTF-16 length 2、code point 1
  const at180 = emoji.repeat(FORMULA_REPLY_CAPS.openingLine);
  const at181 = emoji.repeat(FORMULA_REPLY_CAPS.openingLine + 1);
  assertEquals(
    normalizeFormulaReplies([{ openingLine: at180, whyItWorks: "理由" }])
      .length,
    1,
    "180 code points（UTF-16 360）應合法",
  );
  assertEquals(
    normalizeFormulaReplies([{ openingLine: at181, whyItWorks: "理由" }]),
    [],
    "181 code points 應丟整則",
  );
});

Deno.test("多於兩則 → 最多兩則；droppedCount 含未收的合法項", () => {
  const outcome = normalizeFormulaRepliesDetailed([
    item(1),
    item(2),
    item(3),
    item(4),
  ]);
  assertEquals(outcome.replies.length, 2);
  assertEquals(outcome.droppedCount, 2);
});

Deno.test("公式彼此 openingLine 重複 → 只留第一則（NFKC＋大小寫＋空白容忍）", () => {
  const replies = normalizeFormulaReplies([
    { openingLine: "妳那張咖啡照 Latte 很像 ART", whyItWorks: "理由一" },
    // 全形字母＋不同大小寫＋插入空白：dedupe key 相同。
    { openingLine: "妳那張咖啡照　ｌａｔｔｅ 很像 art", whyItWorks: "理由二" },
    item(3),
  ]);
  assertEquals(replies.length, 2);
  assertEquals(replies[0].whyItWorks, "理由一");
  assertEquals(replies[1].openingLine, item(3).openingLine);
});

Deno.test("與原 opener/topic openingLine 重複 → 丟公式、原內容不動", () => {
  const baseLine = "妳週末都去爬山嗎？";
  const replies = normalizeFormulaReplies(
    [
      { openingLine: `${baseLine} `, whyItWorks: "理由" },
      item(2),
    ],
    { excludeOpeningLines: [baseLine, "另一句 base"] },
  );
  assertEquals(replies.length, 1);
  assertEquals(replies[0].openingLine, item(2).openingLine);
});

Deno.test("prompt 示範句照抄 → 永遠丟（不需呼叫端傳入）", () => {
  for (const example of FORMULA_PROMPT_EXAMPLE_LINES) {
    assertEquals(
      normalizeFormulaReplies([{ openingLine: example, whyItWorks: "理由" }]),
      [],
      `示範句應永遠排除：${example}`,
    );
  }
});

Deno.test("內部作戰板標籤：rejectInternalLabels=true 丟、預設不掃", () => {
  for (const label of FORMULA_INTERNAL_LABELS) {
    const value = [
      { openingLine: `句子提到${label}的內容`, whyItWorks: "理由" },
    ];
    assertEquals(
      normalizeFormulaReplies(value, { rejectInternalLabels: true }),
      [],
      `openingLine 含 ${label} 應丟`,
    );
    const whyValue = [
      { openingLine: "正常句子", whyItWorks: `因為${label}顯示她有興趣` },
    ];
    assertEquals(
      normalizeFormulaReplies(whyValue, { rejectInternalLabels: true }),
      [],
      `whyItWorks 含 ${label} 應丟`,
    );
    assertEquals(
      normalizeFormulaReplies(value).length,
      1,
      "未開 rejectInternalLabels 時不掃標籤",
    );
  }
});

Deno.test("多餘 object key 不出現在 canonical output；不誤殺自然語句", () => {
  const replies = normalizeFormulaReplies([
    { ...item(1), extra: "leak", nested: { a: 1 } },
  ]);
  assertEquals(replies.length, 1);
  assertEquals(Object.keys(replies[0]).sort(), ["openingLine", "whyItWorks"]);

  // 自然語句含「熱度」「備註」等常見詞（非完整標籤）不得誤殺。
  const natural = normalizeFormulaReplies(
    [{
      openingLine: "妳限動那家咖啡店熱度也太高，排隊排到轉角。",
      whyItWorks: "接她剛分享的生活片段，她可以補排了多久或值不值得。",
    }],
    { rejectInternalLabels: true },
  );
  assertEquals(natural.length, 1);
});

Deno.test("dedupe key：標點保留（不同標點＝不同句），空白/全形/大小寫吃掉", () => {
  assertEquals(formulaDedupeKey("你 好 ABC"), formulaDedupeKey("你好ａｂｃ"));
  assert(formulaDedupeKey("你好。") !== formulaDedupeKey("你好？"));
});
