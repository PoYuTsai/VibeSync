// 對話分析 v3 說明書的程式規則、提示詞組裝與卡片解析（從測試工具的原型測試搬來）。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { applyVoice, parseWrittenCards, scoringWords } from "./cards.ts";
import type { GuideV3Entry } from "./entries.ts";
import type { GuideV3SectionId } from "./guide_text.ts";
import {
  cardSpecLine,
  readSystemPrompt,
  WRITE_OUTPUT_FORMAT,
  writeSystemPrompt,
  writeUserPrompt,
} from "./prompts.ts";
import { parseReadTags, READ_TAGS_SCHEMA, type ReadTags } from "./read_tags.ts";
import {
  arrangeCards,
  type CardSpec,
  decidePush,
  decideReply,
  judgmentFor,
  perfunctoryStreak,
  pickEntries,
  SCAM_VENUE_WARNING,
} from "./rules.ts";
import { toTurns, transcriptByTurn } from "./turns.ts";

// 測試用的假段落與條目（不放 Bruce 的原文）：結構照真的，內容是佔位字。
const FAKE_SECTIONS: Readonly<Record<GuideV3SectionId, string>> = {
  A1: "### A1 立場\n\n立場內容。",
  A2: "### A2 價值底線\n\n底線內容。",
  A3: "### A3 輸入怎麼用\n\n輸入內容。",
  A4: "### A4 讀局面（只輸出標記）\n\n讀局面內容。",
  A5: "### A5 寫句子（照每張卡的規格）\n\n寫句子內容。",
  A6: "### A6 送出前快檢\n\n快檢內容。",
};
const entry = (id: string, n: string, enabled = true): GuideV3Entry => ({
  id,
  trigger: `觸發${n}`,
  writing: `寫法${n}`,
  enabled,
});
const FAKE_ENTRIES: readonly GuideV3Entry[] = [
  entry("B01", "一"),
  entry("B02", "二"),
  entry("B11", "十一"),
  entry("B19", "十九", false),
  entry("B40", "四十"),
];
const guide = { sections: FAKE_SECTIONS, entries: FAKE_ENTRIES };

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
    needsHisFacts: false,
    identityQuestion: false,
    hisStatedFacts: [],
    hasHisVoiceSample: false,
    replyWillingness: "high",
    worthyBallCount: 1,
    herTurnsPerfunctory: [],
    matchedEntries: [],
    readForUser: "她願意聊。",
    waitFor: "",
    ...over,
  };
}

const me = (content: string) => ({ isFromMe: true, content });
const her = (content: string) => ({ isFromMe: false, content });

const combo = (c: CardSpec) => `${c.task}|${c.method}|${c.voice}`;

Deno.test("分輪：同一個人連傳併成一輪，標出她最新的一輪", () => {
  const turns = toTurns([me("嗨"), her("哈囉"), her("你好"), me("在幹嘛")]);
  assertEquals(turns.map((t) => [t.index, t.fromMe, t.messages.length]), [
    [1, true, 1],
    [2, false, 2],
    [3, true, 1],
  ]);
  const text = transcriptByTurn(toTurns([me("嗨"), her("哈囉")]));
  assert(text.includes("第 2 輪・她：\n- 哈囉"));
  assert(text.endsWith("（她最新的是第 2 輪）"));
});

Deno.test("C1：他最後一則先別回；封鎖或明確拒絕就停", () => {
  assertEquals(
    decideReply(toTurns([her("嗨"), me("哈囉")]), tags()).kind,
    "hold",
  );
  const turns = toTurns([me("嗨"), her("哈囉")]);
  assertEquals(decideReply(turns, tags({ blocked: true })).kind, "stop");
  assertEquals(
    decideReply(turns, tags({ explicitRejection: true })).kind,
    "stop",
  );
});

Deno.test("C1：連續主動兩次、她兩次都敷衍才先別回；只冷一次照常回", () => {
  const turns = toTurns([
    her("今天去看展超好看"),
    me("真的嗎"),
    her("哈哈"),
    me("那妳週末呢"),
    her("嗯"),
  ]);
  const both = tags({
    herTurnsPerfunctory: [{ turn: 3, perfunctory: true }, {
      turn: 5,
      perfunctory: true,
    }],
  });
  assertEquals(perfunctoryStreak(turns, both), 2);
  assertEquals(decideReply(turns, both).kind, "hold");
  const once = tags({ herTurnsPerfunctory: [{ turn: 5, perfunctory: true }] });
  assertEquals(perfunctoryStreak(turns, once), 1);
  assertEquals(decideReply(turns, once).kind, "send");
});

