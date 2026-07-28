import type {
  KeyboardAssistReadyResult,
  KeyboardAssistV1Request,
} from "./contract.ts";
import type { NormalizedKeyboardAssistCompilerOutput } from "./normalize.ts";

const RELATIVE_DATE_TOKENS = [
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

function addMatches(
  tokens: Set<string>,
  value: string,
  pattern: RegExp,
  group = 0,
): void {
  for (const match of value.matchAll(pattern)) {
    const token = match[group];
    if (token) tokens.add(compactFactualText(token));
  }
}

function factualTokens(value: string): Set<string> {
  const tokens = new Set<string>();
  const normalized = normalizeFactualText(value);

  addMatches(
    tokens,
    normalized,
    /\d{1,4}\s*(?:[./-]|年)\s*\d{1,2}(?:\s*(?:[./-]|月)\s*\d{1,2}\s*(?:日|號)?)?/gu,
  );
  addMatches(
    tokens,
    normalized,
    /\d{1,2}\s*月\s*\d{1,2}\s*(?:日|號)?/gu,
  );
  addMatches(
    tokens,
    normalized,
    /[一二三四五六七八九十廿卅]{1,4}月[一二三四五六七八九十廿卅]{1,4}(?:日|號)/gu,
  );
  addMatches(tokens, normalized, /(?:星期|禮拜|週|周)[一二三四五六日天]/gu);
  for (const token of RELATIVE_DATE_TOKENS) {
    if (normalized.includes(token)) tokens.add(compactFactualText(token));
  }
  for (const token of HISTORY_REFERENCE_TOKENS) {
    if (normalized.includes(token)) tokens.add(compactFactualText(token));
  }

  addMatches(tokens, normalized, /\d{1,2}\s*[:：]\s*\d{2}/gu);
  addMatches(
    tokens,
    normalized,
    /(?:凌晨|早上|上午|中午|下午|傍晚|晚上)\s*(?:\d{1,2}|[一二三四五六七八九十]{1,3})\s*(?:點|時)(?:半|[一二三四五六七八九十\d]{1,3}分)?/gu,
  );
  addMatches(tokens, normalized, /\d+(?:[.,]\d+)*/gu);
  addMatches(
    tokens,
    normalized,
    /(?:https?:\/\/|www\.)[^\s<>"'，。！？、]+/gu,
  );
  addMatches(tokens, normalized, /@[a-z0-9_.-]+/gu);

  for (const place of COMMON_PLACE_TOKENS) {
    if (normalized.includes(place)) tokens.add(compactFactualText(place));
  }
  for (const venue of COMMON_VENUE_TOKENS) {
    if (normalized.includes(venue)) tokens.add(compactFactualText(venue));
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
      tokens.add(compactFactualText(token));
    }
  }

  for (
    const pattern of [
      CHINESE_FULL_NAME_PATTERN,
      CHINESE_NICKNAME_PATTERN,
      CHINESE_TITLED_NAME_PATTERN,
    ]
  ) {
    addMatches(tokens, value, pattern, 1);
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
      tokens.add(compactVenue);
    }
  }

  return tokens;
}

function hasOnlyGroundedFactualTokens(
  generated: string,
  evidence: string,
): boolean {
  const compactEvidence = compactFactualText(evidence);
  return [...factualTokens(generated)].every((token) =>
    compactEvidence.includes(token)
  );
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

export function isGroundedKeyboardAssistReadyResult(
  result: KeyboardAssistReadyResult,
  compiler: NormalizedKeyboardAssistCompilerOutput,
  voice: KeyboardAssistV1Request["voice"],
): boolean {
  const allVisibleMessages = compiler.messages.map((message) => message.text)
    .join("\n");
  const expectedScope = voice.primary === null
    ? "screenshot_only"
    : "screenshot_plus_global_voice";
  if (
    result.source.scope !== expectedScope ||
    result.source.messageCount !== compiler.messages.length ||
    result.source.confidence !== compiler.confidence ||
    result.source.sideConfidence !== compiler.sideConfidence ||
    result.turnState !== compiler.turnState ||
    result.cue !== compiler.cue ||
    result.uncertainty !== compiler.uncertainty
  ) return false;

  // Both batches are served to the user, so both are held to the same bar —
  // but the second batch is optional. Spreading it unguarded turned the
  // documented degrade-to-one-batch result into a TypeError, which the handler
  // could only report as a generic 503.
  return [...result.options, ...(result.alternates ?? [])].every((option) =>
    compiler.candidates.some((candidate) =>
      candidate.strategy === option.strategy &&
      candidate.text === option.text
    ) &&
    hasOnlyGroundedFactualTokens(option.why, allVisibleMessages) &&
    hasOnlyGroundedFactualTokens(option.effect, allVisibleMessages)
  );
}
