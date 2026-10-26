// 兩段式實驗（ANALYZE_GUIDE_V3_TWO_STAGE）× 關係訊號（ANALYZE_GUIDE_V3_RELATION）四種組合（Eric
// 2026-10-20 兩邊都上線）：同一個情境（flag_matrix_harness.ts）跑正式流程，事件、送給模型的請求、
// 扣費、落帳與 log 整份算 sha256。對照值是同一個情境跑兩邊原始快照（git archive）算出來的：
// main 6ef72aff（都沒開、只開關係訊號）與兩段式 c8f64dfe（只開兩段式；main 後來加的 completedAt
// 拿掉再比）。兩個都開沒有對照快照，逐項檢查組法。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  FLAG_MATRIX_MESSAGES,
  FLAG_MATRIX_SWEET_MESSAGES,
  FLAG_MATRIX_SWEET_ONLY_MESSAGES,
  FLAG_MATRIX_T0,
  FLAG_MATRIX_TAGS,
  FLAG_MATRIX_TIRED_MESSAGES,
  flagMatrixCards,
  flagMatrixReadText,
  flagMatrixSweetReadText,
  flagMatrixTiredReadText,
  outcomeDigest,
  runFlagMatrix,
  withoutKeys,
} from "./flag_matrix_harness.ts";
import { GUIDE_V3_ENTRIES } from "./entries.ts";
import { readSystemPrompt } from "./prompts.ts";
import { READ_TAGS_SCHEMA_TWO_STAGE, withHerTired } from "./read_tags.ts";
import { WRITER_TRIM_ENTRY_IDS } from "./rules.ts";
import {
  RELATION_FIELD_NOTES,
  RELATION_SENTINELS,
  withRelationFields,
} from "./relation.ts";
import { explainSystemPrompt } from "./explain.ts";
import { handleGuideV3Stream } from "./stream_flow.ts";
import { detectTypingHabits, styleCard } from "./typing_style.ts";
import { toTurns } from "./turns.ts";
import {
  HER_TIRED_NOTE,
  LIGHT_SHORT_CARD_PART,
  NO_IOU_READ_SENTINELS,
  READ_TAGS_SCHEMA_TWO_STAGE_SWEET_WITH_RELATION,
  READ_TAGS_SCHEMA_TWO_STAGE_WITH_RELATION,
  READ_TWO_STAGE_NOTES,
  readSystemPromptTwoStageWithRelation,
  readUserPromptTwoStage,
  SWEET_SHORT_CARD_PART,
  SWEET_WORTHY_LINES_NOTE,
  TENSION_STYLE_LINE,
  TWO_STAGE_WRITER_SENTINELS,
  twoStageEntryWriting,
  WRITER_TRIM_A5_SENTENCE,
  writeSystemPromptTwoStage,
} from "./two_stage_prompts.ts";

/// main 6ef72aff 的原始快照跑同一個情境（兩個開關都是 false）。
const MAIN_6EF72AFF_OFF =
  "4ba3f3d04478b9600ab6c1ebd1f1eae8aff3e0ca29e64b6546837342cf6020b6";
/// main 6ef72aff 的原始快照，只開關係訊號。
const MAIN_6EF72AFF_RELATION =
  "713a19bed92ad4eb936f2a0387e99b2aee0a91c227be8396ad02cc37c986cd9a";
/// 兩段式 c8f64dfe 的原始快照，只開兩段式（那時還沒有 completedAt）。
const TWO_STAGE_C8F64DFE =
  "378f410f2ac9460e263f347be982fa7f78927330ef3c2e5630ea8ef12540deeb";
/// 合併後兩個都開的整份結果：鎖住這次上線的樣子，改了要連這裡一起改。主審第 1 輪 P2 之後結果多了
/// cardExplains（拿掉這個 key 跟之前的 a5f3b4fc… 一樣，只差這一處）。
const BOTH_ON =
  "37796f798818ef28e875fcaf8244f9be8c5e63bd1f1136104f006981c1445ffe";

const OFF = { twoStage: false, relation: false };
const RELATION_ONLY = { twoStage: false, relation: true };
const TWO_STAGE_ONLY = { twoStage: true, relation: false };
const BOTH = { twoStage: true, relation: true };
/// 正式上線的組合再開口吻與斷句（Bruce 2026-10-20 改法 3）的整份結果：鎖住，改了要連這裡一起改。
const BOTH_TYPING_ON =
  "f3aa55b861063390b3a79e4f9b0b04eeb5b51d8cbf809063c3f69173589a6829";

type Outcome = {
  events: { type: string; [key: string]: unknown }[];
  requests: Record<
    string,
    { system: string; user: string; schema?: unknown }
  >;
  calls: string[];
  markDone: Record<string, unknown>;
  logs: { event: string; metadata: Record<string, unknown> }[];
};

const run = async (
  combo: {
    twoStage: boolean;
    relation: boolean;
    typingStyle?: boolean;
    shortPraise?: boolean;
    tensionStyle?: boolean;
    phraseTidy?: boolean;
    sweetShort?: boolean;
    noIou?: boolean;
    writerTrim?: boolean;
  },
  options = {},
) =>
  await runFlagMatrix(
    handleGuideV3Stream,
    combo,
    options,
  ) as unknown as Outcome;

Deno.test("兩個開關都沒開：跟 main 6ef72aff 一模一樣（事件、請求、扣費、落帳、log 整份）", async () => {
  assertEquals(await outcomeDigest(await run(OFF)), MAIN_6EF72AFF_OFF);
});

Deno.test("只開關係訊號：跟 main 6ef72aff 開關係訊號一模一樣", async () => {
  assertEquals(
    await outcomeDigest(await run(RELATION_ONLY)),
    MAIN_6EF72AFF_RELATION,
  );
});

Deno.test("只開兩段式：跟 c8f64dfe 一模一樣，只多 main 加的 completedAt 與主審第 1 輪 P2 的 cardExplains（done、結果與落帳都帶）", async () => {
  const outcome = await run(TWO_STAGE_ONLY);
  assertEquals(
    await outcomeDigest(withoutKeys(outcome, ["completedAt", "cardExplains"])),
    TWO_STAGE_C8F64DFE,
  );
  const explained = outcome.events.filter((e) =>
    e.type === "analysis.card_explain"
  ).map((e) => ({ card: e.card, text: e.text }));
  assert(explained.length > 0);
  assertEquals(
    (outcome.events.find((e) => e.type === "analysis.done")!
      .finalResult as Record<string, unknown>).cardExplains,
    explained,
  );
  const done = outcome.events.find((e) => e.type === "analysis.done")!;
  const at = new Date(FLAG_MATRIX_T0).toISOString();
  assertEquals(done.completedAt, at);
  assertEquals((done.finalResult as Record<string, unknown>).completedAt, at);
  assertEquals(outcome.markDone.completedAt, at);
});

Deno.test("兩個都開：讀局面帶兩段欄位說明（關係那段在最後）、schema 是兩段式四欄後接關係三欄、對話逐則編號", async () => {
  const outcome = await run(BOTH);
  const read = outcome.requests.read;
  assertEquals(read.system, readSystemPromptTwoStageWithRelation());
  assertEquals(
    read.system,
    readSystemPrompt(
      undefined,
      undefined,
      undefined,
      `${READ_TWO_STAGE_NOTES}\n\n${RELATION_FIELD_NOTES}`,
    ),
  );
  const twoAt = read.system.indexOf(READ_TWO_STAGE_NOTES);
  const relationAt = read.system.indexOf(RELATION_FIELD_NOTES);
  assert(twoAt > 0 && relationAt > twoAt);
  assert(relationAt < read.system.indexOf("## 情境條目的觸發"));
  assertEquals(read.schema, READ_TAGS_SCHEMA_TWO_STAGE_WITH_RELATION);
  assertEquals(read.schema, withRelationFields(READ_TAGS_SCHEMA_TWO_STAGE));
  const schema = read.schema as {
    required: string[];
    properties: Record<string, unknown>;
  };
  const tail = [
    "establishedCouple",
    "herAffection",
    "herHappyShare",
    "worthyLines",
    "gameStage",
    "heatScore",
    "dimensions",
  ];
  assertEquals(schema.required.slice(-7), tail);
  assertEquals(Object.keys(schema.properties).slice(-7), tail);
  assertEquals(
    read.user,
    readUserPromptTwoStage(toTurns(FLAG_MATRIX_MESSAGES)),
  );
});

Deno.test("兩個都開：寫卡與說明的請求跟只開兩段式一字不差；判讀帶跟只開關係訊號一樣的 relation；說明在卡之後、done 之前，done 帶 completedAt", async () => {
  const both = await run(BOTH);
  const twoStage = await run(TWO_STAGE_ONLY);
  const relation = await run(RELATION_ONLY);
  assertEquals(both.requests.write, twoStage.requests.write);
  assertEquals(both.requests.write.system, writeSystemPromptTwoStage());
  assertEquals(both.requests.explain, twoStage.requests.explain);
  const readOf = (o: Outcome) =>
    o.events.find((e) => e.type === "analysis.read")!;
  assertEquals(readOf(both).relation, readOf(relation).relation);
  assert(readOf(both).relation !== undefined);
  const kinds = both.events.map((e) => e.type);
  assert(
    kinds.lastIndexOf("analysis.card") < kinds.indexOf("analysis.card_explain"),
  );
  assert(
    kinds.lastIndexOf("analysis.card_explain") < kinds.indexOf("analysis.done"),
  );
  const cards = both.events.filter((e) => e.type === "analysis.card");
  assertEquals(
    both.events.filter((e) => e.type === "analysis.card_explain").map((e) =>
      e.card
    ),
    cards.map((c) => c.slot),
  );
  assertEquals(
    both.events.find((e) => e.type === "analysis.done")!.completedAt,
    new Date(FLAG_MATRIX_T0).toISOString(),
  );
  const trace = both.markDone.guideV3Trace as Record<string, unknown>;
  assertEquals(
    (trace.relation as { dropped: unknown[] }).dropped,
    [],
  );
  assertEquals(
    (trace.twoStage as { explain: { status: string } }).explain.status,
    "ok",
  );
  assertEquals(await outcomeDigest(both), BOTH_ON);
});