Deno.test("C1：她婉拒就一句收尾；她取消不是只收尾（交給推進：提一次改天）", () => {
  const turns = toTurns([me("週六去看展？"), her("這週有點忙，下次再看看")]);
  const declined = tags({
    declinedOrBoundary: true,
    inviteReadiness: "婉拒過",
  });
  assertEquals(decideReply(turns, declined).kind, "close");
  const cancelled = tags({
    declinedOrBoundary: true,
    inviteReadiness: "她取消了",
  });
  assertEquals(decideReply(turns, cancelled).kind, "send");
  assertEquals(decidePush(turns, cancelled), "改天");
  assertEquals(
    decidePush(turns, { ...cancelled, cancelHasAlternative: true }),
    "說定",
  );
});

Deno.test("C3：開窗具體邀約；綠燈聊開兩輪以上才種；情緒差、紅燈、婉拒過、猶豫不推進", () => {
  const short = toTurns([me("嗨"), her("哈囉")]);
  const long = toTurns([me("a"), her("b"), me("c"), her("d")]);
  assertEquals(decidePush(short, tags({ herMove: "開窗" })), "具體邀約");
  assertEquals(decidePush(short, tags()), null);
  assertEquals(decidePush(long, tags()), "種子");
  assertEquals(decidePush(long, tags({ light: "yellow" })), null);
  assertEquals(decidePush(long, tags({ herMoodBad: true })), null);
  assertEquals(decidePush(long, tags({ light: "red" })), null);
  assertEquals(decidePush(long, tags({ inviteReadiness: "婉拒過" })), null);
  assertEquals(decidePush(long, tags({ inviteReadiness: "猶豫" })), null);
  assertEquals(decidePush(long, tags({ inviteReadiness: "明確答應" })), "說定");
});

Deno.test("D4 第 1 列：她被主管當眾念、有他的口吻樣本 → 3 張共鳴，照他與預設交錯", () => {
  const t = tags({ herMoodBad: true, hasHisVoiceSample: true });
  const cards = arrangeCards({ kind: "send" }, null, t);
  assertEquals(cards.map(combo), [
    "共鳴|只用反應|照他",
    "共鳴|只用反應|預設",
    "共鳴|只用反應|照他",
  ]);
  assertEquals(cards[2].angle, 1);
});

Deno.test("D4 第 2 列：綠燈、需要他的事但他沒講過 → 4 張，最多一張照樣寫＋標示、至少一張空格", () => {
  const t = tags({ needsHisFacts: true, hasHisVoiceSample: true });
  const cards = arrangeCards({ kind: "send" }, null, t);
  assertEquals(cards.length, 4);
  assertEquals(cards.filter((c) => c.task === "帶張力").length, 2);
  assertEquals(cards.filter((c) => c.method === "照樣寫＋標示").length, 1);
  assertEquals(cards.find((c) => c.method === "照樣寫＋標示")!.task, "帶張力");
  assert(cards.some((c) => c.method === "留空格"));
  // 第一張照自然順序是接住（可以有空格）。
  assertEquals(cards[0].task, "接住");
});

Deno.test("D4 第 3 列：她問他做什麼工作、沒有他的訊息 → 3 張全留空格、預設口吻，同規格換切入點", () => {
  const t = tags({
    herMove: "問他的事",
    identityQuestion: true,
    needsHisFacts: true,
  });
  const cards = arrangeCards({ kind: "send" }, null, t);
  assertEquals(cards.map(combo), [
    "接住|留空格|預設",
    "帶張力|留空格|預設",
    "接住|留空格|預設",
  ]);
  assertEquals(cards[2].angle, 1);
});

Deno.test("D4 第 4 列：她開窗、他說過週末有空 → 5 張，兩張推進、推進卡排第一用他說過的", () => {
  const t = tags({
    herMove: "開窗",
    hisStatedFacts: ["我週末通常有空"],
    hasHisVoiceSample: true,
  });
  const push = decidePush(toTurns([me("a"), her("b")]), t);
  assertEquals(push, "具體邀約");
  const cards = arrangeCards({ kind: "send" }, push, t);
  assertEquals(cards.length, 5);
  assertEquals(cards.filter((c) => c.task === "推進").length, 2);
  assertEquals(cards.filter((c) => c.task === "帶張力").length, 2);
  assertEquals([cards[0].task, cards[0].method], ["推進", "用他說過的"]);
  assertEquals(
    new Set(cards.map(combo)).size + cards.filter((c) => c.angle > 0).length,
    5,
  );
});

