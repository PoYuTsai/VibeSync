import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  buildNewTopicRepairPrompt,
  buildNewTopicUserPrompt,
  NEW_TOPIC_GENERATION_DEADLINE_MS,
  NEW_TOPIC_MAX_TOKENS,
  NEW_TOPIC_PROMPT,
  NEW_TOPIC_REPAIR_PROMPT,
  NEW_TOPIC_REQUEST_DEADLINE_MS,
  NEW_TOPIC_SETTLEMENT_RESERVE_MS,
} from "./new_topic_prompt.ts";

Deno.test("deadline 常數符合拍板規格（50s/45s/5s reserve、3000 tokens）", () => {
  assertEquals(NEW_TOPIC_MAX_TOKENS, 3000);
  assertEquals(NEW_TOPIC_REQUEST_DEADLINE_MS, 50_000);
  assertEquals(NEW_TOPIC_GENERATION_DEADLINE_MS, 45_000);
  assertEquals(NEW_TOPIC_SETTLEMENT_RESERVE_MS, 5_000);
  assertEquals(
    NEW_TOPIC_GENERATION_DEADLINE_MS + NEW_TOPIC_SETTLEMENT_RESERVE_MS,
    NEW_TOPIC_REQUEST_DEADLINE_MS,
  );
});

Deno.test("new topic prompts 過三層線 blocking 掃描（同 opener 黑名單）", () => {
  // 黑名單複用 opener_prompt_test.ts 既有 18 詞（含玩咖）。
  const banned = [
    "PUA",
    "紅藥丸",
    "紅丸",
    "DHV",
    "shit test",
    "廢物測試",
    "高價值男性",
    "高分妹",
    "撈女",
    "壞女人",
    "公主病",
    "婊子",
    "怪男",
    "噁男",
    "收割",
    "控住",
    "攻略",
    "玩咖",
  ];
  for (
    const [name, prompt] of [
      ["NEW_TOPIC_PROMPT", NEW_TOPIC_PROMPT],
      ["NEW_TOPIC_REPAIR_PROMPT", NEW_TOPIC_REPAIR_PROMPT],
    ] as const
  ) {
    for (const word of banned) {
      assertFalse(prompt.includes(word), `黑名單詞殘留於 ${name}：${word}`);
    }
    assertFalse(/IO[ID]/.test(prompt), `IOI/IOD 殘留於 ${name}`);
  }
});

Deno.test("NEW_TOPIC_PROMPT grounding 鐵律錨點", () => {
  // 作戰板＝唯一對方事實源；About Me 只做自我揭露。
  assert(NEW_TOPIC_PROMPT.includes("唯一可以當成**對方事實**的來源"));
  assert(NEW_TOPIC_PROMPT.includes("只能用來做自然的自我揭露"));
  assert(
    NEW_TOPIC_PROMPT.includes("絕不能寫成對方也喜歡、你們的共同興趣"),
  );
  assert(NEW_TOPIC_PROMPT.includes("不得虛構對方的興趣"));
  assert(NEW_TOPIC_PROMPT.includes("用開放式、低假設的問題"));
  assert(NEW_TOPIC_PROMPT.includes("不假裝有共同經驗"));
});

Deno.test("NEW_TOPIC_PROMPT situation 節奏規則四條俱全", () => {
  assert(NEW_TOPIC_PROMPT.includes("went_cold"));
  assert(NEW_TOPIC_PROMPT.includes("不責問對方消失"));
  assert(NEW_TOPIC_PROMPT.includes("after_date"));
  assert(NEW_TOPIC_PROMPT.includes("不急著推進第二次邀約"));
  assert(NEW_TOPIC_PROMPT.includes("stuck"));
  assert(NEW_TOPIC_PROMPT.includes("不像面試連環問"));
  assert(NEW_TOPIC_PROMPT.includes("warm_up"));
  assert(NEW_TOPIC_PROMPT.includes("不突然告白"));
});

Deno.test("NEW_TOPIC_PROMPT 產出規格：恰好五題＋四欄＋可直接傳", () => {
  assert(NEW_TOPIC_PROMPT.includes("恰好五個"));
  assert(NEW_TOPIC_PROMPT.includes("direction"));
  assert(NEW_TOPIC_PROMPT.includes("openingLine"));
  assert(NEW_TOPIC_PROMPT.includes("whyItWorks"));
  assert(NEW_TOPIC_PROMPT.includes("nextMove"));
  assert(NEW_TOPIC_PROMPT.includes("直接傳出去"));
  assert(NEW_TOPIC_PROMPT.includes("不情勒"));
  assert(NEW_TOPIC_PROMPT.includes("不性化"));
  assert(NEW_TOPIC_PROMPT.includes("recommendation.index 是 0-4 的整數"));
  assert(NEW_TOPIC_PROMPT.includes("不要 code fence"));
});