Deno.test("兩個都開：兩份哨兵都管——卡抄兩段式寫卡新加的段落就拿掉；判讀抄關係那段就不給（只開兩段式時照給）", async () => {
  const leakyCards = (user: string) =>
    flagMatrixCards(user).map((line, i) =>
      i === 0
        ? JSON.stringify({
          card: 1,
          messages: [TWO_STAGE_WRITER_SENTINELS[0]],
          hasInventedDetail: false,
        }) + "\n"
        : line
    );
  const both = await run(BOTH, { writeParts: leakyCards });
  const removed =
    (both.markDone.guideV3Trace as { removed: { reason: string }[] }).removed;
  assertEquals(removed.map((r) => r.reason), ["prompt_leak"]);
  const leakyJudgment = (combo: typeof OFF) =>
    JSON.stringify({
      ...JSON.parse(flagMatrixReadText(combo)),
      readForUser: `${FLAG_MATRIX_TAGS.readForUser}${RELATION_SENTINELS[2]}`,
    });
  const judgmentOf = (o: Outcome) =>
    o.events.find((e) => e.type === "analysis.read")!.judgment;
  const bothJudgment = await run(BOTH, { readText: leakyJudgment(BOTH) });
  assertEquals(judgmentOf(bothJudgment), "");
  assert(
    bothJudgment.logs.some((l) =>
      l.event === "guide_v3_coach_text_removed" &&
      l.metadata.field === "judgment"
    ),
  );
  const twoStageJudgment = await run(TWO_STAGE_ONLY, {
    readText: leakyJudgment(TWO_STAGE_ONLY),
  });
  assert(String(judgmentOf(twoStageJudgment)).includes(RELATION_SENTINELS[2]));
});

// ---- 口吻與斷句交給程式（ANALYZE_GUIDE_V3_TYPING_STYLE，Bruce 2026-10-20 改法 3） ----

Deno.test("口吻與斷句明確關著（false）：四種組合的整份結果跟沒給一模一樣（雜湊照舊）", async () => {
  assertEquals(
    await outcomeDigest(await run({ ...OFF, typingStyle: false })),
    MAIN_6EF72AFF_OFF,
  );
  assertEquals(
    await outcomeDigest(await run({ ...RELATION_ONLY, typingStyle: false })),
    MAIN_6EF72AFF_RELATION,
  );
  assertEquals(
    await outcomeDigest(
      withoutKeys(await run({ ...TWO_STAGE_ONLY, typingStyle: false }), [
        "completedAt",
        "cardExplains",
      ]),
    ),
    TWO_STAGE_C8F64DFE,
  );
  assertEquals(
    await outcomeDigest(await run({ ...BOTH, typingStyle: false })),
    BOTH_ON,
  );
});

type Rec = Record<string, unknown>;
const HIS_MESSAGES = FLAG_MATRIX_MESSAGES.filter((m) => m.isFromMe).map((m) =>
  m.content
);
const cardsOf = (o: Outcome) =>
  o.events.filter((e) => e.type === "analysis.card") as unknown as {
    slot: number;
    messages: string[];
  }[];

Deno.test("口吻與斷句開（兩段式、關係訊號都開）：送出的卡、扣費的第一張、存的結果、說明步驟看到的卡都是改過的字；trace 記習慣與次數；讀局面與寫卡的請求跟沒開一樣", async () => {
  const off = await run(BOTH);
  const on = await run({ ...BOTH, typingStyle: true });
  const habits = detectTypingHabits(HIS_MESSAGES);
  const offCards = cardsOf(off);
  const onCards = cardsOf(on);
  assertEquals(
    onCards.map((c) => c.messages),
    offCards.map((c) => styleCard(c.messages, habits).messages),
  );
  // 這段他沒打過逗號、也沒有稱呼：逗號全換成空白。
  assert(offCards.every((c) => c.messages.some((m) => m.includes("，"))));
  assert(onCards.every((c) => c.messages.every((m) => !m.includes("，"))));
  // 存的結果、扣費內容的第一張卡、說明步驟看到的卡，都是同一份改過的字。
  assertEquals(
    (on.markDone.cards as { messages: string[] }[]).map((c) => c.messages),
    onCards.map((c) => c.messages),
  );
  const charges = (on as unknown as { charges: Rec[] }).charges;
  assertEquals(
    ((charges[0].recommendationJson as Rec).firstCard as Rec).messages,
    onCards[0].messages,
  );
  const explainUser = on.requests.explain.user;
  for (const card of onCards) {
    for (const m of card.messages) assert(explainUser.includes(`- ${m}`), m);
  }
  assertEquals(explainUser.includes("，第 1 張"), false);
  // 讀局面與寫卡的請求不受影響（只改送出的卡）。
  assertEquals(on.requests.read, off.requests.read);
  assertEquals(on.requests.write, off.requests.write);
  const trace = (on.markDone.guideV3Trace as Rec).typingStyle as {
    habits: unknown;
    changes: { commas: number; messages: number };
  };
  assertEquals(trace.habits, habits);
  assertEquals(trace.changes.commas, onCards.length);
  assertEquals(trace.changes.messages, onCards.length);
  // 存的 trace 只有次數與習慣，沒有卡片的字。
  assertEquals(JSON.stringify(trace).includes("好看"), false);
  assertEquals(await outcomeDigest(on), BOTH_TYPING_ON);
});

Deno.test("口吻與斷句開、兩段式沒開：卡一樣照他的習慣改（不靠兩段式）；沒開的同一組不改", async () => {
  for (const combo of [OFF, RELATION_ONLY]) {
    const off = await run(combo);
    const on = await run({ ...combo, typingStyle: true });
    const habits = detectTypingHabits(HIS_MESSAGES);
    assertEquals(
      cardsOf(on).map((c) => c.messages),
      cardsOf(off).map((c) => styleCard(c.messages, habits).messages),
    );
    assert(
      cardsOf(off).some((c) => c.messages.some((m) => m.includes("，"))),
    );
  }
});

// ---- 寫卡第 4 輪（Bruce 2026-10-20）：短版稱讚、帶張力改寫法 ----

/// 正式上線的組合（兩段式、關係訊號、口吻與斷句都開）。
const PRODUCTION = { ...BOTH, typingStyle: true };
/// 正式組合再開帶張力改寫法 v2 的整份結果：鎖住，改了要連這裡一起改。寫卡的系統提示詞換推拉那一行、說明的
/// 系統提示詞多一條規則（這段她在撒嬌，沒有帶張力的卡，說明的使用者訊息不變）；兩份系統提示詞換回沒開的就是
/// f3aa55b8…。
const PRODUCTION_TENSION_STYLE_ON =
  "6bbd7a3b79aabc806a7c38ca0b1e475a1ebd838c15c7d1b653dd642a06cdb203";
/// 正式組合再開短版稱讚、她沒撒嬌（輕輕誇；matrix-run 這個 runId 抽到短版）的整份結果：鎖住。跟下面的對照只差
/// 寫卡與說明使用者訊息裡短版那段（各一處）與 trace 規格的 shortPraise（一處）。
const PRODUCTION_SHORT_PRAISE_LIGHT_ON =
  "03da6d6b909c3c5871d66de8d0ee66854eb7361edb6b168bdd458409e35e9f1f";
/// 同一個情境（她沒撒嬌）短版稱讚沒開時的整份結果（上面那個的對照）。
const PRODUCTION_LIGHT_OFF =
  "ce5c0f0d69a0dce30608d93be52273488f56d97ccedf5c6ec785b1662e306e99";

Deno.test("第 4 輪兩個開關明確關著（false）：每種組合的整份結果跟沒給一模一樣（雜湊照舊）", async () => {
  const off = { shortPraise: false, tensionStyle: false };
  assertEquals(
    await outcomeDigest(await run({ ...OFF, ...off })),
    MAIN_6EF72AFF_OFF,
  );
  assertEquals(
    await outcomeDigest(await run({ ...RELATION_ONLY, ...off })),
    MAIN_6EF72AFF_RELATION,
  );
  assertEquals(
    await outcomeDigest(
      withoutKeys(await run({ ...TWO_STAGE_ONLY, ...off }), [
        "completedAt",
        "cardExplains",
      ]),
    ),
    TWO_STAGE_C8F64DFE,
  );
  assertEquals(await outcomeDigest(await run({ ...BOTH, ...off })), BOTH_ON);
  assertEquals(
    await outcomeDigest(await run({ ...PRODUCTION, ...off })),
    BOTH_TYPING_ON,
  );
});

Deno.test("第 4 輪兩個開關開、兩段式沒開：整份結果跟沒開一模一樣（只在兩段式開時有作用）", async () => {
  const on = { shortPraise: true, tensionStyle: true };
  assertEquals(
    await outcomeDigest(await run({ ...OFF, ...on })),
    MAIN_6EF72AFF_OFF,
  );
  assertEquals(
    await outcomeDigest(await run({ ...RELATION_ONLY, ...on })),
    MAIN_6EF72AFF_RELATION,
  );
});

Deno.test("正式組合再開帶張力改寫法：寫卡與說明的系統提示詞換帶張力那幾行；讀局面、寫卡的規格與卡都不變", async () => {
  const off = await run(PRODUCTION);
  const on = await run({ ...PRODUCTION, tensionStyle: true });
  assertEquals(on.requests.read, off.requests.read);
  assertEquals(on.requests.write.user, off.requests.write.user);
  assertEquals(
    on.requests.write.system,
    writeSystemPromptTwoStage(undefined, undefined, undefined, {
      tensionStyle: true,
    }),
  );
  assert(on.requests.write.system.includes(TENSION_STYLE_LINE));
  assertEquals(
    on.requests.explain.system,
    explainSystemPrompt(undefined, undefined, { tensionStyle: true }),
  );
  assertEquals(on.requests.explain.user, off.requests.explain.user);
  assertEquals(cardsOf(on), cardsOf(off));
  assertEquals(await outcomeDigest(on), PRODUCTION_TENSION_STYLE_ON);
});

/// 同一段對話，但她這一輪沒撒嬌（程式挑輕輕誇）。
const notAffectionate = (combo: typeof PRODUCTION) =>
  JSON.stringify({
    ...JSON.parse(flagMatrixReadText(combo)),
    herAffection: false,
  });

Deno.test("正式組合再開短版稱讚：她撒嬌（直接誇）時跟沒開一模一樣；她沒撒嬌、這個 runId 抽到短版時，一張卡的規格與說明多短版那段", async () => {
  // 她撒嬌：直接誇，不會用短版，整份結果跟沒開一樣。
  assertEquals(
    await outcomeDigest(await run({ ...PRODUCTION, shortPraise: true })),
    BOTH_TYPING_ON,
  );
  const readText = notAffectionate(PRODUCTION);
  const off = await run(PRODUCTION, { readText });
  const on = await run({ ...PRODUCTION, shortPraise: true }, { readText });
  assertEquals(off.requests.write.user.includes(LIGHT_SHORT_CARD_PART), false);
  assertEquals(
    on.requests.write.user.split(LIGHT_SHORT_CARD_PART).length - 1,
    1,
  );
  assertEquals(
    on.requests.explain.user.split(LIGHT_SHORT_CARD_PART).length - 1,
    1,
  );
  // 稱讚那段跟一般輕輕誇一樣；讀局面、寫卡的系統提示詞不變。
  assertEquals(on.requests.read, off.requests.read);
  assertEquals(on.requests.write.system, off.requests.write.system);
  const specs = (on.markDone.guideV3Trace as { specs: Rec[] }).specs;
  assertEquals(specs.filter((s) => s.shortPraise === true).length, 1);
  assertEquals(await outcomeDigest(off), PRODUCTION_LIGHT_OFF);
  assertEquals(await outcomeDigest(on), PRODUCTION_SHORT_PRAISE_LIGHT_ON);
});

