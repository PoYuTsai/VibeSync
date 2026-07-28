import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";

import {
  type AnalysisResult,
  checkAiOutput,
  getSafeReplies,
  hasOutboundSafetyWarning,
} from "./guardrails.ts";

Deno.test("getSafeReplies - hot fallback keeps the conversation moving", () => {
  const replies = getSafeReplies("hot");

  assertEquals(replies.extend, "這個有畫面欸，你是怎麼想到的？");
  assertEquals(replies.resonate, "有點準，但我想聽聽你為什麼這樣覺得");
  assertFalse(replies.extend.includes("繼續聊這個，我覺得很有意思"));
  assertFalse(replies.resonate.includes("對啊，我也這麼覺得"));
});

function optimizeResult(optimized: string): AnalysisResult {
  return {
    optimizedMessage: {
      original: "原始草稿",
      optimized,
      reason: "調整語氣",
    },
  } as unknown as AnalysisResult;
}

function optimizedTextOf(result: AnalysisResult): string {
  return (result.optimizedMessage as Record<string, string>).optimized;
}

// ---------------------------------------------------------------------------
// 既有行為不得改變
// ---------------------------------------------------------------------------

Deno.test("checkAiOutput - 沒有 replies 也沒有 optimizedMessage 時原樣返回", () => {
  const result = { recognizedMessages: [] } as unknown as AnalysisResult;

  assertEquals(checkAiOutput(result), result);
});

Deno.test("checkAiOutput - null 結果不會炸", () => {
  assertEquals(checkAiOutput(null as unknown as AnalysisResult), null);
});

Deno.test("checkAiOutput - replies 路徑仍照舊換成安全回覆", () => {
  const result = {
    enthusiasm: { score: 50, level: "warm" },
    replies: { extend: "不要放棄，你就一直約她出來" },
    warnings: [],
  } as unknown as AnalysisResult;

  const guarded = checkAiOutput(result);

  assertEquals(guarded.replies.extend, getSafeReplies("warm").extend);
  assertEquals(guarded.warnings[0].type, "safety_filter");
  assertFalse(hasOutboundSafetyWarning(guarded));
});

// ---------------------------------------------------------------------------
// 新增：optimizedMessage 的輸出守門
// ---------------------------------------------------------------------------

Deno.test("checkAiOutput - 乾淨的潤飾結果原樣通過", () => {
  const result = optimizeResult("那我們週末再約？我這邊都可以。");

  const guarded = checkAiOutput(result);

  assertEquals(optimizedTextOf(guarded), "那我們週末再約？我這邊都可以。");
  assertFalse(hasOutboundSafetyWarning(guarded));
});

Deno.test("checkAiOutput - 條件式威脅會被清空且標記", () => {
  const guarded = checkAiOutput(
    optimizeResult("你如果不回我，我就去死給你看。"),
  );

  assertEquals(optimizedTextOf(guarded), "");
  assert(hasOutboundSafetyWarning(guarded));
});

Deno.test("checkAiOutput - 以自傷當籌碼會被清空", () => {
  const guarded = checkAiOutput(
    optimizeResult("沒有你我活不下去，你不要走好不好。"),
  );

  assertEquals(optimizedTextOf(guarded), "");
  assert(hasOutboundSafetyWarning(guarded));
});

Deno.test("checkAiOutput - 威脅散布私密內容會被清空", () => {
  const guarded = checkAiOutput(
    optimizeResult("再不理我，我就把那些照片傳出去。"),
  );

  assertEquals(optimizedTextOf(guarded), "");
  assert(hasOutboundSafetyWarning(guarded));
});

Deno.test("checkAiOutput - 宣告掌握行蹤會被清空", () => {
  const guarded = checkAiOutput(
    optimizeResult("我已經查到你住哪了，晚點過去找你。"),
  );

  assertEquals(optimizedTextOf(guarded), "");
  assert(hasOutboundSafetyWarning(guarded));
});