Deno.test("REPAIR prompt：只修格式、不重新發想、五題 schema", () => {
  assert(NEW_TOPIC_REPAIR_PROMPT.includes("只把上一次 AI 回覆修成合法 JSON"));
  assert(NEW_TOPIC_REPAIR_PROMPT.includes("不要重新發想"));
  assert(NEW_TOPIC_REPAIR_PROMPT.includes("topics 必須恰好五個"));
  assert(
    NEW_TOPIC_REPAIR_PROMPT.includes(
      "direction / openingLine / whyItWorks / nextMove",
    ),
  );
});

Deno.test("buildNewTopicUserPrompt：三段分隔明確、缺席走低假設 fallback", () => {
  const full = buildNewTopicUserPrompt({
    partnerSummary: "對象：小雅。興趣：爬山。",
    effectiveStyleContext: "- 語氣：輕鬆",
    situation: "after_date",
  });
  assert(full.includes("## 對方作戰板"));
  assert(full.includes("對象：小雅。興趣：爬山。"));
  assert(full.includes("## 關於我"));
  assert(full.includes("- 語氣：輕鬆"));
  assert(full.includes("## 目前狀況"));
  assert(full.includes("剛約完會"));
  // 段落順序：作戰板 → 關於我 → 目前狀況。
  assert(
    full.indexOf("## 對方作戰板") < full.indexOf("## 關於我") &&
      full.indexOf("## 關於我") < full.indexOf("## 目前狀況"),
  );

  const empty = buildNewTopicUserPrompt({
    partnerSummary: null,
    effectiveStyleContext: null,
    situation: null,
  });
  assert(empty.includes("沒有提供對方資料"));
  assert(empty.includes("不要猜測對方的興趣"));
  assert(empty.includes("不要編造用戶的個人素材"));
  assert(empty.includes("當作日常重啟"));
});

Deno.test("buildNewTopicRepairPrompt：夾帶原文並裁 7000", () => {
  const prompt = buildNewTopicRepairPrompt("原始輸出 ```json broken```");
  assert(prompt.includes("原始回覆："));
  assert(prompt.includes("原始輸出"));

  const long = buildNewTopicRepairPrompt("字".repeat(9000));
  assert(long.length < 7600, "原文必須裁到 7000 以內");

  assert(buildNewTopicRepairPrompt("   ").includes("(empty)"));
});

Deno.test("公式新話題（計畫 §5.2）：prompt 段落＋schema 殿後＋內部標籤禁令；repair 不碰公式", () => {
  assert(NEW_TOPIC_PROMPT.includes("## 公式新話題（額外兩則，不取代五個 topics）"));
  assert(NEW_TOPIC_PROMPT.includes("也不參與 recommendation.index"));
  assert(
    NEW_TOPIC_PROMPT.includes("不能因為\n「關於我」和「對方作戰板」剛好出現相似詞，就自行宣稱共同點"),
  );
  // 內部標籤禁令九詞俱全。
  for (
    const label of [
      "對象作戰板",
      "對方作戰板",
      "最近熱度",
      "累計對話",
      "你的備註",
      "過往備註",
      "性格分析",
      "資料顯示",
      "系統判斷",
    ]
  ) {
    assert(
      NEW_TOPIC_PROMPT.includes(label),
      `內部標籤禁令缺詞：${label}`,
    );
  }
  assert(NEW_TOPIC_PROMPT.includes("不得讓對方知道系統如何記錄或推測她"));
  assert(
    NEW_TOPIC_PROMPT.includes("openingLine 目標 45–80 個繁中字元；whyItWorks 目標 60–100 個繁中字元"),
  );

  // Schema：formulaTopics 殿後（在 recommendation 之後）。
  const recommendationAt = NEW_TOPIC_PROMPT.indexOf('"recommendation": {');
  const formulaAt = NEW_TOPIC_PROMPT.indexOf('"formulaTopics": [');
  assert(
    formulaAt > recommendationAt && recommendationAt > 0,
    "formulaTopics 必須在 schema 的 recommendation 之後",
  );
  assert(NEW_TOPIC_PROMPT.includes("formulaTopics 必須恰好兩則，放在最後"));
  // 原五題規格不變。
  assert(NEW_TOPIC_PROMPT.includes("topics 必須恰好五個；recommendation.index 是 0-4 的整數"));

  // Repair 只修 base：schema 與指令不得出現 formulaTopics。
  assertFalse(
    NEW_TOPIC_REPAIR_PROMPT.includes("formulaTopics"),
    "NEW_TOPIC_REPAIR_PROMPT 不得要求公式（repair 只修 base）",
  );
});