// ---- 「這題」「滿→蠻」交給程式（ANALYZE_GUIDE_V3_PHRASE_TIDY，Bruce 2026-10-20 PR #97 再處理） ----

/// 正式組合（兩段式、關係訊號、口吻與斷句都開）再開「這題」「滿→蠻」的整份結果：鎖住，改了要連這裡
/// 一起改。卡沒有這兩種字，拿掉 trace 的 phraseTidy 就是 BOTH_TYPING_ON。「不怪」那條拿掉（Bruce 2026-10-21）
/// 之後 trace 少了 herWorries 與 worry 次數，所以從 56a9b571… 換成 6634fa48…；錯字「一齣現」（Bruce 2026-10-21）
/// 多記 typo 次數之後 trace 多一個 typo: 0，再換成這個。拿掉 typo 就是 6634fa48…（下面有比），送出、扣費、落帳
/// 與 log 都沒變。
const BOTH_TYPING_TIDY_ON =
  "db1e2830a5d2b3d945afbec5f8c5d5006c643a6f7cd80e0f3bcbc7248b0dab0c";
const BOTH_TYPING_TIDY_ON_BEFORE_TYPO =
  "6634fa484186680a07d3a6dd295e13d8575a8b3508c27dd4b16ef2cc1ec22578";

Deno.test("「這題」「滿→蠻」明確關著（false）：四種組合與再開口吻與斷句的整份結果都跟沒給一模一樣（雜湊照舊）", async () => {
  const off = { phraseTidy: false };
  assertEquals(
    await outcomeDigest(await run({ ...OFF, ...off })),
    MAIN_6EF72AFF_OFF,
  );
  assertEquals(
    await outcomeDigest(await run({ ...RELATION_ONLY, ...off })),
    MAIN_6EF72AFF_RELATION,
  );
  assertEquals(
    await outcomeDigest(
      withoutKeys(await run({ ...TWO_STAGE_ONLY, ...off }), [
        "completedAt",
        "cardExplains",
      ]),
    ),
    TWO_STAGE_C8F64DFE,
  );
  assertEquals(await outcomeDigest(await run({ ...BOTH, ...off })), BOTH_ON);
  assertEquals(
    await outcomeDigest(await run({ ...BOTH, typingStyle: true, ...off })),
    BOTH_TYPING_ON,
  );
});

Deno.test("「這題」「滿→蠻」開、卡沒有這兩種字：卡、請求、扣費、落帳與 log 都跟沒開一樣，只多 trace 的 phraseTidy（次數都是 0）", async () => {
  const on = await run({
    ...BOTH,
    typingStyle: true,
    phraseTidy: true,
  });
  assertEquals(
    await outcomeDigest(withoutKeys(on, ["phraseTidy"])),
    BOTH_TYPING_ON,
  );
  assertEquals((on.markDone.guideV3Trace as Rec).phraseTidy, {
    herQuizWords: false,
    changes: {
      quiz: 0,
      quizRewrite: 0,
      degree: 0,
      typo: 0,
      messages: 0,
    },
  });
  assertEquals(await outcomeDigest(on), BOTH_TYPING_TIDY_ON);
  assertEquals(
    await outcomeDigest(withoutKeys(on, ["typo"])),
    BOTH_TYPING_TIDY_ON_BEFORE_TYPO,
  );
});

/// 卡裡有「這題」「不怪」「滿」：「不怪」那條不用（Bruce 2026-10-21），「不怪啊」不動。
const TIDY_CARD = ["好看啊 這題不用想", "不怪啊 滿適合你的"];
const tidyCards = (user: string) =>
  flagMatrixCards(user).map((_, i) =>
    JSON.stringify({
      card: i + 1,
      messages: TIDY_CARD,
      hasInventedDetail: false,
    }) + "\n"
  );

Deno.test("「這題」「滿→蠻」開（正式組合）：送出的卡、扣費的第一張、存的結果、說明步驟看到的都是改過的字；「不怪啊」不動；讀局面與寫卡的請求跟沒開一樣", async () => {
  const combo = { ...BOTH, typingStyle: true };
  const off = await run(combo, { writeParts: tidyCards });
  const on = await run({ ...combo, phraseTidy: true }, {
    writeParts: tidyCards,
  });
  const expected = ["好看啊", "不怪啊 蠻適合你的"];
  assert(cardsOf(off).every((c) => c.messages.join() === TIDY_CARD.join()));
  const onCards = cardsOf(on);
  assert(onCards.length > 0);
  for (const card of onCards) assertEquals(card.messages, expected);
  assertEquals(
    (on.markDone.cards as { messages: string[] }[]).map((c) => c.messages),
    onCards.map(() => expected),
  );
  const charges = (on as unknown as { charges: Rec[] }).charges;
  assertEquals(
    ((charges[0].recommendationJson as Rec).firstCard as Rec).messages,
    expected,
  );
  const explainUser = on.requests.explain.user;
  assert(explainUser.includes("- 好看啊\n- 不怪啊 蠻適合你的"));
  assertEquals(explainUser.includes("這題不用想"), false);
  assertEquals(on.requests.read, off.requests.read);
  assertEquals(on.requests.write, off.requests.write);
  const trace = (on.markDone.guideV3Trace as Rec).phraseTidy as {
    changes: Record<string, number>;
  };
  assertEquals(trace.changes, {
    quiz: onCards.length,
    quizRewrite: 0,
    degree: onCards.length,
    typo: 0,
    messages: onCards.length * 2,
  });
  assertEquals(JSON.stringify(trace).includes("適合"), false);
});

// ---- 甜話短回（ANALYZE_GUIDE_V3_SWEET_SHORT，Eric 2026-10-22「照預設」；Codex 主審第 1 輪 P2 改成讀局面逐則標「撒嬌」） ----

/// 正式環境現在開著、這個情境用得到的開關全開（兩段式、關係訊號、口吻與斷句、短版稱讚、帶張力改寫法、「這題」「滿→蠻」；
/// v3、上一輪脈絡、對象記憶不在這個情境裡）：正式環境九個開關在這個工具裡的樣子。
const PRODUCTION_ALL = {
  ...PRODUCTION,
  shortPraise: true,
  tensionStyle: true,
  phraseTidy: true,
};
/// 上面那組（原本的情境）的整份結果：鎖住。拿同一個情境跑 main b36614c7 的原始快照算出來的一樣（甜話短回沒開的對照）。
const PRODUCTION_ALL_OFF =
  "20921e63d35664c28de17fb89b6a7b56370909425c964ca673b6d8bdc4fabab8";
/// 開著、情境不是甜話（原本的情境她先問他），正式組合與全開的整份結果：鎖住。主審第 1 輪 P2 之後開著時讀局面的請求換
/// worthyLines 那一條、schema 多撒嬌，所以跟關著不同；把讀局面的請求換回沒開的，就是 f3aa55b8…、20921e63…（下面有比）。
const PRODUCTION_ON_NOT_SWEET =
  "f06d6c72df2f3b6546e8d61976cae64ccb731a491d560089583076ff6ff90b0c";
const PRODUCTION_ALL_ON_NOT_SWEET =
  "71dae596677a280927bf28ca566bd588e995ae1577ef95a2975bb2c3a42cec87";
/// 甜話情境（flag_matrix_harness.ts 的 FLAG_MATRIX_SWEET_*：交往中，她先撒嬌「只想要你哄❤️」、再說腳底痛，句子全新），正式
/// 組合與全開各自沒開、開的整份結果：鎖住。沒開的跟 main b36614c7 原始快照跑同一個情境一樣（讀局面標情感）。開的（主審第 1 輪
/// P2 之後重鎖：957339f6…→e56eb236…、51d7efba…→cdb93e0b…）比沒開多差讀局面的請求（worthyLines 那一條、schema 多撒嬌）與
/// trace 的讀局面標記（甜話那則標撒嬌），其餘照舊只差寫卡與說明的使用者訊息、trace 的規格（下面逐項比）。
const SWEET_PRODUCTION_OFF =
  "1992c55c2086d80aa9cf1bc0d21ab8897e078499f736ada346a9d44cd6aa5b6d";
const SWEET_PRODUCTION_ON =
  "e56eb23672ebc609a806661d49f5543be4b33fc8a56961db7a3072e534007f1f";
const SWEET_ALL_OFF =
  "81d3e66ee1fb0b1a36c748a932415f229727d419f6a5da4fff129cef4c02be6e";
const SWEET_ALL_ON =
  "cdb93e0b794515d95b4a9d2bf17ee339a24fcf25d53e639151c3bd463c5e14dd";
/// 同一段對話、她只傳那句甜話（少出幾張：4→3）。沒開的兩個一樣跟 main b36614c7 原始快照算的一樣；開的同上重鎖
///（7f24f171…→12954517…、fe4d3529…→5d03d4dd…）。
const SWEET_ONLY_PRODUCTION_OFF =
  "92cafa5c9f27c8a9cc5b4c9d048a0a437554e7a1488ec55e620931f220865dbe";
const SWEET_ONLY_PRODUCTION_ON =
  "129545177a14d565977f2cb8f390015e13d5f1f9390e2d713f8769f52ec9c925";
const SWEET_ONLY_ALL_OFF =
  "c544a4561a49f18fb925bbe99dfc78b5f4d366410199c880653d0f7b7adc23b9";
const SWEET_ONLY_ALL_ON =
  "5d03d4dd1811d2e74a53b0fc2cc47d6e7d2b989c2513ece30553b400d4e5d8c7";
/// 甜話情境改成 Bruce 那次的形狀（A2）：腳底痛那則也標情感，沒開時每張卡先回腳底痛、甜話只當順帶（甜話不是本來先回的那則）。
/// 沒開的兩個跟 main b36614c7 原始快照跑同一個情境一樣；開的同上重鎖（aec931ef…→228677bc…、ebf0ba3a…→59aeae1a…）。
const A2_PRODUCTION_OFF =
  "1528203e2018f52f9573837d8b4643c6ef0192b83ad2b3561dbc8326f41e738a";
const A2_PRODUCTION_ON =
  "228677bc0f4f3d7e7ae32fd654411f6f7109d99be2438eb87a786882cf34d43c";
const A2_ALL_OFF =
  "d7e477efe351b41204381c260e77b9789444bad96f81139cb5f560c98187128e";