Deno.test("紅燈只用接住和收；大笑收尾照 C4 一張收、一張帶張力；收尾決定只有一張收", () => {
  const red = arrangeCards({ kind: "send" }, null, tags({ light: "red" }));
  assert(red.every((c) => c.task === "接住" || c.task === "收"));
  const laugh = arrangeCards(
    { kind: "send" },
    null,
    tags({ herMove: "大笑收尾" }),
  );
  assertEquals(laugh[0].task, "收");
  assertEquals(laugh.filter((c) => c.task === "收").length, 1);
  assertEquals(laugh.filter((c) => c.task === "帶張力").length, 1);
  const close = arrangeCards({ kind: "close", reason: "x" }, null, tags());
  assertEquals(close.map((c) => c.task), ["收"]);
  assertEquals(arrangeCards({ kind: "hold", reason: "x" }, null, tags()), []);
});

Deno.test("每張最多 1 個問句、種子不問；照樣寫＋標示不用在她情緒差和推進", () => {
  const t = tags({ needsHisFacts: true });
  const cards = arrangeCards({ kind: "send" }, "種子", t);
  assertEquals(cards.find((c) => c.task === "推進")!.questionBudget, 0);
  assert(
    cards.filter((c) => c.task !== "推進").every((c) => c.questionBudget === 1),
  );
  assert(
    cards.filter((c) => c.method === "照樣寫＋標示").every((c) =>
      c.task !== "推進"
    ),
  );
  const sad = arrangeCards(
    { kind: "send" },
    null,
    tags({ herMoodBad: true, needsHisFacts: true }),
  );
  assert(sad.every((c) => c.method !== "照樣寫＋標示"));
});

Deno.test("C5 挑條目：只挑啟用的、最多三條，停與拒絕優先，再來她直接問的", () => {
  const picked = pickEntries(
    ["B40", "B02", "B19", "B11", "B01", "B99"],
    guide.entries,
  );
  assertEquals(picked.map((e) => e.id), ["B11", "B02", "B01"]);
});

Deno.test("讀局面的提示詞只帶觸發、不帶寫法，也不帶 A1、A5", () => {
  const prompt = readSystemPrompt(guide.sections, guide.entries);
  assert(prompt.includes("B01：觸發一"));
  assert(!prompt.includes("寫法一"));
  assert(!prompt.includes("B19"));
  assert(prompt.includes("讀局面內容") && prompt.includes("輸入內容"));
  assert(!prompt.includes("立場內容") && !prompt.includes("寫句子內容"));
});

Deno.test("寫句子的提示詞帶 A1、A2、A3、A5、A6 與安全規則；輸出格式沒有中文範例句", () => {
  const prompt = writeSystemPrompt(guide.sections, "安全規則", "外洩指令");
  for (
    const s of [
      "立場內容",
      "底線內容",
      "輸入內容",
      "寫句子內容",
      "快檢內容",
      "安全規則",
      "外洩指令",
    ]
  ) {
    assert(prompt.includes(s), s);
  }
  assert(!prompt.includes("讀局面內容"));
  const quoted = WRITE_OUTPUT_FORMAT.match(/"<[^>]*>"/g) ?? [];
  // 只有佔位符（第 1 則、第 2 則），沒有可以照抄的中文句子。
  assertEquals(quoted.length, 2);
  const user = writeUserPrompt({
    turns: toTurns([me("嗨"), her("哈囉")]),
    tags: tags({ hisStatedFacts: ["我剛下班"] }),
    entries: [guide.entries[1]],
    cards: arrangeCards({ kind: "send" }, null, tags()),
  });
  assert(user.includes("- 我剛下班"));
  assert(user.includes("B02（觸發二）：寫法二"));
  assert(user.includes("1. 任務："));
});

Deno.test("第一段結構化輸出：schema 欄位都必填；檢查擋下錯的值", () => {
  const required = READ_TAGS_SCHEMA.required as string[];
  const props = Object.keys(READ_TAGS_SCHEMA.properties as object);
  assertEquals([...required].sort(), [...props].sort());
  assert(parseReadTags(tags()) !== null);
  assertEquals(parseReadTags({ ...tags(), light: "blue" }), null);
  assertEquals(parseReadTags({ ...tags(), herMoodBad: "yes" }), null);
  assertEquals(parseReadTags({ ...tags(), worthyBallCount: -1 }), null);
  assertEquals(parseReadTags(null), null);
});

