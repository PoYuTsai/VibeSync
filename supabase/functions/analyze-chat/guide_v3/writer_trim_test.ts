// 寫卡瘦身（開關 ANALYZE_GUIDE_V3_WRITER_TRIM，Bruce 2026-10-26「看B43-B47感覺可以從寫卡prompt 移除 他們對自然度會有影響」；
// Eric 2026-10-27「照預設」）的純函式：寫卡拿到的條目先排除 B43、B45、B46、B47 再挑（rules.ts pickWriterEntries、plan.ts
// writerEntries）；B44 留給寫卡（Bruce 2026-10-27 盲選：B44 舊版 4 比 1；Eric 同日「照預設」），只標到 B44 時寫卡的使用者訊息跟沒開
// 一字不差。說明步驟與 trace 用的 entries 不變；B43–B47 的程式保護（B43–B46 不排帶張力、B46 不推進、B44／B45 第一張接住、B47 的
// 酒托提醒與三張固定排法）開不開都一樣；標到 B47 時收卡的任務字換成固定說明；寫卡的系統提示詞 A5「讓她也投入」少一句
//（two_stage_prompts.ts WRITER_TRIM_A5_EDITS），說明書原文那一句改了就丟錯。沒開時一律跟今天一樣。對話全部新寫。
import {
  assert,
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { explainSystemPrompt } from "./explain.ts";
import { finalizeCard } from "./finalize.ts";
import { GUIDE_V3_ENTRIES, type GuideV3Entry } from "./entries.ts";
import { GUIDE_V3_SECTIONS } from "./guide_text.ts";
import { type GuideV3Plan, planTurn } from "./plan.ts";
import { cardTaskText } from "./prompts.ts";
import type { ReadTags, TwoStageTags, WorthyLine } from "./read_tags.ts";
import {
  type CardSpec,
  pickEntries,
  pickWriterEntries,
  SCAM_VENUE_WARNING,
  WRITER_TRIM_ENTRY_IDS,
} from "./rules.ts";
import { NO_SAFETY_HITS } from "./safety.ts";
import { toTurns, type Turn } from "./turns.ts";
import {
  cardSpecLineTwoStage,
  TWO_STAGE_WRITER_SENTINELS,
  twoStageEntryWriting,
  twoStageWriterSections,
  WRITER_TRIM_A5_EDITS,
  WRITER_TRIM_A5_SENTENCE,
  WRITER_TRIM_VENUE_CLOSE_SENTINELS,
  WRITER_TRIM_VENUE_CLOSE_TASK,
  writeSystemPromptTwoStage,
  writeUserPromptTwoStage,
} from "./two_stage_prompts.ts";

function tags(over: Partial<ReadTags> = {}): ReadTags {
  return {
    light: "green",
    herMove: "生活",
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
    hasHisVoiceSample: true,
    replyWillingness: "high",
    worthyBallCount: 1,
    herTurnsPerfunctory: [],
    matchedEntries: [],
    readForUser: "她願意聊，也在講自己。",
    waitFor: "",
    ...over,
  };
}

const w = (
  line: number,
  kind: WorthyLine["kind"],
  label = "x",
): WorthyLine => ({ line, label, kind });

/// 讀局面的兩段式欄位（寫卡瘦身只在兩段式開時有作用）：預設還沒交往、她沒撒嬌、沒分享開心的事。
function extras(over: Partial<TwoStageTags> = {}): TwoStageTags {
  return {
    establishedCouple: false,
    herAffection: false,
    herHappyShare: false,
    worthyLines: [w(1, "其他")],
    ...over,
  };
}

/// 他傳過兩則、她回過一則，她最新這一輪是 latest（綠燈：沒標條目時排種子、一張帶張力）。
function chat(latest: readonly string[]): Turn[] {
  return toTurns([
    { isFromMe: true, content: "週末都在做什麼" },
    { isFromMe: false, content: "看心情 常常宅在家" },
    { isFromMe: true, content: "聽起來是安靜派" },
    ...latest.map((content) => ({ isFromMe: false, content })),
  ]);
}

/// 第一次約：她指定一間酒吧，他提議換地方，她還是不肯。
const VENUE = toTurns([
  { isFromMe: true, content: "這週六有空見個面嗎" },
  { isFromMe: false, content: "好啊 去東區那間威士忌吧" },
  { isFromMe: true, content: "換間咖啡廳如何" },
  { isFromMe: false, content: "不要啦 就那間 我姊妹都說讚" },
]);

const ON = { writerTrim: true } as const;
const plan = (
  turns: readonly Turn[],
  t: ReadTags,
  two: TwoStageTags | undefined = extras(),
  options: {
    writerTrim?: boolean;
    noIou?: boolean;
    sweetShort?: boolean;
    lightShortPraise?: boolean;
  } = ON,
) => planTurn(turns, t, NO_SAFETY_HITS, undefined, two, options);
const ids = (entries: readonly GuideV3Entry[]) => entries.map((e) => e.id);
const tasksOf = (specs: readonly CardSpec[]) => specs.map((s) => s.task);
/// 開時計畫只多 writerEntries：拿掉這一欄就跟沒開一模一樣（決定、推進、規格、判讀、條目、訊號、誇法）。
const withoutWriterEntries = (p: GuideV3Plan) => {
  const { writerEntries: _writerEntries, ...rest } = p;
  return rest;
};
const entryOf = (id: string) => GUIDE_V3_ENTRIES.find((e) => e.id === id)!;
/// 寫卡使用者訊息裡那一條的樣子（prompts.ts writeUserPrompt：「編號（觸發）：寫法」）。
const entryLine = (id: string) =>
  `- ${id}（${entryOf(id).trigger}）：${twoStageEntryWriting(entryOf(id))}`;
/// 照正式流程組寫卡的使用者訊息：開著時用 writerEntries，沒有就用 entries（stream_flow.ts）。
const writerUser = (turns: readonly Turn[], t: ReadTags, p: GuideV3Plan) =>
  writeUserPromptTwoStage({
    turns,
    tags: t,
    entries: p.writerEntries ?? p.entries,
    cards: p.specs,
    praise: p.praise,
  });
const SENTENCE = WRITER_TRIM_A5_SENTENCE;

// ── 寫卡拿到的條目 ─────────────────────────────────────────────────────────

Deno.test("pickWriterEntries：只排除 B43、B45、B46、B47 這四條（全部 47 條逐條試過；B44 留給寫卡），其他條目跟 pickEntries 一模一樣；沒標到這四條時整份一樣", () => {
  assertEquals([...WRITER_TRIM_ENTRY_IDS], ["B43", "B45", "B46", "B47"]);
  assertEquals(GUIDE_V3_ENTRIES.length, 47);
  for (const e of GUIDE_V3_ENTRIES) {
    assertEquals(
      pickWriterEntries([e.id], GUIDE_V3_ENTRIES),
      WRITER_TRIM_ENTRY_IDS.includes(e.id)
        ? []
        : pickEntries([e.id], GUIDE_V3_ENTRIES),
      e.id,
    );
  }
  // B44 留給寫卡（Bruce 2026-10-27 盲選：B44 舊版 4 比 1；Eric 同日「照預設」）。
  assertEquals(ids(pickWriterEntries(["B44"], GUIDE_V3_ENTRIES)), ["B44"]);
  for (
    const matched of [
      [],
      ["B22"],
      ["B02", "B11", "B22", "B40"],
      ["B21", "B31", "B40", "B01"],
      [" B22 ", "B22", "B99"],
      ["B44", "B22"],
      ["B44", "B21", "B31", "B40"],
    ]
  ) {
    assertEquals(
      pickWriterEntries(matched, GUIDE_V3_ENTRIES),
      pickEntries(matched, GUIDE_V3_ENTRIES),
      JSON.stringify(matched),
    );
  }
});

Deno.test("pickWriterEntries：先排除再挑，空出來的名額由其他標到的條目補上（照 pickEntries 的先後、最多三條）；B44 照樣佔名額；全是這四條時是空的", () => {
  // B45（她直接問他）排在一般條目前面，原本佔掉一個名額；排除之後 B40 補上。
  const asked = ["B45", "B21", "B31", "B40"];
  assertEquals(ids(pickEntries(asked, GUIDE_V3_ENTRIES)), [
    "B45",
    "B21",
    "B31",
  ]);
  assertEquals(ids(pickWriterEntries(asked, GUIDE_V3_ENTRIES)), [
    "B21",
    "B31",
    "B40",
  ]);
  // B44 跟 B45 同一組（她直接問他）：B44 照留、照樣排在一般條目前面；B45 排除，空出來的名額由 B40 補上。
  const both = ["B44", "B45", "B21", "B40"];
  assertEquals(ids(pickEntries(both, GUIDE_V3_ENTRIES)), [
    "B44",
    "B45",
    "B21",
  ]);
  assertEquals(ids(pickWriterEntries(both, GUIDE_V3_ENTRIES)), [
    "B44",
    "B21",
    "B40",
  ]);
  // B47 在最前面那一組（停、拒絕、安全），B43 在一般那一組：兩條都排除，剩下的照原本的先後。
  const venue = ["B40", "B47", "B11", "B43"];
  assertEquals(ids(pickEntries(venue, GUIDE_V3_ENTRIES)), [
    "B11",
    "B47",
    "B40",
  ]);
  assertEquals(ids(pickWriterEntries(venue, GUIDE_V3_ENTRIES)), ["B11", "B40"]);
  // 四條全標、前後有空白也認得：寫卡一條都沒有；B43–B47 全標時只剩 B44。
  assertEquals(
    pickWriterEntries(["B43", "B45", "B46", "B47"], GUIDE_V3_ENTRIES),
    [],
  );
  assertEquals(pickWriterEntries([" B45 ", "B47"], GUIDE_V3_ENTRIES), []);
  assertEquals(
    ids(
      pickWriterEntries(["B43", "B44", "B45", "B46", "B47"], GUIDE_V3_ENTRIES),
    ),
    ["B44"],
  );
  // 停用的條目照舊不挑（假條目，不放原文）。
  const fake = (id: string, enabled: boolean): GuideV3Entry => ({
    id,
    trigger: `觸發${id}`,
    writing: `寫法${id}`,
    enabled,
  });
  const fakes = [fake("B22", false), fake("B40", true), fake("B45", true)];
  assertEquals(ids(pickWriterEntries(["B22", "B40", "B45"], fakes)), ["B40"]);
});

// ── 計畫 ───────────────────────────────────────────────────────────────────

Deno.test("planTurn：開時出卡、收尾的計畫多 writerEntries（排除 B43、B45、B46、B47；B44 照留），entries 與其他欄位都不變；沒開（沒給或 false）一個 key 都不多", () => {
  const turns = chat(["那你喜歡什麼樣的女生", "我還拍了一堆照片"]);
  const t = tags({ matchedEntries: ["B45", "B22"], worthyBallCount: 2 });
  const two = extras({ worthyLines: [w(1, "問他"), w(2, "其他")] });
  const off = plan(turns, t, two, {});
  assertEquals("writerEntries" in off, false);
  const offFalse = plan(turns, t, two, { writerTrim: false });
  assertEquals("writerEntries" in offFalse, false);
  assertEquals(offFalse, off);
  const on = plan(turns, t, two);
  assertEquals(on.decision, "send");
  assertEquals(ids(on.entries), ["B45", "B22"]);
  assertEquals(ids(on.writerEntries!), ["B22"]);
  assertEquals(withoutWriterEntries(on), off);
  // B44 留給寫卡：寫卡用的那一份跟 entries 一樣。
  const asked = chat(["所以我這樣算加分嗎😏", "我還拍了一堆照片"]);
  const t44 = tags({ matchedEntries: ["B44", "B22"], worthyBallCount: 2 });
  const on44 = plan(asked, t44, two);
  assertEquals(ids(on44.entries), ["B44", "B22"]);
  assertEquals(on44.writerEntries, on44.entries);
  assertEquals(withoutWriterEntries(on44), plan(asked, t44, two, {}));
  // 收尾（她婉拒）也一樣多這一欄。
  const declined = tags({
    declinedOrBoundary: true,
    matchedEntries: ["B09", "B46"],
  });
  const closeOff = plan(turns, declined, two, {});
  const closeOn = plan(turns, declined, two);
  assertEquals(closeOn.decision, "close");
  assertEquals(ids(closeOn.entries), ["B09", "B46"]);
  assertEquals(ids(closeOn.writerEntries!), ["B09"]);
  assertEquals(withoutWriterEntries(closeOn), closeOff);
  // 跟其他開關各自獨立：短版稱讚、甜話短回、不記帳不承諾一起開，也只多這一欄。
  const others = { lightShortPraise: true, sweetShort: true, noIou: true };
  assertEquals(
    withoutWriterEntries(plan(turns, t, two, { ...others, writerTrim: true })),
    plan(turns, t, two, others),
  );
});

Deno.test("planTurn：先別回、停、自傷、未成年、他連續主動兩次她都敷衍，開著也不加 writerEntries，跟沒開一模一樣", () => {
  const two = extras();
  const hisLast = toTurns([
    { isFromMe: false, content: "那你喜歡什麼樣的女生" },
    { isFromMe: true, content: "等等跟你說" },
  ]);
  const herLast = chat(["那你喜歡什麼樣的女生"]);
  const perfunctory = toTurns([
    { isFromMe: true, content: "在幹嘛" },
    { isFromMe: false, content: "嗯" },
    { isFromMe: true, content: "今天好冷" },
    { isFromMe: false, content: "哈哈" },
  ]);
  const cases: [string, readonly Turn[], ReadTags][] = [
    ["他是最後一則", hisLast, tags({ matchedEntries: ["B45", "B22"] })],
    ["封鎖", herLast, tags({ blocked: true, matchedEntries: ["B45", "B22"] })],
    [
      "明確拒絕",
      herLast,
      tags({ explicitRejection: true, matchedEntries: ["B45", "B11"] }),
    ],
    [
      "自傷",
      herLast,
      tags({ selfHarmSignal: true, matchedEntries: ["B45", "B22"] }),
    ],
    [
      "未成年",
      herLast,
      tags({ minorSignal: true, matchedEntries: ["B45", "B22"] }),
    ],
    [
      "他連續主動兩次、她都只回敷衍的字",
      perfunctory,
      tags({
        matchedEntries: ["B07", "B44"],
        herTurnsPerfunctory: [
          { turn: 2, perfunctory: true },
          { turn: 4, perfunctory: true },
        ],
      }),
    ],
  ];
  for (const [name, turns, t] of cases) {
    const on = plan(turns, t, two);
    assert(["hold", "stop", "care"].includes(on.decision), name);
    assertEquals("writerEntries" in on, false, name);
    assertEquals(on, plan(turns, t, two, {}), name);
  }
});

// ── B43–B47 的程式保護：開關開不開都一樣 ─────────────────────────────────────

/// 開時跟沒開比：決定、推進、規格（任務）、判讀與條目都一樣，只多 writerEntries，而且裡面沒有這一條；寫卡的使用者訊息只少那一條，
/// 規格一字不差。回沒開的計畫。
function assertSameExceptWriter(
  turns: readonly Turn[],
  t: ReadTags,
  two: TwoStageTags,
  id: string,
): GuideV3Plan {
  const off = plan(turns, t, two, {});
  const on = plan(turns, t, two);
  assertEquals(withoutWriterEntries(on), off, id);
  assertEquals(on.decision, off.decision, id);
  assertEquals(on.push, off.push, id);
  assertEquals(on.specs, off.specs, id);
  assertEquals(on.judgment, off.judgment, id);
  assertEquals(ids(on.entries), [id], id);
  assertEquals(on.writerEntries, [], id);
  const offUser = writerUser(turns, t, off);
  const onUser = writerUser(turns, t, on);
  assert(offUser.includes(`## 這一輪的情境做法\n${entryLine(id)}`), id);
  assert(onUser.includes("## 這一輪的情境做法\n（這一輪沒有）"), id);
  assertEquals(
    onUser,
    offUser.replace(entryLine(id), "（這一輪沒有）"),
    id,
  );
  return off;
}

Deno.test("B43（她解釋自己、秀自己會什麼）：開不開都一樣——沒有帶張力（沒標到時有一張）；寫卡看不到 B43", () => {
  const turns = chat(["我才不安靜好嗎", "上個月還跑去學衝浪"]);
  const two = extras({ worthyLines: [w(1, "其他"), w(2, "其他")] });
  const base = { worthyBallCount: 2 };
  const plain = plan(turns, tags(base), two, {});
  assertEquals(tasksOf(plain.specs), [
    "推進",
    "接住",
    "帶張力",
    "接住",
    "接住",
  ]);
  const off = assertSameExceptWriter(
    turns,
    tags({ ...base, matchedEntries: ["B43"] }),
    two,
    "B43",
  );
  assertEquals(tasksOf(off.specs), ["推進", "接住", "接住", "接住", "接住"]);
  assertEquals(off.push, "種子");
});

Deno.test("B44（她討他的看法）：開不開都一樣——第一張排接住（她直接問他）、沒有帶張力；寫卡照樣看得到 B44（Bruce 2026-10-27 盲選留下），寫卡的使用者訊息跟沒開一字不差、系統提示詞只少 A5 那一句", () => {
  const turns = chat(["所以我這樣算加分嗎😏"]);
  const two = extras({ worthyLines: [w(1, "問他")] });
  const plain = plan(turns, tags(), two, {});
  assertEquals(tasksOf(plain.specs), ["推進", "接住", "帶張力", "接住"]);
  const t = tags({ matchedEntries: ["B44"] });
  const off = plan(turns, t, two, {});
  const on = plan(turns, t, two);
  assertEquals(withoutWriterEntries(on), off);
  assertEquals(ids(on.entries), ["B44"]);
  assertEquals(ids(on.writerEntries!), ["B44"]);
  assertEquals(tasksOf(off.specs), ["接住", "推進", "接住", "接住"]);
  assertEquals(off.push, "種子");
  const offUser = writerUser(turns, t, off);
  assert(offUser.includes(`## 這一輪的情境做法\n${entryLine("B44")}`));
  assertEquals(writerUser(turns, t, on), offUser);
  // 系統提示詞只少 A5 那一句（帶張力改寫法開不開都一樣）。
  for (const tensionStyle of [false, true]) {
    assertEquals(
      writeSystemPromptTwoStage(undefined, undefined, undefined, {
        tensionStyle,
        writerTrim: true,
      }),
      writeSystemPromptTwoStage(undefined, undefined, undefined, {
        tensionStyle,
      }).replace(SENTENCE, ""),
    );
  }
});

Deno.test("B45（她問他喜歡怎樣的人）：開不開都一樣——第一張排接住、沒有帶張力；寫卡看不到 B45", () => {
  const turns = chat(["那你喜歡什麼樣的女生"]);
  const two = extras({ worthyLines: [w(1, "問他")] });
  const off = assertSameExceptWriter(
    turns,
    tags({ matchedEntries: ["B45"] }),
    two,
    "B45",
  );
  assertEquals(tasksOf(off.specs), ["接住", "推進", "接住", "接住"]);
});

Deno.test("B46（她對自己聊這麼多不好意思）：開不開都一樣——沒有推進、沒有帶張力；寫卡看不到 B46", () => {
  const turns = chat(["奇怪 我平常很少跟剛認識的人聊這麼多"]);
  const two = extras({ worthyLines: [w(1, "情感")] });
  const plain = plan(turns, tags(), two, {});
  assertEquals(plain.push, "種子");
  const off = assertSameExceptWriter(
    turns,
    tags({ matchedEntries: ["B46"] }),
    two,
    "B46",
  );
  assertEquals(off.push, null);
  assertEquals(tasksOf(off.specs), ["接住", "接住", "接住", "接住"]);
});

Deno.test("B47（第一次約她堅持去她指定的店）：開不開都一樣——推進（換地方）、收、推進，判讀是酒托提醒；寫卡看不到 B47，換地方的卡片規格還在", () => {
  const t = tags({
    matchedEntries: ["B47"],
    inviteReadiness: "她自己提見面",
    readForUser: "她堅持要去她指定的那間酒吧。",
  });
  const two = extras({ worthyLines: [w(1, "其他")] });
  const off = assertSameExceptWriter(VENUE, t, two, "B47");
  assertEquals(off.decision, "send");
  assertEquals(off.push, "換地方");
  assertEquals(tasksOf(off.specs), ["推進", "收", "推進"]);
  assertEquals(off.judgment, SCAM_VENUE_WARNING);
  // 讀局面把「她不肯換地方」也標成婉拒時，照樣出這三張（不是一張收尾），開不開都一樣。
  const declined = { ...t, declinedOrBoundary: true };
  assertEquals(
    withoutWriterEntries(plan(VENUE, declined, two)),
    plan(VENUE, declined, two, {}),
  );
  assertEquals(plan(VENUE, declined, two).decision, "send");
  // 寫卡看不到 B47 的觸發與寫法；換地方的規格（prompts.ts PUSH_NOTE.換地方，裡面寫「不答應去那家」）照樣在兩張推進卡上。
  const on = plan(VENUE, t, two);
  const user = writerUser(VENUE, t, on);
  const b47 = entryOf("B47");
  assertEquals(user.includes(b47.trigger), false);
  assertEquals(user.includes(b47.writing), false);
  assertEquals(user.includes("- B47（"), false);
  const venueSpec = cardTaskText(on.specs[0]);
  assert(venueSpec.includes("不答應去那家"));
  assertEquals(user.split(venueSpec).length - 1, 2);
  assert(writerUser(VENUE, t, off).includes(b47.writing));
});

Deno.test("B47 的收卡：寫卡瘦身標到 B47 時（venueClose），收卡的任務字換成固定說明，說法照 PUSH_NOTE.換地方；兩張推進卡照舊；沒給、或不是 B47 的收卡照舊「收」", () => {
  const t = tags({
    matchedEntries: ["B47"],
    inviteReadiness: "她自己提見面",
    readForUser: "她堅持要去她指定的那間酒吧。",
  });
  const on = plan(VENUE, t, extras({ worthyLines: [w(1, "其他")] }));
  assertEquals(tasksOf(on.specs), ["推進", "收", "推進"]);
  const herLatest = ["不要啦 就那間 我姊妹都說讚"];
  const lines = (venueClose?: boolean) =>
    on.specs.map((s, i) =>
      cardSpecLineTwoStage(
        s,
        i + 1,
        herLatest,
        venueClose ? { venueClose } : {},
      )
    );
  const plain = lines();
  const venue = lines(true);
  assert(plain[1].startsWith("2. 任務：收｜"));
  assertEquals(venue[0], plain[0]);
  assertEquals(venue[2], plain[2]);
  assertEquals(
    venue[1],
    plain[1].replace("任務：收｜", `任務：${WRITER_TRIM_VENUE_CLOSE_TASK}｜`),
  );
  // 說法跟兩張推進卡的規格一致：這次先不約、不答應去那家、也不答應之後再去那家。
  const pushNote = cardTaskText(on.specs[0]);
  for (
    const part of [
      "她堅持要去她指定的店：",
      "不答應去那家，也不答應之後再去那家",
    ]
  ) {
    assert(pushNote.includes(part), part);
    assert(WRITER_TRIM_VENUE_CLOSE_TASK.includes(part), part);
  }
  // 照正式流程組寫卡的使用者訊息：只有收卡那一行不同。
  const base = writerUser(VENUE, t, on);
  const withNote = writeUserPromptTwoStage({
    turns: VENUE,
    tags: t,
    entries: on.writerEntries ?? on.entries,
    cards: on.specs,
    praise: on.praise,
    venueClose: true,
  });
  assertEquals(
    withNote,
    base.replace("2. 任務：收｜", `2. 任務：${WRITER_TRIM_VENUE_CLOSE_TASK}｜`),
  );
  // 不是 B47 的收卡（她大笑收尾）：正式流程只在換地方（只有 B47 會排）時給 venueClose（stream_flow.ts），沒給就照舊「收」。
  const laughT = tags({ herMove: "大笑收尾", matchedEntries: [] });
  const laugh = plan(chat(["哈哈哈哈好啦"]), laughT, extras(), ON);
  const close = laugh.specs.find((s) => s.task === "收");
  assert(close);
  assert(
    cardSpecLineTwoStage(close, 1, ["哈哈哈哈好啦"]).startsWith(
      "1. 任務：收｜",
    ),
  );
});

Deno.test("B47 收卡那句的外洩哨兵：照抄自那句、夠長；正常的收尾與改約不會被擋，照抄那句（夾空白也一樣）就拿掉那張", () => {
  assert(WRITER_TRIM_VENUE_CLOSE_SENTINELS.length > 0);
  for (const s of WRITER_TRIM_VENUE_CLOSE_SENTINELS) {
    assert(WRITER_TRIM_VENUE_CLOSE_TASK.includes(s), s);
    assert([...s.replace(/\s+/g, "")].length >= 8, s);
  }
  const sentinels = [
    ...TWO_STAGE_WRITER_SENTINELS,
    ...WRITER_TRIM_VENUE_CLOSE_SENTINELS,
  ];
  const card = (messages: string[]) =>
    finalizeCard(
      { card: 2, messages, hasInventedDetail: false, expectedReaction: "" },
      { voice: "照他" },
      "不要啦 就那間 我姊妹都說讚",
      sentinels,
    );
  for (
    const messages of [
      ["這次先不約了 等你哪天想換個地方再說"],
      ["那這週就先這樣吧"],
      ["改約燒肉吧 週六晚上七點"],
      ["那間就先不去了"],
    ]
  ) {
    assertEquals(card(messages).ok, true, messages.join("／"));
  }
  for (
    const leak of [
      "不答應去那家，也不答應之後再去那家",
      "不答應去那家， 也不答應之後再去那家",
    ]
  ) {
    const out = card(["這次先不約了", leak]);
    assertEquals(out.ok, false, leak);
    assertEquals(!out.ok && out.reason, "prompt_leak");
  }
});

// ── 寫卡的使用者訊息 ───────────────────────────────────────────────────────

Deno.test("寫卡使用者訊息：開時沒有 B43、B45、B46、B47 的觸發與寫法，其他標到的條目照樣在、順序不變；沒開照舊有；B44 開不開都在、整份一字不差", () => {
  const turns = chat(["所以我這樣算加分嗎😏", "我還拍了一堆照片"]);
  const two = extras({ worthyLines: [w(1, "問他"), w(2, "其他")] });
  // B44 留給寫卡（Bruce 2026-10-27 盲選：B44 舊版 4 比 1；Eric 同日「照預設」）。
  const t44 = tags({
    matchedEntries: ["B44", "B22", "B40"],
    worthyBallCount: 2,
  });
  const user44 = writerUser(turns, t44, plan(turns, t44, two));
  assert(user44.includes(`## 這一輪的情境做法\n${entryLine("B44")}\n`));
  assertEquals(user44, writerUser(turns, t44, plan(turns, t44, two, {})));
  for (const id of WRITER_TRIM_ENTRY_IDS) {
    const t = tags({ matchedEntries: [id, "B22", "B40"], worthyBallCount: 2 });
    const off = plan(turns, t, two, {});
    const on = plan(turns, t, two);
    const offUser = writerUser(turns, t, off);
    const onUser = writerUser(turns, t, on);
    const e = entryOf(id);
    assert(offUser.includes(entryLine(id)), id);
    assertEquals(onUser.includes(e.trigger), false, id);
    assertEquals(onUser.includes(twoStageEntryWriting(e)), false, id);
    assertEquals(onUser.includes(`- ${id}（`), false, id);
    for (const other of ["B22", "B40"]) {
      assert(onUser.includes(entryLine(other)), `${id}/${other}`);
    }
    // 只少那一行，其他（對話、他說過的事、稱讚、規格）一字不差。
    assertEquals(
      onUser.split("\n"),
      offUser.split("\n").filter((l) => l !== entryLine(id)),
      id,
    );
  }
});

Deno.test("寫卡使用者訊息：只標到 B43、B45、B46、B47 時情境做法是「（這一輪沒有）」，跟一條都沒標到一樣；多標 B44 時只剩 B44", () => {
  const turns = chat(["我才不安靜好嗎", "那你喜歡什麼樣的女生"]);
  const two = extras({ worthyLines: [w(1, "其他"), w(2, "問他")] });
  const t = tags({ matchedEntries: ["B43", "B45"], worthyBallCount: 2 });
  const on = plan(turns, t, two);
  assertEquals(ids(on.entries), ["B45", "B43"]);
  assertEquals(on.writerEntries, []);
  const user = writerUser(turns, t, on);
  assert(user.includes("## 這一輪的情境做法\n（這一輪沒有）\n"));
  assertEquals(
    user,
    writeUserPromptTwoStage({
      turns,
      tags: t,
      entries: [],
      cards: on.specs,
      praise: on.praise,
    }),
  );
  // 多標 B44（她也討他的看法）：B44 留給寫卡，情境做法只剩 B44 那一條。
  const asked = chat(["我才不安靜好嗎", "所以我這樣算加分嗎😏"]);
  const t44 = tags({ matchedEntries: ["B43", "B44"], worthyBallCount: 2 });
  const on44 = plan(asked, t44, two);
  assertEquals(ids(on44.entries), ["B44", "B43"]);
  assertEquals(ids(on44.writerEntries!), ["B44"]);
  assert(
    writerUser(asked, t44, on44).includes(
      `## 這一輪的情境做法\n${entryLine("B44")}\n\n`,
    ),
  );
});

// ── 寫卡的系統提示詞 ───────────────────────────────────────────────────────

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

Deno.test("寫卡系統提示詞：沒開（沒給或 false）跟今天一字不差（雜湊同 two_stage_prompts_test.ts 的鎖）；說明書原文與說明步驟照舊有那一句", async () => {
  const off = writeSystemPromptTwoStage();
  assertEquals(
    await sha256(
      writeSystemPromptTwoStage(undefined, undefined, undefined, {
        writerTrim: false,
      }),
    ),
    "e016b913452728fd3ee7419d76782d66f993ec7e036ae05a18f924f83802c1a5",
  );
  for (const tensionStyle of [false, true]) {
    assertEquals(
      writeSystemPromptTwoStage(undefined, undefined, undefined, {
        tensionStyle,
        writerTrim: false,
      }),
      writeSystemPromptTwoStage(undefined, undefined, undefined, {
        tensionStyle,
      }),
    );
  }
  assertEquals(
    twoStageWriterSections(undefined, { writerTrim: false }),
    twoStageWriterSections(),
  );
  assertEquals(off.split(SENTENCE).length - 1, 1);
  // 說明書原文一字不改；說明步驟的系統提示詞照舊有這一句（說明照舊用原本那一份）。
  assert(GUIDE_V3_SECTIONS.A5.includes(SENTENCE));
  assertEquals(explainSystemPrompt().split(SENTENCE).length - 1, 1);
});

Deno.test("寫卡系統提示詞：開時只少那一句，補回去就等於沒開；帶張力改寫法開不開都一樣；A5 只有「讓她也投入」那一行變、其他字都在", () => {
  for (const tensionStyle of [false, true]) {
    const off = writeSystemPromptTwoStage(undefined, undefined, undefined, {
      tensionStyle,
    });
    const on = writeSystemPromptTwoStage(undefined, undefined, undefined, {
      tensionStyle,
      writerTrim: true,
    });
    const at = off.indexOf(SENTENCE);
    assert(at > 0);
    assertEquals(on.includes(SENTENCE), false);
    assertEquals(on, off.slice(0, at) + off.slice(at + SENTENCE.length));
    // 補回去就等於沒開。
    assertEquals(on.slice(0, at) + SENTENCE + on.slice(at), off);
  }
  const offA5 = twoStageWriterSections().A5.split("\n");
  const onA5 = twoStageWriterSections(undefined, { writerTrim: true }).A5.split(
    "\n",
  );
  assertEquals(onA5.length, offA5.length);
  const changed = onA5.flatMap((l, i) => l === offA5[i] ? [] : [i]);
  assertEquals(changed.length, 1);
  const line = onA5[changed[0]];
  assert(offA5[changed[0]].startsWith("- 讓她也投入："));
  assertEquals(line, offA5[changed[0]].replace(SENTENCE, ""));
  // 前後照留：邀她參與不是考她、帶回她講過的事、「小挑戰」那一句，接在一起沒有多的字。
  for (
    const kept of [
      "- 讓她也投入：丟一個她會想回應的小觀點或小挑戰；是邀她參與，不是考她。",
      "適時帶回她前面講過的事。「小挑戰」是好玩、她接得住的，不是她要過的關；不對她的能力下負面定論。",
    ]
  ) {
    assert(line.includes(kept), kept);
  }
  assertEquals(
    twoStageWriterSections(undefined, { writerTrim: true }).A6,
    twoStageWriterSections().A6,
  );
  assertEquals(WRITER_TRIM_A5_EDITS.length, 1);
});

Deno.test("寫卡系統提示詞：說明書原文那一句改了、那一行開頭改了、那一句出現兩次，開時直接丟錯（不會悄悄沒拿掉）；沒開照舊組得出來", () => {
  const a5 = GUIDE_V3_SECTIONS.A5;
  const line = a5.split("\n").find((l) => l.startsWith("- 讓她也投入："))!;
  for (
    const changed of [
      a5.replace(SENTENCE, SENTENCE.replace("一定要接住", "要接住")),
      a5.replace(SENTENCE, SENTENCE.replace("下次就不給了", "下次就少給了")),
      a5.replace(line, line.replace("- 讓她也投入：", "- 讓她投入：")),
      a5.replace(SENTENCE, `${SENTENCE}${SENTENCE}`),
    ]
  ) {
    assert(changed !== a5);
    const sections = { ...GUIDE_V3_SECTIONS, A5: changed };
    assertThrows(() => twoStageWriterSections(sections, { writerTrim: true }));
    assertThrows(() =>
      writeSystemPromptTwoStage(sections, undefined, undefined, {
        writerTrim: true,
      })
    );
    twoStageWriterSections(sections);
  }
});