const A2_ALL_ON =
  "59aeae1a24678b7040edc6eb6a7d1723a39791c1f9ad32370f995e4971d49e08";

type Combo = Parameters<typeof run>[0];
const ON = <C extends Combo>(combo: C) => ({ ...combo, sweetShort: true });
const SWEET_ONLY_OVER = {
  worthyBallCount: 1,
  worthyLines: [{ line: 1, label: "撒嬌要他哄", kind: "情感" }],
};
/// 甜話情境：harness 的假讀局面跟真的模型一樣，開著（schema 有撒嬌）才把甜話那則標撒嬌，沒開標情感。
const sweetScenario = (combo: Combo, over: Rec = {}) => ({
  messages: FLAG_MATRIX_SWEET_MESSAGES,
  readText: flagMatrixSweetReadText(combo, over),
});
const sweetOnlyScenario = (combo: Combo) => ({
  messages: FLAG_MATRIX_SWEET_ONLY_MESSAGES,
  readText: flagMatrixSweetReadText(combo, SWEET_ONLY_OVER),
});
const A2_OVER = {
  worthyLines: [
    { line: 1, label: "撒嬌要他哄", kind: "情感" },
    { line: 2, label: "腳底痛", kind: "情感" },
  ],
};
const a2Scenario = (combo: Combo) => sweetScenario(combo, A2_OVER);
const specLinesOf = (user: string) =>
  user.split("\n").filter((l) => /^\d\. 任務：/.test(l));
const traceOf = (o: Outcome) => o.markDone.guideV3Trace as Rec;
/// 開著時讀局面的請求（關係訊號也開）：系統提示詞只換 worthyLines 那一條、schema 多撒嬌；使用者那一則跟沒開一樣。
const assertSweetRead = (on: Outcome, off: Outcome) => {
  assertEquals(on.requests.read.user, off.requests.read.user);
  assertEquals(
    on.requests.read.system,
    readSystemPromptTwoStageWithRelation(undefined, undefined, undefined, {
      sweetShort: true,
    }),
  );
  assert(on.requests.read.system.includes(SWEET_WORTHY_LINES_NOTE));
  assertEquals(
    off.requests.read.system.includes(SWEET_WORTHY_LINES_NOTE),
    false,
  );
  assertEquals(
    on.requests.read.schema,
    READ_TAGS_SCHEMA_TWO_STAGE_SWEET_WITH_RELATION,
  );
  assertEquals(
    off.requests.read.schema,
    READ_TAGS_SCHEMA_TWO_STAGE_WITH_RELATION,
  );
};
/// 開著的整份結果把這幾處換回沒開的：讀局面的請求、trace 的讀局面標記與規格、寫卡與說明的使用者訊息（key 的順序不變）。
const swapBack = (on: Outcome, off: Outcome) => ({
  ...on,
  requests: {
    ...on.requests,
    read: off.requests.read,
    write: { ...on.requests.write, user: off.requests.write.user },
    explain: { ...on.requests.explain, user: off.requests.explain.user },
  },
  markDone: {
    ...on.markDone,
    guideV3Trace: {
      ...traceOf(on),
      tags: traceOf(off).tags,
      specs: traceOf(off).specs,
    },
  },
});

Deno.test("甜話短回明確關著（false）：每種組合、原本的情境與甜話情境的整份結果都跟沒給一模一樣（既有雜湊照舊）", async () => {
  const off = { sweetShort: false };
  assertEquals(
    await outcomeDigest(await run({ ...OFF, ...off })),
    MAIN_6EF72AFF_OFF,
  );
  assertEquals(
    await outcomeDigest(await run({ ...RELATION_ONLY, ...off })),
    MAIN_6EF72AFF_RELATION,
  );
  assertEquals(
    await outcomeDigest(
      withoutKeys(await run({ ...TWO_STAGE_ONLY, ...off }), [
        "completedAt",
        "cardExplains",
      ]),
    ),
    TWO_STAGE_C8F64DFE,
  );
  assertEquals(await outcomeDigest(await run({ ...BOTH, ...off })), BOTH_ON);
  assertEquals(
    await outcomeDigest(await run({ ...PRODUCTION, ...off })),
    BOTH_TYPING_ON,
  );
  assertEquals(
    await outcomeDigest(
      await run({ ...PRODUCTION, tensionStyle: true, ...off }),
    ),
    PRODUCTION_TENSION_STYLE_ON,
  );
  assertEquals(
    await outcomeDigest(await run({ ...PRODUCTION, phraseTidy: true, ...off })),
    BOTH_TYPING_TIDY_ON,
  );
  const readText = notAffectionate(PRODUCTION);
  assertEquals(
    await outcomeDigest(await run({ ...PRODUCTION, ...off }, { readText })),
    PRODUCTION_LIGHT_OFF,
  );
  assertEquals(
    await outcomeDigest(
      await run({ ...PRODUCTION, shortPraise: true, ...off }, { readText }),
    ),
    PRODUCTION_SHORT_PRAISE_LIGHT_ON,
  );
  for (const combo of [PRODUCTION_ALL, { ...PRODUCTION_ALL, ...off }]) {
    assertEquals(await outcomeDigest(await run(combo)), PRODUCTION_ALL_OFF);
  }
  for (
    const [combo, scenario, digest] of [
      [PRODUCTION, sweetScenario, SWEET_PRODUCTION_OFF],
      [PRODUCTION_ALL, sweetScenario, SWEET_ALL_OFF],
      [PRODUCTION, sweetOnlyScenario, SWEET_ONLY_PRODUCTION_OFF],
      [PRODUCTION_ALL, sweetOnlyScenario, SWEET_ONLY_ALL_OFF],
      [PRODUCTION, a2Scenario, A2_PRODUCTION_OFF],
      [PRODUCTION_ALL, a2Scenario, A2_ALL_OFF],
    ] as const
  ) {
    assertEquals(
      await outcomeDigest(await run(combo, scenario(combo))),
      digest,
    );
    assertEquals(
      await outcomeDigest(
        await run({ ...combo, ...off }, scenario({ ...combo, ...off })),
      ),
      digest,
    );
  }
  // 其他每一種開關組合、四個情境：給 false 跟沒給一樣。
  const flags = [
    "typingStyle",
    "shortPraise",
    "tensionStyle",
    "phraseTidy",
  ] as const;
  for (const base of [OFF, RELATION_ONLY, TWO_STAGE_ONLY, BOTH]) {
    for (let mask = 0; mask < 1 << flags.length; mask++) {
      const combo: Combo = {
        ...base,
        ...Object.fromEntries(
          flags.map((f, i) => [f, (mask & (1 << i)) !== 0]),
        ),
      };
      for (
        const options of [
          {},
          sweetScenario(combo),
          sweetOnlyScenario(combo),
          a2Scenario(combo),
        ]
      ) {
        assertEquals(
          await outcomeDigest(await run({ ...combo, ...off }, options)),
          await outcomeDigest(await run(combo, options)),
          JSON.stringify(combo),
        );
      }
    }
  }
});

Deno.test("甜話短回開、兩段式沒開：整份結果跟沒開一模一樣（只在兩段式開時有作用；讀局面的請求也不變），甜話情境也一樣", async () => {
  assertEquals(
    await outcomeDigest(await run(ON(OFF))),
    MAIN_6EF72AFF_OFF,
  );
  assertEquals(
    await outcomeDigest(await run(ON(RELATION_ONLY))),
    MAIN_6EF72AFF_RELATION,
  );
  for (const combo of [OFF, RELATION_ONLY]) {
    for (const scenario of [sweetScenario, sweetOnlyScenario, a2Scenario]) {
      assertEquals(
        await outcomeDigest(await run(ON(combo), scenario(ON(combo)))),
        await outcomeDigest(await run(combo, scenario(combo))),
      );
    }
  }
});

Deno.test("甜話短回開、情境不是甜話：只差讀局面的請求（worthyLines 那一條、schema 多撒嬌）與 trace 的讀局面標記，排卡、卡、說明都跟關著一樣；原本的情境鎖住", async () => {
  for (
    const [combo, offDigest, onDigest] of [
      [PRODUCTION, BOTH_TYPING_ON, PRODUCTION_ON_NOT_SWEET],
      [PRODUCTION_ALL, PRODUCTION_ALL_OFF, PRODUCTION_ALL_ON_NOT_SWEET],
    ] as const
  ) {
    const off = await run(combo);
    const on = await run(ON(combo));
    assertSweetRead(on, off);
    assertEquals(on.requests.write, off.requests.write);
    assertEquals(on.requests.explain, off.requests.explain);
    assertEquals(await outcomeDigest(swapBack(on, off)), offDigest);
    assertEquals(await outcomeDigest(on), onDigest);
  }
  const replaced = (at: number, content: string) =>
    FLAG_MATRIX_SWEET_MESSAGES.map((m, i) => i === at ? { ...m, content } : m);
  const variants: [
    string,
    (c: Combo) => { messages: unknown; readText: string },
  ][] = [
    ["她沒撒嬌", (c) => sweetScenario(c, { herAffection: false })],
    [
      "那則 7 個字",
      (c) => ({
        messages: replaced(3, "好想好想要你哄❤️"),
        readText: flagMatrixSweetReadText(c),
      }),
    ],
    [
      "標成其他",
      (c) =>
        sweetScenario(c, {
          worthyLines: [
            { line: 1, label: "撒嬌要他哄", kind: "其他" },
            { line: 2, label: "腳底痛", kind: "其他" },
          ],
        }),
    ],
    [
      "同一輪也問他",
      (c) => ({
        messages: replaced(4, "你今天幾點下班"),
        readText: flagMatrixSweetReadText(c, {
          worthyLines: [
            { line: 1, label: "撒嬌要他哄", kind: "情感" },
            { line: 2, label: "問他幾點下班", kind: "問他" },
          ],
        }),
      }),
    ],
  ];
  for (const [name, scenario] of variants) {
    const offOut = await run(PRODUCTION, scenario(PRODUCTION));
    const onOut = await run(ON(PRODUCTION), scenario(ON(PRODUCTION)));
    assertSweetRead(onOut, offOut);
    assertEquals(
      await outcomeDigest(swapBack(onOut, offOut)),
      await outcomeDigest(offOut),
      name,
    );
    assertEquals(
      onOut.requests.write.user.includes(SWEET_SHORT_CARD_PART),
      false,
    );
  }
});

