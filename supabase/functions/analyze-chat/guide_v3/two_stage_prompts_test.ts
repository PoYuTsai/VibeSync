// 兩段式實驗（開關 ANALYZE_GUIDE_V3_TWO_STAGE，Eric 2026-10-19）的提示詞與讀局面欄位：
// 只在開關開時才多的字；開關沒開的版本由 two_stage_flag_off_test.ts 的雜湊鎖住。
import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { readSystemPrompt, readUserPrompt } from "./prompts.ts";
import {
  parseTwoStageTags,
  READ_TAGS_SCHEMA,
  READ_TAGS_SCHEMA_TWO_STAGE,
  type TwoStageTags,
  WORTHY_LINE_KINDS,
} from "./read_tags.ts";
import { toTurns } from "./turns.ts";
import {
  READ_TWO_STAGE_NOTES,
  readSystemPromptTwoStage,
  readUserPromptTwoStage,
} from "./two_stage_prompts.ts";

const MESSAGES = [
  { isFromMe: true, content: "今天上班還好嗎" },
  { isFromMe: false, content: "還行" },
  { isFromMe: true, content: "晚餐吃什麼" },
  { isFromMe: false, content: "[照片：一盤咖哩飯]" },
  { isFromMe: false, content: "我自己煮的！" },
  { isFromMe: false, content: "好想你喔" },
];

const EXTRAS: TwoStageTags = {
  establishedCouple: true,
  herAffection: true,
  herHappyShare: true,
  worthyLines: [
    { line: 3, label: "說想他", kind: "情感" },
    { line: 2, label: "自己煮的", kind: "其他" },
    { line: 1, label: "咖哩照片", kind: "照片或貼圖" },
  ],
};

Deno.test("兩段式讀局面 schema：今天的欄位一個不少、定義不變，另加四欄而且都必填", () => {
  const today = READ_TAGS_SCHEMA as {
    required: string[];
    properties: Record<string, unknown>;
  };
  const two = READ_TAGS_SCHEMA_TWO_STAGE as {
    required: string[];
    properties: Record<string, unknown>;
    additionalProperties: boolean;
  };
  assertEquals(two.additionalProperties, false);
  assertEquals(two.required, [
    ...today.required,
    "establishedCouple",
    "herAffection",
    "herHappyShare",
    "worthyLines",
  ]);
  for (const [key, value] of Object.entries(today.properties)) {
    assertEquals(two.properties[key], value, key);
  }
  assertEquals(
    Object.keys(two.properties).filter((k) => !(k in today.properties)),
    ["establishedCouple", "herAffection", "herHappyShare", "worthyLines"],
  );
  assertEquals(two.properties.worthyLines, {
    type: "array",
    items: {
      type: "object",
      additionalProperties: false,
      required: ["line", "label", "kind"],
      properties: {
        line: { type: "integer" },
        label: { type: "string" },
        kind: { type: "string", enum: [...WORTHY_LINE_KINDS] },
      },
    },
  });
});

Deno.test("兩段式四欄：型別對才收；少一欄、種類不在選項裡、編號不是整數都算讀局面失敗", () => {
  assertEquals(parseTwoStageTags({ light: "green", ...EXTRAS }), EXTRAS);
  for (
    const broken of [
      { ...EXTRAS, establishedCouple: undefined },
      { ...EXTRAS, herAffection: "true" },
      { ...EXTRAS, worthyLines: undefined },
      { ...EXTRAS, worthyLines: [{ line: 1, label: "x", kind: "撒嬌" }] },
      { ...EXTRAS, worthyLines: [{ line: 1.5, label: "x", kind: "其他" }] },
      { ...EXTRAS, worthyLines: [{ line: 1, kind: "其他" }] },
    ]
  ) {
    assertEquals(parseTwoStageTags(broken), null, JSON.stringify(broken));
  }
  assertEquals(parseTwoStageTags(null), null);
});

Deno.test("兩段式讀局面系統提示詞：今天的整段照舊，只在欄位說明之後多一段新欄位與標籤怎麼判", () => {
  const today = readSystemPrompt();
  const two = readSystemPromptTwoStage();
  assertEquals(
    two,
    today.replace(
      "\n\n## 情境條目的觸發",
      `\n\n${READ_TWO_STAGE_NOTES}\n\n## 情境條目的觸發`,
    ),
  );
  for (
    const field of [
      "establishedCouple",
      "herAffection",
      "herHappyShare",
      "worthyLines",
    ]
  ) {
    assertStringIncludes(READ_TWO_STAGE_NOTES, `- ${field}：`);
  }
  // 研究 §5.3、§7.2：標籤可能是 App 預設值，跟對話對不上時照對話；情侶的親暱稱呼不是風險。
  assertStringIncludes(READ_TWO_STAGE_NOTES, "App 的預設值");
  assertStringIncludes(READ_TWO_STAGE_NOTES, "照對話判斷");
  assertStringIncludes(READ_TWO_STAGE_NOTES, "不是風險");
  assertStringIncludes(READ_TWO_STAGE_NOTES, "「已是伴侶」");
  for (const kind of WORTHY_LINE_KINDS) {
    assertStringIncludes(READ_TWO_STAGE_NOTES, `「${kind}」`);
  }
});

Deno.test("兩段式讀局面使用者提示詞：只有她最新這一輪逐則編號，其他一字不變；最後是他的就完全一樣", () => {
  const turns = toTurns(MESSAGES);
  const today = readUserPrompt(turns);
  const two = readUserPromptTwoStage(turns);
  assertEquals(
    two,
    today.replace(
      "第 4 輪・她：\n- [照片：一盤咖哩飯]\n- 我自己煮的！\n- 好想你喔",
      "第 4 輪・她：\n1. [照片：一盤咖哩飯]\n2. 我自己煮的！\n3. 好想你喔",
    ),
  );
  assert(two !== today);
  // 前面幾輪照舊用「- 」。
  assertStringIncludes(two, "第 2 輪・她：\n- 還行");
  const hisLast = toTurns([...MESSAGES, {
    isFromMe: true,
    content: "我也想妳",
  }]);
  assertEquals(readUserPromptTwoStage(hisLast), readUserPrompt(hisLast));
});
