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
  FLAG_MATRIX_T0,
  FLAG_MATRIX_TAGS,
  flagMatrixCards,
  flagMatrixReadText,
  outcomeDigest,
  runFlagMatrix,
  withoutKeys,
} from "./flag_matrix_harness.ts";
import { readSystemPrompt } from "./prompts.ts";
import { READ_TAGS_SCHEMA_TWO_STAGE } from "./read_tags.ts";
import {
  RELATION_FIELD_NOTES,
  RELATION_SENTINELS,
  withRelationFields,
} from "./relation.ts";
import { handleGuideV3Stream } from "./stream_flow.ts";
import { detectTypingHabits, styleCard } from "./typing_style.ts";
import { toTurns } from "./turns.ts";
import {
  READ_TAGS_SCHEMA_TWO_STAGE_WITH_RELATION,
  READ_TWO_STAGE_NOTES,
  readSystemPromptTwoStageWithRelation,
  readUserPromptTwoStage,
  TWO_STAGE_WRITER_SENTINELS,
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
  combo: { twoStage: boolean; relation: boolean; typingStyle?: boolean },
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