Deno.test("甜話短回開、甜話情境（正式組合、正式九個開關全開）：甜話那則標撒嬌時只有第 2 張（第一張不是推進的卡）回那句、多短回的指示，其他卡回腳底痛；讀局面的請求換那一條；鎖住", async () => {
  for (
    const [combo, offDigest, onDigest] of [
      [PRODUCTION, SWEET_PRODUCTION_OFF, SWEET_PRODUCTION_ON],
      [PRODUCTION_ALL, SWEET_ALL_OFF, SWEET_ALL_ON],
    ] as const
  ) {
    const off = await run(combo, sweetScenario(combo));
    const on = await run(ON(combo), sweetScenario(ON(combo)));
    assertSweetRead(on, off);
    assertEquals(on.requests.write.system, off.requests.write.system);
    assertEquals(on.requests.explain.system, off.requests.explain.system);
    // trace 的讀局面標記：開著時甜話那則標撒嬌，沒開標情感。
    const kinds = (o: Outcome) =>
      ((traceOf(o).tags as Rec).worthyLines as { kind: string }[]).map((w) =>
        w.kind
      );
    assertEquals(kinds(off), ["情感", "其他"]);
    assertEquals(kinds(on), ["撒嬌", "其他"]);
    // 寫卡的使用者訊息：規格以外一字不差；規格第 2 張回甜話、多短回的指示，其他張回腳底痛、完全不出現甜話那句。
    const others = (user: string) =>
      user.split("\n").filter((l) => !/^\d\. 任務：/.test(l));
    assertEquals(
      others(on.requests.write.user),
      others(off.requests.write.user),
    );
    const offSpecs = specLinesOf(off.requests.write.user);
    const onSpecs = specLinesOf(on.requests.write.user);
    assertEquals(onSpecs.length, 5);
    assertEquals(offSpecs.length, 5);
    for (const line of offSpecs) {
      assert(line.includes("這張接：她的「只想要你哄」｜可以順帶："), line);
    }
    assertEquals(
      onSpecs[1],
      `2. 任務：接住｜這張接：她的「只想要你哄」｜${SWEET_SHORT_CARD_PART}｜他的事怎麼寫：只用反應｜口吻：預設｜問句最多 1 個`,
    );
    for (const i of [0, 2, 3, 4]) {
      assert(
        onSpecs[i].includes("這張接：她的「今天穿新鞋走了好多路 腳底好痛」"),
        onSpecs[i],
      );
      assertEquals(onSpecs[i].includes("只想要你哄"), false);
      assertEquals(onSpecs[i].includes(SWEET_SHORT_CARD_PART), false);
    }
    assert(onSpecs[0].startsWith("1. 任務：推進（種子）｜"));
    // 換切入點照「回同一則」重算：第 4 張前面同規格的只有回甜話那張，不用換；第 5 張照舊要換。
    assertEquals(
      onSpecs.map((l) => l.endsWith("切入點要跟前面同規格的卡不同")),
      [false, false, false, false, true],
    );
    // 說明的使用者訊息：卡片標頭以外一字不差；標頭跟寫卡回同一則、同一段短回指示。
    const heads = (user: string) =>
      user.split("\n").filter((l) => /^任務：/.test(l));
    const notHeads = (user: string) =>
      user.split("\n").filter((l) => !/^任務：/.test(l));
    assertEquals(
      notHeads(on.requests.explain.user),
      notHeads(off.requests.explain.user),
    );
    assertEquals(
      heads(on.requests.explain.user)[1],
      `任務：接住｜他的事怎麼寫：只用反應｜這張接：她的「只想要你哄」｜${SWEET_SHORT_CARD_PART}`,
    );
    assertEquals(
      on.requests.explain.user.split(SWEET_SHORT_CARD_PART).length - 1,
      1,
    );
    // 卡、扣費、張數不變（有別的話時不少出）；trace 的規格只在第 2 張標 sweetShort。
    assertEquals(cardsOf(on), cardsOf(off));
    const specs = traceOf(on).specs as Rec[];
    assertEquals(specs.flatMap((s, i) => s.sweetShort === true ? [i] : []), [
      1,
    ]);
    // 讀局面的請求與標記、寫卡與說明的使用者訊息、trace 的規格換回沒開的，整份結果就跟沒開一模一樣。
    assertEquals(await outcomeDigest(swapBack(on, off)), offDigest);
    assertEquals(await outcomeDigest(off), offDigest);
    assertEquals(await outcomeDigest(on), onDigest);
  }
});

Deno.test("甜話短回開、她只傳那句甜話（正式組合、正式九個開關全開）：少出幾張（4→3），每張都回那句、都帶短回指示、不換切入點；讀局面的請求換那一條；鎖住", async () => {
  for (
    const [combo, offDigest, onDigest] of [
      [PRODUCTION, SWEET_ONLY_PRODUCTION_OFF, SWEET_ONLY_PRODUCTION_ON],
      [PRODUCTION_ALL, SWEET_ONLY_ALL_OFF, SWEET_ONLY_ALL_ON],
    ] as const
  ) {
    const off = await run(combo, sweetOnlyScenario(combo));
    const on = await run(ON(combo), sweetOnlyScenario(ON(combo)));
    assertSweetRead(on, off);
    assertEquals(on.requests.write.system, off.requests.write.system);
    assertEquals(on.requests.explain.system, off.requests.explain.system);
    assertEquals(cardsOf(off).length, 4);
    assertEquals(cardsOf(on).length, 3);
    const planned = (o: Outcome) =>
      (o.events.find((e) => e.type === "analysis.read")!.plannedCards as Rec[])
        .map((p) => p.task);
    assertEquals(planned(off), ["push", "accept", "accept", "accept"]);
    assertEquals(planned(on), ["push", "accept", "accept"]);
    const lines = specLinesOf(on.requests.write.user);
    assertEquals(lines.length, 3);
    for (const line of lines) {
      assert(
        line.includes(`這張接：她的「只想要你哄」｜${SWEET_SHORT_CARD_PART}｜`),
        line,
      );
      assertEquals(line.includes("切入點要跟前面同規格的卡不同"), false);
    }
    assertEquals(
      lines.map((l) => l.match(/口吻：(照他|預設)/)?.[1]),
      ["照他", "預設", "照他"],
    );
    assertEquals(
      on.requests.explain.user.split(SWEET_SHORT_CARD_PART).length - 1,
      3,
    );
    assert(on.requests.write.user.includes("一共 3 張"));
    assertEquals(
      (traceOf(on).specs as Rec[]).every((s) => s.sweetShort === true),
      true,
    );
    assertEquals(await outcomeDigest(off), offDigest);
    assertEquals(await outcomeDigest(on), onDigest);
  }
});

Deno.test("甜話短回開、A2 形狀（甜話標撒嬌在前、腳底痛標情感在後）：沒開時每張先回腳底痛、甜話當順帶；開了第 2 張回甜話，其他卡回腳底痛、不帶順帶；讀局面的請求換那一條；鎖住", async () => {
  for (
    const [combo, offDigest, onDigest] of [
      [PRODUCTION, A2_PRODUCTION_OFF, A2_PRODUCTION_ON],
      [PRODUCTION_ALL, A2_ALL_OFF, A2_ALL_ON],
    ] as const
  ) {
    const off = await run(combo, a2Scenario(combo));
    const on = await run(ON(combo), a2Scenario(ON(combo)));
    assertSweetRead(on, off);
    assertEquals(on.requests.write.system, off.requests.write.system);
    assertEquals(on.requests.explain.system, off.requests.explain.system);
    const offSpecs = specLinesOf(off.requests.write.user);
    const onSpecs = specLinesOf(on.requests.write.user);
    assertEquals(offSpecs.length, 5);
    assertEquals(onSpecs.length, 5);
    for (const line of offSpecs) {
      assert(
        line.includes(
          "這張接：她的「今天穿新鞋走了好多路 腳底好痛」｜可以順帶：她的「只想要你哄」",
        ),
        line,
      );
    }
    assertEquals(
      onSpecs[1],
      `2. 任務：接住｜這張接：她的「只想要你哄」｜${SWEET_SHORT_CARD_PART}｜他的事怎麼寫：只用反應｜口吻：預設｜問句最多 1 個`,
    );
    for (const i of [0, 2, 3, 4]) {
      assert(
        onSpecs[i].includes(
          "這張接：她的「今天穿新鞋走了好多路 腳底好痛」｜他的事怎麼寫：",
        ),
        onSpecs[i],
      );
      assertEquals(onSpecs[i].includes("只想要你哄"), false);
    }
    assertEquals(cardsOf(on), cardsOf(off));
    assertEquals(await outcomeDigest(swapBack(on, off)), offDigest);
    assertEquals(await outcomeDigest(off), offDigest);
    assertEquals(await outcomeDigest(on), onDigest);
  }
});

Deno.test("甜話短回開、甜話情境：說明寫到「短短回她一句就好」照送（只比卡片）；卡片寫到同一句就拿掉那張", async () => {
  const combo = ON(PRODUCTION);
  const explainText = (user: string) =>
    JSON.stringify({
      explanations: [...user.matchAll(/^### 第 (\d+) 張$/gmu)].map((m) => ({
        card: Number(m[1]),
        text: Number(m[1]) === 2
          ? `她撒嬌要你哄，這張${SWEET_SHORT_CARD_PART}。`
          : `第 ${m[1]} 張先回她說的事。`,
      })),
    });
  const kept = await run(combo, { ...sweetScenario(combo), explainText });
  const explains = kept.events.filter((e) =>
    e.type === "analysis.card_explain"
  );
  assertEquals(explains.map((e) => e.card), [1, 2, 3, 4, 5]);
  assert(String(explains[1].text).includes(SWEET_SHORT_CARD_PART));
  assertEquals(
    ((traceOf(kept).twoStage as Rec).explain as { removed: unknown[] }).removed,
    [],
  );
  const leakyCards = (user: string) =>
    flagMatrixCards(user).map((line, i) =>
      i === 2
        ? JSON.stringify({
          card: 3,
          messages: [`腳還好嗎 ${SWEET_SHORT_CARD_PART}`],
          hasInventedDetail: false,
        }) + "\n"
        : line
    );
  const leaky = await run(combo, {
    ...sweetScenario(combo),
    writeParts: leakyCards,
  });
  assertEquals(
    (traceOf(leaky).removed as { slot: number; reason: string }[]).map((r) => [
      r.slot,
      r.reason,
    ]),
    [[3, "prompt_leak"]],
  );
  // 沒排到（開關關著）時卡片同一句不比，照送。
  const off = await run(PRODUCTION, {
    ...sweetScenario(PRODUCTION),
    writeParts: leakyCards,
  });
  assertEquals(traceOf(off).removed, []);
});

// ---- 不記帳不承諾（ANALYZE_GUIDE_V3_NO_IOU，Bruce 2026-10-22 PR #97 盲選回覆；Eric 同日「回了 來處理吧」） ----

