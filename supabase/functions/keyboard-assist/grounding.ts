import type { NormalizedKeyboardAssistCompilerOutput } from "./normalize.ts";

/// Deliberately absent from the gate below. "改天再約" and "下次帶你去" invent
/// nothing: they point at a future that has not happened, so there is no fact
/// to contradict. Requiring the screenshot to contain the word "下次" before a
/// reply may say it is not a safety property, it is a vocabulary ban — and it
/// is the one that killed three consecutive real screenshots on 2026-07-28,
/// because a batch is exactly three replies and losing one loses all three.
/// A *specific* future is still a fact and stays gated: "下週六" contains 週六,
/// which the weekday pattern picks up.
export const UNGATED_RELATIVE_DATE_TOKENS = [
  "今天",
  "明天",
  "後天",
  "昨天",
  "前天",
  "大前天",
  "大後天",
  "今晚",
  "今早",
  "明早",
  "明晚",
  "今年",
  "明年",
  "去年",
  "本月",
  "這月",
  "下月",
  "上月",
  "這個月",
  "下個月",
  "上個月",
  "本週",
  "這週",
  "下週",
  "上週",
  "本周",
  "這周",
  "下周",
  "上周",
  "週末",
  "周末",
  "下次",
] as const;

/// Gated, unlike the relative dates above: these assert a shared past. A reply
/// opening "還記得上次你說的那家店嗎" when no such exchange is on screen makes the
/// user look like they are talking to someone else.
const HISTORY_REFERENCE_TOKENS = [
  "上次",
  "之前",
  "那次",
  "那天",
  "你說過",
  "你说过",
  "我們聊過",
  "我们聊过",
  "還記得",
  "还记得",
] as const;

const COMMON_PLACE_TOKENS = [
  "台北",
  "新北",
  "桃園",
  "台中",
  "台南",
  "高雄",
  "基隆",
  "新竹",
  "苗栗",
  "彰化",
  "南投",
  "雲林",
  "嘉義",
  "屏東",
  "宜蘭",
  "花蓮",
  "台東",
  "澎湖",
  "金門",
  "馬祖",
  "東京",
  "大阪",
  "京都",
  "首爾",
  "曼谷",
  "巴黎",
  "倫敦",
  "紐約",
] as const;

const COMMON_VENUE_TOKENS = [
  "鼎泰豐",
  "海底撈",
  "星巴克",
  "路易莎",
  "春水堂",
  "瓦城",
  "饗食天堂",
  "王品",
  "西堤",
  "陶板屋",
  "藏壽司",
  "壽司郎",
] as const;

const LATIN_NON_NAME_WORDS = new Set([
  "bye",
  "haha",
  "happy",
  "hello",
  "hey",
  "hi",
  "lol",
  "no",
  "ok",
  "okay",
  "sorry",
  "sure",
  "thank",
  "thanks",
  "yes",
]);

const COMMON_CHINESE_SURNAMES =
  "王李張劉陳楊黃趙吳周徐孫馬朱胡郭何高林羅鄭梁謝宋唐許韓馮鄧曹彭曾蕭田董袁潘于蔣蔡余杜葉程蘇魏呂丁任沈姚盧姜崔鍾譚陸汪范金石廖賈夏韋傅方白鄒孟熊秦邱江尹薛閻段雷侯龍史陶黎賀顧毛郝龔邵萬錢嚴賴覃洪武莫孔";

const NAME_CONTEXT = "(?:問|找|叫|跟|和|約|告訴|聯絡|回覆|傳給|通知)";
const NAME_BOUNDARY =
  "(?=$|[\\s，。！？、；：,.!?]|一起|去|來|說|問|看|聊|吃|喝|會|也|碰面|見面|看看)";