Deno.test("第二段輸出：一行一張、壞行略過並計數、依卡號排序", () => {
  const { cards, invalidLines } = parseWrittenCards(
    [
      '{"card": 2, "messages": ["第二"], "hasInventedDetail": true, "expectedReaction": "她會笑"}',
      "不是 JSON",
      '{"card": 1, "messages": ["一", "二"], "hasInventedDetail": false, "expectedReaction": ""}',
      '{"card": 3, "messages": []}',
    ].join("\n"),
  );
  assertEquals(cards.map((c) => c.card), [1, 2]);
  assertEquals(cards[1].hasInventedDetail, true);
  assertEquals(invalidLines, 2);
});

Deno.test("預設口吻的卡由程式把妳換成你，照他的卡不動，原文另存", () => {
  const card = {
    card: 1,
    messages: ["妳好", "我們"],
    hasInventedDetail: false,
    expectedReaction: "",
  };
  const spec = (voice: "照他" | "預設"): CardSpec => ({
    task: "接住",
    method: "只用反應",
    voice,
    questionBudget: 1,
    push: null,
    angle: 0,
  });
  const fixed = applyVoice(card, spec("預設"));
  assertEquals(fixed.messages, ["你好", "我們"]);
  assertEquals(fixed.rawMessages, ["妳好", "我們"]);
  assertEquals(applyVoice(card, spec("照他")).messages, ["妳好", "我們"]);
});

Deno.test("v3.2：留空格的卡可以編別的細節但要標示，身分資料仍只能留空格；輸出格式不要「她大概會」", () => {
  const line = cardSpecLine({
    task: "接住",
    method: "留空格",
    voice: "預設",
    questionBudget: 1,
    push: null,
    angle: 0,
  }, 1);
  assert(!line.includes("空格以外不寫他的事"));
  assert(line.includes("空格以外編出來的細節要標示"));
  assert(line.includes("工作、年紀、身高、感情狀態、住哪只能留空格"));
  assert(
    WRITE_OUTPUT_FORMAT.includes(
      "「照樣寫＋標示」和「留空格」的卡可以寫他的經歷或狀態",
    ),
  );
  assert(!WRITE_OUTPUT_FORMAT.includes("expectedReaction"));
});

Deno.test("v3.2 C5：打分或考題字眼只記錄；照他口吻的「妳」也算", () => {
  assertEquals(scoringWords("OK 加分，不過住宿應該有先訂吧"), ["加分"]);
  assertEquals(scoringWords("給妳一次機會重答"), ["重答", "給你一次機會"]);
  assertEquals(scoringWords("有啊，願意踩雷這點我很欣賞"), []);
});

Deno.test("v3.2：B44、B45（她直接問他）排在一般條目前面", () => {
  const e = (id: string) => ({ id, trigger: "t", writing: "w", enabled: true });
  const entries = ["B01", "B43", "B44", "B45", "B46"].map(e);
  assertEquals(
    pickEntries(["B46", "B43", "B45", "B44"], entries).map((x) => x.id),
    ["B44", "B45", "B43"],
  );
});

Deno.test("v3.3：標到 B43–B46 時帶張力改排接住；沒標到照原樣", () => {
  const cut = arrangeCards(
    { kind: "send" },
    null,
    tags({ worthyBallCount: 2, matchedEntries: ["B44"] }),
  );
  assert(cut.length >= 4);
  assert(cut.every((c) => c.task !== "帶張力"));
  const other = arrangeCards(
    { kind: "send" },
    null,
    tags({ worthyBallCount: 2, matchedEntries: ["B21"] }),
  );
  assert(other.some((c) => c.task === "帶張力"));
});

Deno.test("v3.3：標到 B46 不排推進（就算綠燈、聊開了也不種子）", () => {
  const turns = toTurns([me("a"), her("b"), me("c"), her("d")]);
  assertEquals(decidePush(turns, tags()), "種子");
  assertEquals(decidePush(turns, tags({ matchedEntries: ["B46"] })), null);
});

Deno.test("v3.3：她直接問他時第一張排接住、推進放後面；沒直接問照原樣推進在前", () => {
  const asks = arrangeCards(
    { kind: "send" },
    "具體邀約",
    tags({ herMove: "問他的事", hisStatedFacts: ["週末常爬山"] }),
  );
  assertEquals(asks[0].task, "接住");
  assertEquals(asks[1].task, "推進");
  const viaEntry = arrangeCards(
    { kind: "send" },
    "具體邀約",
    tags({ herMove: "試探", matchedEntries: ["B44"] }),
  );
  assertEquals(viaEntry[0].task, "接住");
  assert(viaEntry.some((c) => c.task === "推進"));
  const plain = arrangeCards({ kind: "send" }, "具體邀約", tags());
  assertEquals(plain[0].task, "推進");
});