/// 甜話情境（交往中她撒嬌「只想要你哄❤️」、再說腳底痛），正式組合再開甜話短回與不記帳不承諾的整份結果：鎖住。沒有推進（種子），
/// 5 張都接住，第 1 張回甜話（短回）、其他回腳底痛。
const NOIOU_SWEET_PRODUCTION_ON =
  "511b455bb811ea7390eb7653ab0375a81af107d9111f3352ccd78e4de224ae09";
/// 同一個情境只開不記帳不承諾（甜話短回沒開）：5 張都接住，每張先回甜話、順帶腳底痛。鎖住。
const NOIOU_PRODUCTION_ON =
  "1522a39d302fef2a130156c2f8e4433301abc36525d10e2a445ec57431c97469";
/// 她只傳那句甜話，正式組合再開兩個：3 張都接住、都短回（甜話短回單開時第 1 張是推進（種子））。鎖住。
const NOIOU_SWEET_ONLY_PRODUCTION_ON =
  "c9f26925fe0b7f9b9073c49639418a4bb652a24a4c2987d3452733fc650d3e16";
/// 喊累情境（flag_matrix_harness.ts 的 FLAG_MATRIX_TIRED_*：交往中她開心地喊累、沒撒嬌，句子全新），全開（正式九個開關＋甜話短回）
/// 沒開與再開不記帳不承諾的整份結果：鎖住。沒開第 1 張是推進（種子）；開了 4 張都接住。
const TIRED_ALL_OFF =
  "52171c62b5cc5f54e178f5a1ec2469696d80741acaa355b3a15e7da6e6d781b1";
const TIRED_ALL_ON =
  "2e2ec851c835a4737acf5ec63ff3382615719a8f9076b3b63d8327efcaddd108";
/// 開著、情境不觸發種子規則（原本的情境：還沒交往、他只傳過一則，本來就沒有推進），正式組合與全開：鎖住。只差讀局面那一行、schema
/// 與 trace 讀局面標記的 herTired（這段她沒喊累，假讀局面標 false）；換回沒開的就是 f3aa55b8…、71dae596…（下面有比）。
const NOT_TRIGGERED_PRODUCTION_ON =
  "6c1939b218e639984df16146390c38b46e7f7d1fb6a740344919fd8c465fecd4";
const NOT_TRIGGERED_ALL_ON =
  "47f25612c84086aa815a02c57eec5eaa070a13584e4d2b9beb0753e85c2bc75d";

const NO_IOU = <C extends Combo>(combo: C) => ({ ...combo, noIou: true });
/// 全開：正式環境九個開關再開甜話短回（它比這個先上線）；不記帳不承諾另外用 NO_IOU 開。
const ALL_SWEET = { ...PRODUCTION_ALL, sweetShort: true };
/// 喊累情境：harness 的假讀局面跟真的模型一樣，開著（schema 有 herTired）才標 herTired。
const tiredScenario = (combo: Combo) => ({
  messages: FLAG_MATRIX_TIRED_MESSAGES,
  readText: flagMatrixTiredReadText(combo),
});
const plannedTasks = (o: Outcome) =>
  (o.events.find((e) => e.type === "analysis.read")!.plannedCards as Rec[])
    .map((p) => p.task);
const cardTasks = (o: Outcome) =>
  o.events.filter((e) => e.type === "analysis.card").map((e) => e.task);

/// 開著時的請求：讀局面只在 herAffection 下面多 herTired 那一行、schema 多 herTired，使用者那一則跟沒開一樣；寫卡與說明的系統提示詞
/// 不變。
const assertNoIouRequests = (on: Outcome, off: Outcome, combo: Combo) => {
  assertEquals(on.requests.read.user, off.requests.read.user);
  assertEquals(
    on.requests.read.system,
    readSystemPromptTwoStageWithRelation(undefined, undefined, undefined, {
      sweetShort: combo.sweetShort === true,
      noIou: true,
    }),
  );
  assertEquals(
    on.requests.read.system.replace(`\n${HER_TIRED_NOTE}`, ""),
    off.requests.read.system,
  );
  assertEquals(
    on.requests.read.schema,
    withHerTired(off.requests.read.schema as Record<string, unknown>),
  );
  assertEquals(on.requests.write.system, off.requests.write.system);
  assertEquals(on.requests.explain.system, off.requests.explain.system);
};
/// 開著的整份結果把這幾處換回沒開的：讀局面的請求、trace 的讀局面標記（key 的順序不變）。
const swapBackNoIou = (on: Outcome, off: Outcome) => ({
  ...on,
  requests: {
    ...on.requests,
    read: off.requests.read,
  },
  markDone: {
    ...on.markDone,
    guideV3Trace: { ...traceOf(on), tags: traceOf(off).tags },
  },
});

Deno.test("不記帳不承諾明確關著（false）：每種組合、每個情境的整份結果都跟沒給一模一樣（既有雜湊照舊）", async () => {
  const off = { noIou: false };
  const locked: [Combo, Rec, string][] = [
    [OFF, {}, MAIN_6EF72AFF_OFF],
    [RELATION_ONLY, {}, MAIN_6EF72AFF_RELATION],
    [BOTH, {}, BOTH_ON],
    [PRODUCTION, {}, BOTH_TYPING_ON],
    [{ ...PRODUCTION, tensionStyle: true }, {}, PRODUCTION_TENSION_STYLE_ON],
    [{ ...PRODUCTION, phraseTidy: true }, {}, BOTH_TYPING_TIDY_ON],
    [
      PRODUCTION,
      { readText: notAffectionate(PRODUCTION) },
      PRODUCTION_LIGHT_OFF,
    ],
    [
      { ...PRODUCTION, shortPraise: true },
      { readText: notAffectionate(PRODUCTION) },
      PRODUCTION_SHORT_PRAISE_LIGHT_ON,
    ],
    [PRODUCTION_ALL, {}, PRODUCTION_ALL_OFF],
    [ON(PRODUCTION), {}, PRODUCTION_ON_NOT_SWEET],
    [ON(PRODUCTION_ALL), {}, PRODUCTION_ALL_ON_NOT_SWEET],
  ];
  for (
    const [combo, scenario, digest] of [
      [PRODUCTION, sweetScenario, SWEET_PRODUCTION_OFF],
      [PRODUCTION_ALL, sweetScenario, SWEET_ALL_OFF],
      [ON(PRODUCTION), sweetScenario, SWEET_PRODUCTION_ON],
      [ON(PRODUCTION_ALL), sweetScenario, SWEET_ALL_ON],
      [PRODUCTION, sweetOnlyScenario, SWEET_ONLY_PRODUCTION_OFF],
      [PRODUCTION_ALL, sweetOnlyScenario, SWEET_ONLY_ALL_OFF],
      [ON(PRODUCTION), sweetOnlyScenario, SWEET_ONLY_PRODUCTION_ON],
      [ON(PRODUCTION_ALL), sweetOnlyScenario, SWEET_ONLY_ALL_ON],
      [PRODUCTION, a2Scenario, A2_PRODUCTION_OFF],
      [PRODUCTION_ALL, a2Scenario, A2_ALL_OFF],
      [ON(PRODUCTION), a2Scenario, A2_PRODUCTION_ON],
      [ON(PRODUCTION_ALL), a2Scenario, A2_ALL_ON],
    ] as const
  ) {
    locked.push([{ ...combo, ...off }, scenario({ ...combo, ...off }), digest]);
  }
  for (const [combo, options, digest] of locked) {
    assertEquals(
      await outcomeDigest(await run({ ...combo, ...off }, options)),
      digest,
      JSON.stringify(combo),
    );
  }
  assertEquals(
    await outcomeDigest(
      withoutKeys(await run({ ...TWO_STAGE_ONLY, ...off }), [
        "completedAt",
        "cardExplains",
      ]),
    ),
    TWO_STAGE_C8F64DFE,
  );
  // 其他每一種開關組合（含甜話短回）、五個情境：給 false 跟沒給一樣。
  const flags = [
    "typingStyle",
    "shortPraise",
    "tensionStyle",
    "phraseTidy",
    "sweetShort",
  ] as const;
  for (const base of [OFF, RELATION_ONLY, TWO_STAGE_ONLY, BOTH]) {
    for (let mask = 0; mask < 1 << flags.length; mask++) {
      const combo: Combo = {
        ...base,
        ...Object.fromEntries(
          flags.map((f, i) => [f, (mask & (1 << i)) !== 0]),
        ),
      };
      for (
        const scenario of [
          () => ({}),
          sweetScenario,
          sweetOnlyScenario,
          a2Scenario,
          tiredScenario,
        ]
      ) {
        assertEquals(
          await outcomeDigest(
            await run({ ...combo, ...off }, scenario({ ...combo, ...off })),
          ),
          await outcomeDigest(await run(combo, scenario(combo))),
          JSON.stringify(combo),
        );
      }
    }
  }
});

Deno.test("不記帳不承諾開、兩段式沒開：整份結果跟沒開一模一樣（只在兩段式開時有作用；讀局面的請求也不變），每個情境都一樣", async () => {
  assertEquals(
    await outcomeDigest(await run(NO_IOU(OFF))),
    MAIN_6EF72AFF_OFF,
  );
  assertEquals(
    await outcomeDigest(await run(NO_IOU(RELATION_ONLY))),
    MAIN_6EF72AFF_RELATION,
  );
  for (
    const combo of [
      OFF,
      RELATION_ONLY,
      { ...RELATION_ONLY, typingStyle: true, sweetShort: true },
    ]
  ) {
    for (
      const scenario of [
        sweetScenario,
        sweetOnlyScenario,
        a2Scenario,
        tiredScenario,
      ]
    ) {
      assertEquals(
        await outcomeDigest(await run(NO_IOU(combo), scenario(NO_IOU(combo)))),
        await outcomeDigest(await run(combo, scenario(combo))),
        JSON.stringify(combo),
      );
    }
  }
});

Deno.test("不記帳不承諾開、情境不觸發種子規則（原本的情境，本來就沒有推進）：只差讀局面那一行、schema 與 trace 的 herTired，排卡、寫卡的規格、卡、說明都跟關著一樣；正式組合與全開都鎖住", async () => {
  for (
    const [combo, offDigest, onDigest] of [
      [PRODUCTION, BOTH_TYPING_ON, NOT_TRIGGERED_PRODUCTION_ON],
      [ALL_SWEET, PRODUCTION_ALL_ON_NOT_SWEET, NOT_TRIGGERED_ALL_ON],
    ] as const
  ) {
    const off = await run(combo);
    const on = await run(NO_IOU(combo));
    assertNoIouRequests(on, off, combo);
    assertEquals(on.requests.write.user, off.requests.write.user);
    assertEquals(on.requests.explain, off.requests.explain);
    assertEquals(cardsOf(on), cardsOf(off));
    assertEquals(plannedTasks(on), plannedTasks(off));
    assertEquals(traceOf(on).push, null);
    assertEquals(traceOf(off).push, null);
    assertEquals((traceOf(on).tags as Rec).herTired, false);
    assertEquals("herTired" in (traceOf(off).tags as Rec), false);
    assertEquals(await outcomeDigest(swapBackNoIou(on, off)), offDigest);
    assertEquals(await outcomeDigest(off), offDigest);
    assertEquals(await outcomeDigest(on), onDigest);
  }
});

