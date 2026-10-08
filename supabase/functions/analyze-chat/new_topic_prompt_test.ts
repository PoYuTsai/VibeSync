// 新話題的期限常數、修格式提示詞與 production prompt blocking scan。
// 生成提示詞（結構刀，ADR #53）的結構測試在 new_topic_slots_test.ts。
import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  buildNewTopicRepairPrompt,
  NEW_TOPIC_GENERATION_DEADLINE_MS,
  NEW_TOPIC_MAX_TOKENS,
  NEW_TOPIC_REPAIR_PROMPT,
  NEW_TOPIC_REQUEST_DEADLINE_MS,
  NEW_TOPIC_SETTLEMENT_RESERVE_MS,
} from "./new_topic_prompt.ts";
import { NEW_TOPIC_SLOTS_SYSTEM_PROMPT } from "./new_topic_slots.ts";

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
      ["NEW_TOPIC_SLOTS_SYSTEM_PROMPT", NEW_TOPIC_SLOTS_SYSTEM_PROMPT],
      ["NEW_TOPIC_REPAIR_PROMPT", NEW_TOPIC_REPAIR_PROMPT],
    ] as const
  ) {
    for (const word of banned) {
      assertFalse(prompt.includes(word), `黑名單詞殘留於 ${name}：${word}`);
    }
    assertFalse(/IO[ID]/.test(prompt), `IOI/IOD 殘留於 ${name}`);
  }
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
  assert(NEW_TOPIC_REPAIR_PROMPT.includes("openingLine 必須逐字保留"));
  assert(NEW_TOPIC_REPAIR_PROMPT.includes("只改寫客戶看到的解釋"));
});

Deno.test("buildNewTopicRepairPrompt：夾帶原文並裁 7000", () => {
  const prompt = buildNewTopicRepairPrompt("原始輸出 ```json broken```");
  assert(prompt.includes("原始回覆："));
  assert(prompt.includes("原始輸出"));

  const long = buildNewTopicRepairPrompt("字".repeat(9000));
  assert(long.length < 7600, "原文必須裁到 7000 以內");

  assert(buildNewTopicRepairPrompt("   ").includes("(empty)"));
});