const CHINESE_FULL_NAME_PATTERN = new RegExp(
  `${NAME_CONTEXT}\\s*([${COMMON_CHINESE_SURNAMES}][\\p{Script=Han}]{2})${NAME_BOUNDARY}`,
  "gu",
);
const CHINESE_NICKNAME_PATTERN = new RegExp(
  `${NAME_CONTEXT}\\s*(小[\\p{Script=Han}])${NAME_BOUNDARY}`,
  "gu",
);
const CHINESE_TITLED_NAME_PATTERN = new RegExp(
  `([${COMMON_CHINESE_SURNAMES}][\\p{Script=Han}]{1,2})(?=先生|小姐|老師|醫師|教練)`,
  "gu",
);

const VENUE_SUFFIXES = [
  "高鐵站",
  "捷運站",
  "火車站",
  "咖啡廳",
  "咖啡店",
  "博物館",
  "美術館",
  "電影院",
  "火鍋店",
  "燒肉店",
  "餐廳",
  "夜市",
  "車站",
  "公園",
  "百貨",
  "商場",
  "飯店",
  "旅館",
  "民宿",
  "影城",
  "酒吧",
  "大道",
  "市",
  "縣",
  "區",
  "鄉",
  "鎮",
  "村",
  "路",
  "街",
  "巷",
  "弄",
  "站",
  "店",
] as const;
const VENUE_PATTERN = new RegExp(
  `(?:約在|位於|住在|去|在|到|回|從|逛)([\\p{Script=Han}A-Za-z0-9]{2,18}?(?:${
    VENUE_SUFFIXES.join("|")
  }))`,
  "giu",
);
const GENERIC_VENUE_PATTERN =
  /^(?:這|那|哪|某|一|附近|新開|喜歡|好吃)|(?:這家|那家|哪家|這間|那間|哪間)|^(?:市區|附近)$/u;
const GENERIC_VENUE_CATEGORIES = new Set([
  "店",
  "咖啡廳",
  "咖啡店",
  "餐廳",
  "火鍋店",
  "燒肉店",
  "酒吧",
  "夜市",
  "公園",
  "百貨",
  "商場",
  "飯店",
  "旅館",
  "民宿",
  "博物館",
  "美術館",
  "影城",
  "電影院",
]);

function normalizeFactualText(value: string): string {
  return value.normalize("NFKC").replaceAll("臺", "台").toLocaleLowerCase(
    "zh-TW",
  );
}

function compactFactualText(value: string): string {
  return normalizeFactualText(value).replace(/\s+/gu, "");
}

/// Which rule claimed a token. Fixed vocabulary, never text from the image, so
/// it is safe to put in telemetry — and without it a grounding rejection says
/// only "a candidate was ungrounded", which is not enough to tell an invented
/// price from an over-eager regex.
export const FACTUAL_TOKEN_CLASSES = [
  "date",
  "time",
  "number",
  "link",
  "handle",
  "place",
  "venue",
  "person",
  "history",
] as const;

export type FactualTokenClass = typeof FACTUAL_TOKEN_CLASSES[number];

function addMatches(
  tokens: Map<string, FactualTokenClass>,
  value: string,
  pattern: RegExp,
  tokenClass: FactualTokenClass,
  group = 0,
): void {
  for (const match of value.matchAll(pattern)) {
    const token = match[group];
    if (!token) continue;
    const compact = compactFactualText(token);
    if (!tokens.has(compact)) tokens.set(compact, tokenClass);
  }
}