// ---------------------------------------------------------------------------
// 誤傷防線：這些句子正是在設界線，擋掉等於幫施壓的一方消音。
// BLOCKED_PATTERNS 那組詞彙型樣式若直接套到訊息上，以下每一條都會誤擋。
// ---------------------------------------------------------------------------

Deno.test("checkAiOutput - 正當設界線的訊息不得被攔", () => {
  const legitimate = [
    "你這樣一直傳訊息，我覺得有點被騷擾了。",
    "我不是要逼你答應，只是想知道你的想法。",
    "我不想死纏爛打，所以我就說到這裡。",
    "我沒有要威脅你的意思，只是講我的感受。",
    "你說不要，我尊重你的意願，就這樣吧。",
    "我不會去跟蹤你，也不會再打擾你了。",
    "我不會把我們的對話傳出去，你放心。",
    "那張照片我早就刪了，不會讓大家看到。",
  ];

  for (const text of legitimate) {
    const guarded = checkAiOutput(optimizeResult(text));

    assertEquals(optimizedTextOf(guarded), text);
    assertFalse(
      hasOutboundSafetyWarning(guarded),
      `不該被攔：${text}`,
    );
  }
});

/**
 * 2026-07-28 Codex 對抗式審查實測出的七個誤擋，全部已修並鎖在這裡。
 * 最嚴重的是後兩條：「我知道你住哪區比較方便」是完全正常的約會訊息，
 * 原本會被當成宣告掌握行蹤攔掉。
 */
Deno.test("checkAiOutput - Codex 審查抓到的誤擋反例不得再現", () => {
  const regressions = [
    // 「去死心」被「去死」吃到
    "你如果不想再見，我就去死心，不再打擾你。",
    // 「不想活在怨恨裡」被「不想活」吃到
    "你離開我之後，我不想活在怨恨裡，祝福你。",
    // 「你不想／你不希望」被當成條件式威脅引子
    "你不想讓大家看到的照片，我不會傳出去。",
    "你不希望公開的對話，我會替你保密。",
    // 「知道你住哪」是正常約地點，不是宣告掌握行蹤
    "我知道你住哪區比較方便，下次約中間點。",
    "我已經知道你家在哪附近了，所以挑你方便的餐廳。",
  ];

  for (const text of regressions) {
    const guarded = checkAiOutput(optimizeResult(text));

    assertEquals(optimizedTextOf(guarded), text, `不該被攔：${text}`);
    assertFalse(hasOutboundSafetyWarning(guarded), `不該被攔：${text}`);
  }
});

/** 同樣來自 Codex 審查：模型真的寫得出來、原本卻漏擋的說法。 */
Deno.test("checkAiOutput - 補上原本漏擋的自然中文說法", () => {
  const shouldBlock = [
    "你若不回我，我就自殺。",
    "你不回我我就死給你看啦。",
    "再不理我，我就把私密照外流。",
    "我查到你的地址了。",
  ];

  for (const text of shouldBlock) {
    const guarded = checkAiOutput(optimizeResult(text));

    assertEquals(optimizedTextOf(guarded), "", `該被攔：${text}`);
    assert(hasOutboundSafetyWarning(guarded), `該被攔：${text}`);
  }
});

Deno.test("checkAiOutput - warnings 不是陣列時不得拋錯", () => {
  const result = {
    optimizedMessage: { original: "x", optimized: "你如果不回我我就去死。" },
    warnings: { unexpected: true },
  } as unknown as AnalysisResult;

  const guarded = checkAiOutput(result);

  assertEquals(optimizedTextOf(guarded), "");
  assert(hasOutboundSafetyWarning(guarded));
});

Deno.test("hasOutboundSafetyWarning - 沒有 warnings 陣列時回 false", () => {
  assertFalse(hasOutboundSafetyWarning({}));
  assertFalse(hasOutboundSafetyWarning(null));
  assertFalse(hasOutboundSafetyWarning({ warnings: "not-an-array" }));
});