Deno.test("不記帳不承諾開、交往撒嬌情境（甜話情境）、正式組合再開甜話短回：沒有推進（種子），5 張都接住，第 1 張回甜話（短回）、其他回腳底痛；張數不變、扣費的第一張是接住；只開不記帳不承諾時每張先回甜話；都鎖住", async () => {
  const sweetOn = ON(PRODUCTION);
  const off = await run(sweetOn, sweetScenario(sweetOn));
  const on = await run(NO_IOU(sweetOn), sweetScenario(NO_IOU(sweetOn)));
  assertEquals(await outcomeDigest(off), SWEET_PRODUCTION_ON);
  assertNoIouRequests(on, off, sweetOn);
  // trace：讀局面多 herTired（這段她沒喊累，標 false）；push 拿掉、沒有推進的卡；短回只在第 1 張。
  assertEquals((traceOf(on).tags as Rec).herTired, false);
  assertEquals(traceOf(off).push, "種子");
  assertEquals(traceOf(on).push, null);
  const specs = traceOf(on).specs as Rec[];
  assertEquals(specs.map((s) => s.task), [
    "接住",
    "接住",
    "接住",
    "接住",
    "接住",
  ]);
  assertEquals(specs.every((s) => s.push === null), true);
  assertEquals(
    specs.flatMap((s, i) => s.sweetShort === true ? [i] : []),
    [0],
  );
  // 寫卡的規格：第 1 張回甜話、多短回的指示，其他回腳底痛；沒有推進。規格以外一字不差。
  const lines = specLinesOf(on.requests.write.user);
  assertEquals(lines.length, 5);
  assertEquals(
    lines[0],
    `1. 任務：接住｜這張接：她的「只想要你哄」｜${SWEET_SHORT_CARD_PART}｜他的事怎麼寫：只用反應｜口吻：照他｜問句最多 1 個`,
  );
  for (const line of lines.slice(1)) {
    assert(
      line.includes("這張接：她的「今天穿新鞋走了好多路 腳底好痛」"),
      line,
    );
  }
  assertEquals(on.requests.write.user.includes("推進"), false);
  const others = (user: string) =>
    user.split("\n").filter((l) => !/^\d\. 任務：/.test(l));
  assertEquals(others(on.requests.write.user), others(off.requests.write.user));
  // 送給 App 的：預定的卡與送出的卡都沒有 push，張數一樣；扣費紀錄的第一張是接住。
  assertEquals(plannedTasks(off), [
    "push",
    "accept",
    "accept",
    "accept",
    "accept",
  ]);
  assertEquals(plannedTasks(on), [
    "accept",
    "accept",
    "accept",
    "accept",
    "accept",
  ]);
  assertEquals(cardTasks(on), [
    "accept",
    "accept",
    "accept",
    "accept",
    "accept",
  ]);
  assertEquals(cardsOf(on).length, cardsOf(off).length);
  const charges = (on as unknown as { charges: Rec[] }).charges;
  assertEquals(charges[0].cardTask, "accept");
  assertEquals(await outcomeDigest(on), NOIOU_SWEET_PRODUCTION_ON);

  // 只開不記帳不承諾（甜話短回沒開）：一樣沒有推進；甜話短回沒開，每張照舊先回甜話、順帶腳底痛。
  const onlyOff = await run(PRODUCTION, sweetScenario(PRODUCTION));
  const only = await run(NO_IOU(PRODUCTION), sweetScenario(NO_IOU(PRODUCTION)));
  assertEquals(await outcomeDigest(onlyOff), SWEET_PRODUCTION_OFF);
  assertNoIouRequests(only, onlyOff, PRODUCTION);
  assertEquals(traceOf(only).push, null);
  const onlyLines = specLinesOf(only.requests.write.user);
  assertEquals(onlyLines.length, 5);
  for (const line of onlyLines) {
    assert(
      line.includes("任務：接住｜這張接：她的「只想要你哄」｜可以順帶："),
      line,
    );
  }
  assertEquals(await outcomeDigest(only), NOIOU_PRODUCTION_ON);
});

Deno.test("不記帳不承諾、甜話短回都開、她只傳那句甜話：3 張都接住、都短回、沒有推進（甜話短回單開時第 1 張是推進（種子））；鎖住", async () => {
  const sweetOn = ON(PRODUCTION);
  const off = await run(sweetOn, sweetOnlyScenario(sweetOn));
  const on = await run(NO_IOU(sweetOn), sweetOnlyScenario(NO_IOU(sweetOn)));
  assertEquals(await outcomeDigest(off), SWEET_ONLY_PRODUCTION_ON);
  assertNoIouRequests(on, off, sweetOn);
  assertEquals(plannedTasks(off), ["push", "accept", "accept"]);
  assertEquals(plannedTasks(on), ["accept", "accept", "accept"]);
  const lines = specLinesOf(on.requests.write.user);
  assertEquals(lines.length, 3);
  for (const line of lines) {
    assert(
      line.includes(
        `任務：接住｜這張接：她的「只想要你哄」｜${SWEET_SHORT_CARD_PART}｜`,
      ),
      line,
    );
  }
  assertEquals(
    (traceOf(on).specs as Rec[]).every((s) => s.sweetShort === true),
    true,
  );
  assertEquals(await outcomeDigest(on), NOIOU_SWEET_ONLY_PRODUCTION_ON);
});

Deno.test("全開（正式九個開關＋甜話短回）再開不記帳不承諾、交往喊累情境（她開心地喊累、沒撒嬌）：讀局面標 herTired、沒有推進（種子）、4 張都接住；沒開時第 1 張是推進（種子）；都鎖住", async () => {
  const off = await run(ALL_SWEET, tiredScenario(ALL_SWEET));
  const on = await run(NO_IOU(ALL_SWEET), tiredScenario(NO_IOU(ALL_SWEET)));
  assertNoIouRequests(on, off, ALL_SWEET);
  const onTags = traceOf(on).tags as Rec;
  assertEquals([onTags.herTired, onTags.herAffection], [true, false]);
  assertEquals("herTired" in (traceOf(off).tags as Rec), false);
  assertEquals(traceOf(off).push, "種子");
  assertEquals(traceOf(on).push, null);
  assertEquals(plannedTasks(off), ["push", "accept", "accept", "accept"]);
  assertEquals(plannedTasks(on), ["accept", "accept", "accept", "accept"]);
  assertEquals(on.requests.write.user.includes("推進"), false);
  assertEquals(
    (traceOf(on).specs as Rec[]).some((s) => s.sweetShort === true),
    false,
  );
  assertEquals(await outcomeDigest(off), TIRED_ALL_OFF);
  assertEquals(await outcomeDigest(on), TIRED_ALL_ON);
});

Deno.test("不記帳不承諾開：判讀照抄 herTired 那一行就不給、記 log（沒開照給）", async () => {
  const combo = NO_IOU(PRODUCTION);
  // 判讀照抄 herTired 那一行：開著不給、記 log；沒開照給。
  const leakyJudgment = (c: Combo) =>
    JSON.stringify({
      ...JSON.parse(flagMatrixTiredReadText(c)),
      readForUser: `她跑了四家客戶。${NO_IOU_READ_SENTINELS[0]}`,
    });
  const judgmentOf = (o: Outcome) =>
    o.events.find((e) => e.type === "analysis.read")!.judgment;
  const judged = await run(combo, {
    messages: FLAG_MATRIX_TIRED_MESSAGES,
    readText: leakyJudgment(combo),
  });
  assertEquals(judgmentOf(judged), "");
  assert(
    judged.logs.some((l) =>
      l.event === "guide_v3_coach_text_removed" &&
      l.metadata.field === "judgment"
    ),
  );
  const offJudged = await run(PRODUCTION, {
    messages: FLAG_MATRIX_TIRED_MESSAGES,
    readText: leakyJudgment(PRODUCTION),
  });
  assert(String(judgmentOf(offJudged)).includes(NO_IOU_READ_SENTINELS[0]));
});

// ---- 寫卡瘦身（ANALYZE_GUIDE_V3_WRITER_TRIM，Bruce 2026-10-26「看B43-B47感覺可以從寫卡prompt 移除 他們對自然度會有影響」；Eric 2026-10-27「照預設」） ----

/// 正式 11 個開關全開：正式環境九個開關（PRODUCTION_ALL 那六個；v3、上一輪脈絡、對象記憶不在這個情境裡）再開甜話短回與不記帳
/// 不承諾（都比這個先上線）；寫卡瘦身另外用 WRITER_TRIM 開。原本的情境在這組沒開寫卡瘦身時就是 NOT_TRIGGERED_ALL_ON。
const ALL_ELEVEN = NO_IOU(ALL_SWEET);
/// 原本的情境（標到 B44、B22），正式組合與正式 11 個開關全開再開寫卡瘦身的整份結果：鎖住。跟沒開只差寫卡的系統提示詞（A5「讓她也
/// 投入」少一句）與寫卡使用者訊息的條目段（B44 那一行不見）；這兩處換回沒開的就是 f3aa55b8…、47f25612…（下面有比）。
const WRITER_TRIM_PRODUCTION_ON =
  "915ced2dc2d6f4204020f540439f0dcb7d7ab19bec816c8ead477c63ba508a38";
const WRITER_TRIM_ALL_ON =
  "0335ba9340078e2c580c21feb6ec540109c6d0fb08d99fbe1c54628b470df1bb";