Deno.test("v3.3：B47 只出換地方的推進和先不約的收，判斷由程式附上酒托提醒", () => {
  const t = tags({
    matchedEntries: ["B47"],
    risk: true,
    readForUser: "她堅持去那家。",
  });
  const turns = toTurns([
    her("就約那家酒吧"),
    me("換一家咖啡店？"),
    her("不要，就那家"),
  ]);
  const push = decidePush(turns, t);
  assertEquals(push, "換地方");
  const cards = arrangeCards({ kind: "send" }, push, t);
  assertEquals(cards.map((c) => c.task), ["推進", "收", "推進"]);
  assertEquals(cards[2].angle, cards[0].method === cards[2].method ? 1 : 0);
  assert(cardSpecLine(cards[0], 1).includes("不答應去那家"));
  // Bruce 10/16：換地方的卡只約別的地方，之後也不答應去她那家。
  assert(cardSpecLine(cards[0], 1).includes("也不答應之後再去那家"));
  assertEquals(judgmentFor(t), SCAM_VENUE_WARNING);
  assert(SCAM_VENUE_WARNING.includes("酒托或飯托"));
  // 讀局面把「她不肯換地方」也標成婉拒時，B47 仍照常出卡，不只回一張收尾。
  assertEquals(
    decideReply(turns, { ...t, declinedOrBoundary: true }).kind,
    "send",
  );
  assertEquals(
    decideReply(turns, { ...t, explicitRejection: true }).kind,
    "stop",
  );
  assertEquals(judgmentFor(tags({ readForUser: "一般。" })), "一般。");
  const e = (id: string) => ({ id, trigger: "t", writing: "w", enabled: true });
  assertEquals(
    pickEntries(["B21", "B04", "B47"], ["B04", "B21", "B47"].map(e)).map((x) =>
      x.id
    )[0],
    "B47",
  );
});

Deno.test("規則先後：B47 蓋過 B46、她直接問他、B43–B46；拒絕、他最後一則、自傷在 B47 之前", () => {
  const b47Turns = toTurns([
    her("就約那家酒吧"),
    me("換一家咖啡店？"),
    her("不要，就那家，你要來嗎"),
  ]);
  // 她直接問他（「你要來嗎」）＋B47：不排接住，照樣換地方、收、推進。
  for (
    const extra of [
      { herMove: "問他的事" as const },
      { matchedEntries: ["B47", "B46"] },
      { matchedEntries: ["B47", "B43", "B44"] },
    ]
  ) {
    const t = tags({ matchedEntries: ["B47"], ...extra });
    const push = decidePush(b47Turns, t);
    assertEquals(push, "換地方", JSON.stringify(extra));
    assertEquals(
      arrangeCards(decideReply(b47Turns, t), push, t).map((c) => c.task),
      ["推進", "收", "推進"],
      JSON.stringify(extra),
    );
  }
  // 拒絕、封鎖、他是最後一則都在 B47 之前。
  assertEquals(
    decideReply(b47Turns, tags({ matchedEntries: ["B47"], blocked: true }))
      .kind,
    "stop",
  );
  const hisLast = toTurns([her("就約那家"), me("那家我不去")]);
  assertEquals(
    decideReply(hisLast, tags({ matchedEntries: ["B47"] })).kind,
    "hold",
  );
});

Deno.test("規則先後：B46 蓋過「她給了機會至少一張推進」；B43–B46 蓋過「綠燈至少一張帶張力」", () => {
  const turns = toTurns([me("a"), her("b"), me("c"), her("週末要不要見面")]);
  // 她自己提見面本來排具體邀約；標到 B46 就不排推進。
  assertEquals(
    decidePush(turns, tags({ inviteReadiness: "她自己提見面" })),
    "具體邀約",
  );
  const b46 = tags({
    inviteReadiness: "她自己提見面",
    matchedEntries: ["B46"],
  });
  assertEquals(decidePush(turns, b46), null);
  assert(
    arrangeCards({ kind: "send" }, null, b46).every((c) => c.task !== "推進"),
  );
  // 綠燈、好幾顆球本來至少一張帶張力；B43–B46 任一條都改排接住。
  for (const id of ["B43", "B44", "B45", "B46"]) {
    const cards = arrangeCards(
      { kind: "send" },
      null,
      tags({ worthyBallCount: 2, matchedEntries: [id] }),
    );
    assert(cards.every((c) => c.task !== "帶張力"), id);
  }
});
