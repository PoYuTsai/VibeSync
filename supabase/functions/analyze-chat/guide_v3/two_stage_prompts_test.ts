// 兩段式實驗（開關 ANALYZE_GUIDE_V3_TWO_STAGE，Eric 2026-10-19）的提示詞與讀局面欄位：
// 只在開關開時才多的字；開關沒開的版本由 two_stage_flag_off_test.ts 的雜湊鎖住。
import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  containsPromptLeak,
  PROMPT_LEAK_DEFENSE_DIRECTIVE,
} from "../../_shared/prompt_leak_guard.ts";
import fixtures from "../testdata/guide_v3_replay_fixtures.json" with {
  type: "json",
};
import { GUIDE_V3_ENTRIES } from "./entries.ts";
import { GUIDE_V3_SECTIONS } from "./guide_text.ts";
import {
  readSystemPrompt,
  readUserPrompt,
  WRITE_OUTPUT_FORMAT,
  WRITE_SAFETY_FLOOR,
  writeSystemPrompt,
  writeUserPrompt,
} from "./prompts.ts";
import type { ReadTags } from "./read_tags.ts";
import type { CardSpec } from "./rules.ts";
import {
  parseTwoStageTags,
  READ_TAGS_SCHEMA,
  READ_TAGS_SCHEMA_TWO_STAGE,
  type TwoStageTags,
  WORTHY_LINE_KINDS,
} from "./read_tags.ts";
import { toTurns } from "./turns.ts";
import {
  applyLineEdits,
  cardSpecLineTwoStage,
  HAPPY_SHARE_TASK,
  quoteHerLine,
  READ_TWO_STAGE_NOTES,
  readSystemPromptTwoStage,
  readUserPromptTwoStage,
  TWO_STAGE_METHOD_LABEL,
  TWO_STAGE_TENSION_LINE,
  TWO_STAGE_WRITER_SENTINELS,
  twoStageEntryWriting,
  twoStageWriterSections,
  WRITE_MEDIA_RULES,
  WRITE_NATURAL_RULES,
  writeSystemPromptTwoStage,
  writeUserPromptTwoStage,
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

Deno.test("兩段式第 2 輪讀局面：值得接的句子多一種「問他」（排第一個），同時算問他和情感時填問他", () => {
  assertEquals(WORTHY_LINE_KINDS, ["問他", "情感", "照片或貼圖", "其他"]);
  assertStringIncludes(
    READ_TWO_STAGE_NOTES,
    "「問他」（她直接問他、要他的看法，或想聽他說好不好看、厲不厲害）",
  );
  assertStringIncludes(
    READ_TWO_STAGE_NOTES,
    "一則同時算問他和情感時填「問他」",
  );
  const asks: TwoStageTags = {
    ...EXTRAS,
    worthyLines: [{ line: 3, label: "問他好不好看", kind: "問他" }],
  };
  assertEquals(parseTwoStageTags(asks), asks);
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

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/// 推拉那一條在寫卡看到的樣子（Eric 2026-10-19 決定：拿掉「用來製造張力」和「推在前、拉收尾…」）。
const PUSH_PULL_WRITER_LINE =
  "  - 推拉：推只推觀點、喜好或合不合，拉多推少；用反話表達喜歡也算。挑戰只在他真的有立場時用。";

/// 原文裡以這幾個字開頭的那一行（測試不另抄原文）。
function lineOf(section: string, startsWith: string): string {
  const found = section.split("\n").filter((l) => l.startsWith(startsWith));
  assertEquals(found.length, 1, startsWith);
  return found[0];
}

Deno.test("兩段式寫卡系統提示詞：沒有 A1、沒有「每張卡都要有他的態度」、沒有「繃緊」與封號、沒有「「有他」做法」", () => {
  const write = writeSystemPromptTwoStage();
  for (const line of GUIDE_V3_SECTIONS.A1.split("\n").filter((l) => l)) {
    assert(!write.includes(line), `A1 還在：${line}`);
  }
  for (
    const gone of [
      "每張卡都要有他的態度",
      "換誰講都成立",
      "繃緊",
      "封號",
      // 推拉那一條（Eric 2026-10-19 決定）：跟先繃緊再鬆開同一個形狀，寫卡不帶。
      "製造張力",
      "推在前",
      "拉收尾",
      "「有他」做法",
      "**有他**",
    ]
  ) {
    assert(!write.includes(gone), gone);
  }
  // 新的規則：訊息是自然句子、說明交給下一步、不是每句都要表態；照片與貼圖怎麼讀。
  assertStringIncludes(write, WRITE_NATURAL_RULES);
  assertStringIncludes(write, "原封不動傳出去的自然句子");
  assertStringIncludes(write, "下一步會另外說明給用戶");
  assertStringIncludes(write, "不是每一句都要表態");
  assertStringIncludes(write, WRITE_MEDIA_RULES);
  assertStringIncludes(write, "不是她說的話");
  assertStringIncludes(write, `**${TWO_STAGE_METHOD_LABEL}**`);
  // 照留的：A2、A3 原文，輸出格式、安全底線、外洩指令，寫卡的開頭那句（也是外洩哨兵）。
  assertStringIncludes(write, GUIDE_V3_SECTIONS.A2);
  assertStringIncludes(write, GUIDE_V3_SECTIONS.A3);
  assertStringIncludes(write, WRITE_OUTPUT_FORMAT);
  assertStringIncludes(write, WRITE_SAFETY_FLOOR);
  assertStringIncludes(write, PROMPT_LEAK_DEFENSE_DIRECTIVE.trim());
  assert(
    write.startsWith("你是 VibeSync 對話分析的「寫句子」步驟："),
  );
  assert(!write.includes(GUIDE_V3_SECTIONS.A4));
});

Deno.test("兩段式寫卡的 A5、A6：只改那幾行，其他一字不差、順序不變；A6 編號往前補", () => {
  const { A5, A6 } = twoStageWriterSections();
  const a5 = GUIDE_V3_SECTIONS.A5;
  const expectedA5 = a5
    .replace(
      lineOf(a5, "程式會指定每張卡的"),
      lineOf(a5, "程式會指定每張卡的").replace(
        "「有他」做法",
        TWO_STAGE_METHOD_LABEL,
      ),
    )
    .replace(lineOf(a5, "- **帶張力**："), TWO_STAGE_TENSION_LINE)
    .replace(
      lineOf(a5, "  - 材料從她話裡"),
      lineOf(a5, "  - 材料從她話裡").split("；")[0] + "。",
    )
    .replace(lineOf(a5, "  - 推拉用來製造張力："), PUSH_PULL_WRITER_LINE)
    .replace(
      `\n${lineOf(a5, "**「有他」做法**")}\n`,
      `\n**${TWO_STAGE_METHOD_LABEL}**\n`,
    )
    .replace(lineOf(a5, "- 每張卡都要有他的態度"), "- 講具體的，不講類別。");
  assertEquals(A5, expectedA5);
  assertEquals(A5.split("\n").length, a5.split("\n").length);
  // 帶張力底下的手法與界線照留；推拉只留具體的做法與界線。
  for (
    const kept of [
      "誇張解讀",
      "反差",
      "好笑的類比",
      "虧她做的事，不虧她這個人",
      "她越喜歡他，玩笑越少",
      PUSH_PULL_WRITER_LINE,
    ]
  ) {
    assertStringIncludes(A5, kept);
  }
  const a6 = GUIDE_V3_SECTIONS.A6.split("\n");
  const numbered = A6.split("\n").filter((l) => /^\d+\. /.test(l));
  assertEquals(numbered.map((l) => Number(l.split(".")[0])), [
    1,
    2,
    3,
    4,
    5,
    6,
  ]);
  assertEquals(A6.split("\n").length, a6.length - 1);
  assertStringIncludes(A6, `任務、${TWO_STAGE_METHOD_LABEL}、口吻`);
  assertStringIncludes(A6, "**不需要她**");
  assertStringIncludes(A6, "技巧要消失在句子裡");
});

Deno.test("兩段式寫卡系統提示詞的雜湊鎖：改這段要連這裡一起改", async () => {
  assertEquals(
    await sha256(writeSystemPromptTwoStage()),
    "e0382516166c197a869d0835a7dd745deab14200b022a5d00bfb2dfcb75bfc55",
  );
  assertEquals(
    await sha256(readSystemPromptTwoStage()),
    "35dcb974cb25db0f12db7b4f1c33b63dd138010629a1621904a2c1624e26a203",
  );
});

Deno.test("推拉那一條：原文的「用來製造張力」或「推在前、拉收尾…」那一句改了，寫卡提示詞直接丟錯", () => {
  const a5 = GUIDE_V3_SECTIONS.A5;
  const line = lineOf(a5, "  - 推拉用來製造張力：");
  for (
    const changed of [
      line.replace("推在前、拉收尾", "推在後、拉收尾"),
      line.replace("最後一句決定", "最後那句決定"),
      line.replace("推拉用來製造張力：", "推拉用來製造張力，"),
    ]
  ) {
    let threw = false;
    try {
      twoStageWriterSections({
        ...GUIDE_V3_SECTIONS,
        A5: a5.replace(line, changed),
      });
    } catch {
      threw = true;
    }
    assert(threw, changed);
  }
});

Deno.test("改說明書原文的工具：對不上一行、對上兩行、要換的字不在，都直接丟錯", () => {
  const text = "### X\n- 甲：一\n- 乙：二；三\n- 乙：四";
  assertEquals(
    applyLineEdits(text, [{ startsWith: "- 甲", edit: () => null }]),
    "### X\n- 乙：二；三\n- 乙：四",
  );
  let threw = 0;
  for (
    const edits of [
      [{ startsWith: "- 丙", edit: () => "x" }],
      [{ startsWith: "- 乙", edit: () => "x" }],
    ]
  ) {
    try {
      applyLineEdits(text, edits);
    } catch {
      threw++;
    }
  }
  assertEquals(threw, 2);
});

const TAGS: ReadTags = {
  light: "green",
  herMove: "高點",
  herMoodBad: false,
  drunkOrLateNight: false,
  inviteReadiness: "沒機會",
  cancelHasAlternative: false,
  retreating: false,
  declinedOrBoundary: false,
  explicitRejection: false,
  blocked: false,
  risk: false,
  selfHarmSignal: false,
  minorSignal: false,
  needsHisFacts: false,
  identityQuestion: false,
  hisStatedFacts: [],
  hasHisVoiceSample: false,
  replyWillingness: "high",
  worthyBallCount: 2,
  herTurnsPerfunctory: [],
  matchedEntries: ["B22", "B23"],
  readForUser: "她在分享。",
  waitFor: "",
};

const SPECS: CardSpec[] = [
  {
    task: "接住",
    method: "只用反應",
    voice: "預設",
    questionBudget: 1,
    push: null,
    angle: 0,
    lines: [3, 1],
  },
  {
    task: "共鳴",
    method: "只用反應",
    voice: "預設",
    questionBudget: 1,
    push: null,
    angle: 0,
    lines: [2],
    note: "happy_share",
  },
  {
    task: "推進",
    method: "留空格",
    voice: "預設",
    questionBudget: 0,
    push: "種子",
    angle: 0,
  },
];

Deno.test("兩段式卡片規格：任務後面先講這張接她哪幾句，標籤改「他的事怎麼寫」，開心分享的共鳴另寫清楚", () => {
  const herLatest = ["[照片：一盤咖哩飯]", "我自己煮的！", "好想你喔"];
  assertEquals(
    cardSpecLineTwoStage(SPECS[0], 1, herLatest),
    `1. 任務：接住｜這張接：她的「好想你喔」和「[照片：一盤咖哩飯]」｜${TWO_STAGE_METHOD_LABEL}：只用反應｜口吻：預設｜問句最多 1 個`,
  );
  assertEquals(
    cardSpecLineTwoStage(SPECS[1], 2, herLatest),
    `2. 任務：${HAPPY_SHARE_TASK}｜這張接：她的「我自己煮的！」｜${TWO_STAGE_METHOD_LABEL}：只用反應｜口吻：預設｜問句最多 1 個`,
  );
  // 沒分到句子（或編號超出）就不寫「這張接」；推進照舊帶動作說明。
  const third = cardSpecLineTwoStage(SPECS[2], 3, herLatest);
  assert(!third.includes("這張接"));
  assert(third.startsWith("3. 任務：推進（種子）｜他的事怎麼寫：留空格（"));
  assert(
    !cardSpecLineTwoStage({ ...SPECS[0], lines: [9] }, 1, herLatest).includes(
      "這張接",
    ),
  );
});

Deno.test("引她的那一句：去掉引用前綴、空白收成一格、超過 30 字截短", () => {
  assertEquals(quoteHerLine("（引用：「你說的那家」）我吃到了"), "我吃到了");
  assertEquals(quoteHerLine("今天\n  好累"), "今天 好累");
  const long = "一".repeat(40);
  assertEquals([...quoteHerLine(long)].length, 30);
  assert(quoteHerLine(long).endsWith("…"));
});

Deno.test("兩段式寫卡使用者提示詞：她最新這一輪逐則編號、條目的「有他」做法改名、規格換成兩段式，其他照舊", () => {
  const turns = toTurns(MESSAGES);
  const entries = GUIDE_V3_ENTRIES.filter((e) =>
    TAGS.matchedEntries.includes(e.id)
  );
  const args = { turns, tags: TAGS, entries, cards: SPECS };
  const two = writeUserPromptTwoStage(args);
  const today = writeUserPrompt(args);
  assert(!two.includes("「有他」做法"));
  assert(today.includes("「有他」做法"));
  const b23 = GUIDE_V3_ENTRIES.find((e) => e.id === "B23")!;
  assertStringIncludes(
    two,
    `- B23（${b23.trigger}）：${twoStageEntryWriting(b23)}`,
  );
  assertStringIncludes(
    twoStageEntryWriting(b23),
    `「${TWO_STAGE_METHOD_LABEL}」`,
  );
  assertStringIncludes(
    two,
    "第 4 輪・她：\n1. [照片：一盤咖哩飯]\n2. 我自己煮的！\n3. 好想你喔",
  );
  assertStringIncludes(two, "這張接：她的「好想你喔」");
  // 規格以外的段落跟今天一樣。
  const before = (text: string) => text.split("## 卡片規格")[0];
  assertEquals(
    before(two),
    before(today).replace(
      "第 4 輪・她：\n- [照片：一盤咖哩飯]\n- 我自己煮的！\n- 好想你喔",
      "第 4 輪・她：\n1. [照片：一盤咖哩飯]\n2. 我自己煮的！\n3. 好想你喔",
    ).replace(b23.writing, twoStageEntryWriting(b23)),
  );
});

Deno.test("兩段式寫卡的外洩哨兵：都是新加段落裡的字，今天的提示詞沒有，重播錄音的卡一張都不中", () => {
  const two = writeSystemPromptTwoStage();
  const today = writeSystemPrompt();
  for (const sentinel of TWO_STAGE_WRITER_SENTINELS) {
    assert([...sentinel].length >= 8, sentinel);
    assertStringIncludes(two, sentinel);
    assert(!today.includes(sentinel), sentinel);
  }
  const cards = fixtures.cases.flatMap((c) =>
    (c.expected.events as { type: string; messages?: string[] }[])
      .filter((e) => e.type === "analysis.card")
      .map((e) => (e.messages ?? []).join("\n"))
  );
  assert(cards.length > 50);
  for (const card of cards) {
    assertEquals(containsPromptLeak(card, TWO_STAGE_WRITER_SENTINELS), false);
  }
});