const WRITER_TRIM = <C extends Combo>(combo: C) => ({
  ...combo,
  writerTrim: true,
});
/// 寫卡使用者訊息裡一條條目的樣子（「編號（觸發）：寫法」，兩段式的寫法照 twoStageEntryWriting）。
const entryLine = (id: string) => {
  const e = GUIDE_V3_ENTRIES.find((x) => x.id === id)!;
  return `- ${e.id}（${e.trigger}）：${twoStageEntryWriting(e)}`;
};
/// 寫卡看不到的那幾條（B43–B47）在寫卡使用者訊息裡的樣子。
const TRIMMED_ENTRY_LINES = WRITER_TRIM_ENTRY_IDS.map(entryLine);
const ALL_SCENARIOS = [
  () => ({}),
  sweetScenario,
  sweetOnlyScenario,
  a2Scenario,
  tiredScenario,
] as const;
/// 開著（兩段式也開）跟沒開比，只差寫卡那兩處：系統提示詞只少 A5 那一句；使用者訊息只少 B43–B47 那幾行（removed 行，這裡的情境
/// 都還有別的條目或本來就沒有條目，不會變成「（這一輪沒有）」）。比雜湊之前先比結構：把寫卡的請求換回沒開的，整份就跟沒開一模一樣
///（key 的順序不變）。
const assertWriterTrimOnly = async (
  on: Outcome,
  off: Outcome,
  removed: number,
  label: string,
) => {
  assertEquals(
    off.requests.write.system.split(WRITER_TRIM_A5_SENTENCE).length - 1,
    1,
    label,
  );
  assertEquals(
    on.requests.write.system,
    off.requests.write.system.replace(WRITER_TRIM_A5_SENTENCE, ""),
    label,
  );
  const offLines = off.requests.write.user.split("\n");
  assertEquals(
    offLines.filter((l) => TRIMMED_ENTRY_LINES.includes(l)).length,
    removed,
    label,
  );
  assertEquals(
    on.requests.write.user.split("\n"),
    offLines.filter((l) => !TRIMMED_ENTRY_LINES.includes(l)),
    label,
  );
  assertEquals(
    await outcomeDigest({
      ...on,
      requests: { ...on.requests, write: off.requests.write },
    }),
    await outcomeDigest(off),
    label,
  );
};

Deno.test("寫卡瘦身明確關著（false）：每種組合、每個情境的整份結果都跟沒給一模一樣（既有雜湊照舊）", async () => {
  const off = { writerTrim: false };
  const none = () => ({});
  const affection = () => ({ readText: notAffectionate(PRODUCTION) });
  const locked: [Combo, (c: Combo) => Rec, string][] = [
    [OFF, none, MAIN_6EF72AFF_OFF],
    [RELATION_ONLY, none, MAIN_6EF72AFF_RELATION],
    [BOTH, none, BOTH_ON],
    [PRODUCTION, none, BOTH_TYPING_ON],
    [{ ...PRODUCTION, tensionStyle: true }, none, PRODUCTION_TENSION_STYLE_ON],
    [{ ...PRODUCTION, phraseTidy: true }, none, BOTH_TYPING_TIDY_ON],
    [PRODUCTION, affection, PRODUCTION_LIGHT_OFF],
    [
      { ...PRODUCTION, shortPraise: true },
      affection,
      PRODUCTION_SHORT_PRAISE_LIGHT_ON,
    ],
    [PRODUCTION_ALL, none, PRODUCTION_ALL_OFF],
    [ON(PRODUCTION), none, PRODUCTION_ON_NOT_SWEET],
    [ON(PRODUCTION_ALL), none, PRODUCTION_ALL_ON_NOT_SWEET],
    [PRODUCTION, sweetScenario, SWEET_PRODUCTION_OFF],
    [PRODUCTION_ALL, sweetScenario, SWEET_ALL_OFF],
    [ON(PRODUCTION), sweetScenario, SWEET_PRODUCTION_ON],
    [ON(PRODUCTION_ALL), sweetScenario, SWEET_ALL_ON],
    [PRODUCTION, sweetOnlyScenario, SWEET_ONLY_PRODUCTION_OFF],
    [PRODUCTION_ALL, sweetOnlyScenario, SWEET_ONLY_ALL_OFF],
    [ON(PRODUCTION), sweetOnlyScenario, SWEET_ONLY_PRODUCTION_ON],
    [ON(PRODUCTION_ALL), sweetOnlyScenario, SWEET_ONLY_ALL_ON],
    [PRODUCTION, a2Scenario, A2_PRODUCTION_OFF],
    [PRODUCTION_ALL, a2Scenario, A2_ALL_OFF],
    [ON(PRODUCTION), a2Scenario, A2_PRODUCTION_ON],
    [ON(PRODUCTION_ALL), a2Scenario, A2_ALL_ON],
    [NO_IOU(ON(PRODUCTION)), sweetScenario, NOIOU_SWEET_PRODUCTION_ON],
    [NO_IOU(PRODUCTION), sweetScenario, NOIOU_PRODUCTION_ON],
    [
      NO_IOU(ON(PRODUCTION)),
      sweetOnlyScenario,
      NOIOU_SWEET_ONLY_PRODUCTION_ON,
    ],
    [ALL_SWEET, tiredScenario, TIRED_ALL_OFF],
    [NO_IOU(ALL_SWEET), tiredScenario, TIRED_ALL_ON],
    [NO_IOU(PRODUCTION), none, NOT_TRIGGERED_PRODUCTION_ON],
    [ALL_ELEVEN, none, NOT_TRIGGERED_ALL_ON],
  ];
  for (const [combo, scenario, digest] of locked) {
    const withOff = { ...combo, ...off };
    assertEquals(
      await outcomeDigest(await run(withOff, scenario(withOff))),
      digest,
      JSON.stringify(combo),
    );
  }
  assertEquals(
    await outcomeDigest(
      withoutKeys(await run({ ...TWO_STAGE_ONLY, ...off }), [
        "completedAt",
        "cardExplains",
      ]),
    ),
    TWO_STAGE_C8F64DFE,
  );
  // 其他每一種開關組合（含甜話短回、不記帳不承諾）、五個情境：給 false 跟沒給一樣。
  const flags = [
    "typingStyle",
    "shortPraise",
    "tensionStyle",
    "phraseTidy",
    "sweetShort",
    "noIou",
  ] as const;
  for (const base of [OFF, RELATION_ONLY, TWO_STAGE_ONLY, BOTH]) {
    for (let mask = 0; mask < 1 << flags.length; mask++) {
      const combo: Combo = {
        ...base,
        ...Object.fromEntries(
          flags.map((f, i) => [f, (mask & (1 << i)) !== 0]),
        ),
      };
      for (const scenario of ALL_SCENARIOS) {
        assertEquals(
          await outcomeDigest(
            await run({ ...combo, ...off }, scenario({ ...combo, ...off })),
          ),
          await outcomeDigest(await run(combo, scenario(combo))),
          JSON.stringify(combo),
        );
      }
    }
  }
});

Deno.test("寫卡瘦身開、兩段式沒開：整份結果跟沒開一模一樣（只在兩段式開時有作用；舊的一步寫卡照舊看得到 B44），每個情境都一樣", async () => {
  assertEquals(
    await outcomeDigest(await run(WRITER_TRIM(OFF))),
    MAIN_6EF72AFF_OFF,
  );
  assertEquals(
    await outcomeDigest(await run(WRITER_TRIM(RELATION_ONLY))),
    MAIN_6EF72AFF_RELATION,
  );
  assert((await run(WRITER_TRIM(OFF))).requests.write.user.includes("- B44（"));
  for (
    const combo of [
      OFF,
      RELATION_ONLY,
      { ...RELATION_ONLY, typingStyle: true, sweetShort: true, noIou: true },
    ]
  ) {
    for (const scenario of ALL_SCENARIOS) {
      assertEquals(
        await outcomeDigest(
          await run(WRITER_TRIM(combo), scenario(WRITER_TRIM(combo))),
        ),
        await outcomeDigest(await run(combo, scenario(combo))),
        JSON.stringify(combo),
      );
    }
  }
});

Deno.test("寫卡瘦身開、原本的情境（標到 B44、B22），正式組合與正式 11 個開關全開：只差寫卡的系統提示詞那一句與使用者訊息的條目段（B44 那一行不見）；讀局面、說明、卡、扣費、trace 都不變；鎖住", async () => {
  for (
    const [combo, offDigest, onDigest] of [
      [PRODUCTION, BOTH_TYPING_ON, WRITER_TRIM_PRODUCTION_ON],
      [ALL_ELEVEN, NOT_TRIGGERED_ALL_ON, WRITER_TRIM_ALL_ON],
    ] as const
  ) {
    const off = await run(combo);
    const on = await run(WRITER_TRIM(combo));
    assertEquals(await outcomeDigest(off), offDigest);
    // 寫卡的系統提示詞：A5「讓她也投入」少一句（全開時帶張力改寫法也開，一樣只少這一句）。
    assertEquals(
      on.requests.write.system,
      writeSystemPromptTwoStage(undefined, undefined, undefined, {
        tensionStyle: (combo as Combo).tensionStyle === true,
        writerTrim: true,
      }),
    );
    // 寫卡的使用者訊息：條目段原本是 B44、B22，開了只剩 B22。
    const section = (user: string) =>
      user.split("\n\n").find((p) => p.startsWith("## 這一輪的情境做法\n"));
    assertEquals(
      section(off.requests.write.user),
      `## 這一輪的情境做法\n${entryLine("B44")}\n${entryLine("B22")}`,
    );
    assertEquals(
      section(on.requests.write.user),
      `## 這一輪的情境做法\n${entryLine("B22")}`,
    );
    // 讀局面、說明、送出的卡、扣費、trace（條目照舊有 B44）都一樣。
    assertEquals(on.requests.read, off.requests.read);
    assertEquals(on.requests.explain, off.requests.explain);
    const b44 = GUIDE_V3_ENTRIES.find((e) => e.id === "B44")!;
    assert(
      on.requests.explain.user.includes(`- ${b44.trigger}：${b44.writing}`),
    );
    assertEquals(cardsOf(on), cardsOf(off));
    assertEquals(
      (on as unknown as { charges: Rec[] }).charges,
      (off as unknown as { charges: Rec[] }).charges,
    );
    assertEquals(traceOf(on), traceOf(off));
    assertEquals(traceOf(on).entries, ["B44", "B22"]);
    // 比雜湊之前先比結構：寫卡那兩處換回沒開的就是沒開的雜湊。
    await assertWriterTrimOnly(on, off, 1, JSON.stringify(combo));
    assertEquals(await outcomeDigest(on), onDigest);
  }
});

Deno.test("寫卡瘦身開（兩段式開）：每一種開關組合、每個情境都只差寫卡那兩處——系統提示詞少那一句；原本的情境少 B44 那一行，沒標到 B43–B47 的情境使用者訊息一字不差", async () => {
  const flags = [
    "typingStyle",
    "shortPraise",
    "tensionStyle",
    "phraseTidy",
    "sweetShort",
    "noIou",
  ] as const;
  for (const base of [TWO_STAGE_ONLY, BOTH]) {
    for (let mask = 0; mask < 1 << flags.length; mask++) {
      const combo: Combo = {
        ...base,
        ...Object.fromEntries(
          flags.map((f, i) => [f, (mask & (1 << i)) !== 0]),
        ),
      };
      for (const [i, scenario] of ALL_SCENARIOS.entries()) {
        const off = await run(combo, scenario(combo));
        const on = await run(WRITER_TRIM(combo), scenario(WRITER_TRIM(combo)));
        await assertWriterTrimOnly(
          on,
          off,
          i === 0 ? 1 : 0,
          `${JSON.stringify(combo)}/${i}`,
        );
      }
    }
  }
});