function factualTokens(value: string): Map<string, FactualTokenClass> {
  const tokens = new Map<string, FactualTokenClass>();
  const add = (token: string, tokenClass: FactualTokenClass) => {
    const compact = compactFactualText(token);
    if (!tokens.has(compact)) tokens.set(compact, tokenClass);
  };
  const normalized = normalizeFactualText(value);

  addMatches(
    tokens,
    normalized,
    /\d{1,4}\s*(?:[./-]|年)\s*\d{1,2}(?:\s*(?:[./-]|月)\s*\d{1,2}\s*(?:日|號)?)?/gu,
    "date",
  );
  addMatches(
    tokens,
    normalized,
    /\d{1,2}\s*月\s*\d{1,2}\s*(?:日|號)?/gu,
    "date",
  );
  addMatches(
    tokens,
    normalized,
    /[一二三四五六七八九十廿卅]{1,4}月[一二三四五六七八九十廿卅]{1,4}(?:日|號)/gu,
    "date",
  );
  addMatches(
    tokens,
    normalized,
    /(?:星期|禮拜|週|周)[一二三四五六日天]/gu,
    "date",
  );
  for (const token of HISTORY_REFERENCE_TOKENS) {
    if (normalized.includes(token)) add(token, "history");
  }

  addMatches(tokens, normalized, /\d{1,2}\s*[:：]\s*\d{2}/gu, "time");
  addMatches(
    tokens,
    normalized,
    /(?:凌晨|早上|上午|中午|下午|傍晚|晚上)\s*(?:\d{1,2}|[一二三四五六七八九十]{1,3})\s*(?:點|時)(?:半|[一二三四五六七八九十\d]{1,3}分)?/gu,
    "time",
  );
  // A bare clock time is as much of an appointment as 下午三點 is. It used to be
  // caught only because every digit was, so it has to be named now that they
  // are not.
  addMatches(
    tokens,
    normalized,
    /\d{1,2}\s*(?:點|時)(?:半|\s*\d{1,2}\s*分)?/gu,
    "time",
  );
  // Refusing every digit cost far more ordinary replies than it caught claims:
  // one candidate writing 那 4 道菜 instead of 那幾道菜 killed all three lines.
  // Money is the part worth keeping — an invented price is a claim the user
  // sends to a real person. A count is not, and dates and times are gated above.
  addMatches(
    tokens,
    normalized,
    /(?:nt\$|\$)\s*\d+(?:[.,]\d+)*|\d+(?:[.,]\d+)*\s*(?:元|塊)/gu,
    "number",
  );
  addMatches(
    tokens,
    normalized,
    /(?:https?:\/\/|www\.)[^\s<>"'，。！？、]+/gu,
    "link",
  );
  addMatches(tokens, normalized, /@[a-z0-9_.-]+/gu, "handle");

  for (const place of COMMON_PLACE_TOKENS) {
    if (normalized.includes(place)) add(place, "place");
  }
  for (const venue of COMMON_VENUE_TOKENS) {
    if (normalized.includes(venue)) add(venue, "venue");
  }

  const originalCase = value.normalize("NFKC");
  for (
    const match of originalCase.matchAll(
      /(?:^|[^\p{L}])([A-Z][a-z]{1,30}(?:[ -][A-Z][a-z]{1,30})?)(?=$|[^\p{L}])/gu,
    )
  ) {
    const token = match[1];
    if (
      token && !LATIN_NON_NAME_WORDS.has(token.toLocaleLowerCase("en-US"))
    ) {
      add(token, "person");
    }
  }

  for (
    const pattern of [
      CHINESE_FULL_NAME_PATTERN,
      CHINESE_NICKNAME_PATTERN,
      CHINESE_TITLED_NAME_PATTERN,
    ]
  ) {
    addMatches(tokens, value, pattern, "person", 1);
  }

  for (const match of value.matchAll(VENUE_PATTERN)) {
    const rawVenue = match[1];
    if (!rawVenue) continue;
    const venue = rawVenue.replace(/^(?:吃|喝|逛|看看|那個|這個)/u, "");
    const compactVenue = compactFactualText(venue);
    if (
      venue.length >= 2 && !GENERIC_VENUE_PATTERN.test(venue) &&
      !GENERIC_VENUE_CATEGORIES.has(compactVenue)
    ) {
      add(compactVenue, "venue");
    }
  }

  return tokens;
}

/// The class of the first token the evidence cannot account for, or null when
/// everything the text asserts is on screen.
export function ungroundedFactualTokenClass(
  generated: string,
  evidence: string,
): FactualTokenClass | null {
  const compactEvidence = compactFactualText(evidence);
  for (const [token, tokenClass] of factualTokens(generated)) {
    if (!compactEvidence.includes(token)) return tokenClass;
  }
  return null;
}

export function hasOnlyGroundedFactualTokens(
  generated: string,
  evidence: string,
): boolean {
  return ungroundedFactualTokenClass(generated, evidence) === null;
}

/// Which part of the compiler output failed grounding. The three fields are not
/// equally dangerous: `cue` and `uncertainty` are commentary we render, while a
/// candidate is text the user is about to send to a real person. Naming the
/// field is what lets the pipeline drop the former and still refuse the latter.
export type KeyboardAssistGroundingFailure =
  | "cue"
  | "uncertainty"
  | "candidate";

export function keyboardAssistCompilerGroundingFailure(
  value: NormalizedKeyboardAssistCompilerOutput,
): KeyboardAssistGroundingFailure | null {
  const allVisibleMessages = value.messages.map((message) => message.text).join(
    "\n",
  );
  if (!hasOnlyGroundedFactualTokens(value.cue, allVisibleMessages)) {
    return "cue";
  }
  if (
    value.uncertainty !== null &&
    !hasOnlyGroundedFactualTokens(value.uncertainty, allVisibleMessages)
  ) {
    return "uncertainty";
  }
  return value.candidates.every((candidate) =>
      isGroundedKeyboardAssistCandidate(candidate, value)
    )
    ? null
    : "candidate";
}

export function isGroundedKeyboardAssistCandidate(
  candidate: NormalizedKeyboardAssistCompilerOutput["candidates"][number],
  value: NormalizedKeyboardAssistCompilerOutput,
): boolean {
  const messagesByIndex = new Map(
    value.messages.map((message) => [message.index, message.text]),
  );
  const allVisibleMessages = value.messages.map((message) => message.text).join(
    "\n",
  );
  if (
    candidate.evidenceIndices.length < 1 ||
    candidate.evidenceIndices.some((index) => !messagesByIndex.has(index))
  ) return false;
  return hasOnlyGroundedFactualTokens(candidate.text, allVisibleMessages);
}

/// Why the batch is about to be refused, at the granularity telemetry can
/// carry. `citation` means the candidate pointed at a message index that does
/// not exist, which is a different bug from asserting a fact off screen.
export function ungroundedCandidateTokenClass(
  value: NormalizedKeyboardAssistCompilerOutput,
): FactualTokenClass | "citation" | null {
  const messagesByIndex = new Set(
    value.messages.map((message) => message.index),
  );
  const allVisibleMessages = value.messages.map((message) => message.text).join(
    "\n",
  );
  for (const candidate of value.candidates) {
    if (
      candidate.evidenceIndices.length < 1 ||
      candidate.evidenceIndices.some((index) => !messagesByIndex.has(index))
    ) return "citation";
    const tokenClass = ungroundedFactualTokenClass(
      candidate.text,
      allVisibleMessages,
    );
    if (tokenClass !== null) return tokenClass;
  }
  return null;
}

export function isGroundedKeyboardAssistCompilerOutput(
  value: NormalizedKeyboardAssistCompilerOutput,
): boolean {
  const messagesByIndex = new Map(
    value.messages.map((message) => [message.index, message.text]),
  );
  const allVisibleMessages = value.messages.map((message) => message.text).join(
    "\n",
  );
  if (
    !hasOnlyGroundedFactualTokens(value.cue, allVisibleMessages) ||
    value.uncertainty !== null &&
      !hasOnlyGroundedFactualTokens(value.uncertainty, allVisibleMessages)
  ) return false;

  return value.candidates.every((candidate) => {
    // The citation contract still has to hold: a candidate must point at real
    // messages. But the safety property is "no fact from outside this
    // screenshot", so the tokens are checked against everything visible rather
    // than only the messages this candidate happened to cite. Checking against
    // the citation alone rejects an ordinary reply that answers the newest
    // message using a date agreed three messages earlier — a real conversation
    // spreads its facts around, and that rejection is a hard failure the user
    // can only escape by giving up.
    if (
      candidate.evidenceIndices.length < 1 ||
      candidate.evidenceIndices.some((index) => !messagesByIndex.has(index))
    ) return false;
    return hasOnlyGroundedFactualTokens(candidate.text, allVisibleMessages);
  });
}
