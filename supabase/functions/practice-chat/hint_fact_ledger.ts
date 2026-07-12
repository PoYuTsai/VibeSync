import type { PracticeTurn } from "./validate.ts";
import type { PracticeProfile } from "./practice_persona.ts";

export type HintFactOwner =
  | "user"
  | "partner"
  | "shared"
  | "world"
  | "third_party"
  | "unknown";

export type HintFactDomain =
  | "age"
  | "name"
  | "profession"
  | "school"
  | "residence"
  | "work_location"
  | "current_location"
  | "phone"
  | "email"
  | "social"
  | "schedule"
  | "history"
  | "pet"
  | "family"
  | "preference"
  | "lifestyle"
  | "venue";

export type HintFactRelation =
  | "is_age"
  | "is_named"
  | "works_as"
  | "attended_school"
  | "alma_mater"
  | "lives_in"
  | "hometown_is"
  | "works_at_location"
  | "is_at"
  | "has_phone"
  | "has_email"
  | "has_social"
  | "available_at"
  | "busy_at"
  | "met"
  | "has_pet"
  | "has_relative"
  | "likes"
  | "favorite"
  | "hobby"
  | "does_activity"
  | "venue_named"
  | "located_at";

export type HintFactProvenance =
  | "user_turn"
  | "partner_turn"
  | "memory"
  | "partner_context"
  | "generated_reply"
  | "generated_coaching";

export interface HintFactClaim {
  owner: HintFactOwner;
  domain: HintFactDomain;
  relation: HintFactRelation;
  anchor: string;
  quantity?: number;
  polarity: "positive" | "negative";
  provenance: HintFactProvenance;
}

export interface HintFactContext {
  claims: readonly HintFactClaim[];
  latestPartnerText: string;
}

type FactPerspective =
  | "user_turn"
  | "partner_turn"
  | "memory"
  | "partner_context"
  | "reply"
  | "coaching";

interface ExtractFactClaimsOptions {
  text: string;
  perspective: FactPerspective;
  provenance: HintFactProvenance;
  defaultOwner?: HintFactOwner;
  partnerQuoteSource?: string;
}

const ACTOR_TOKEN = String
  .raw`(?:使用者(?:本人)?|男方|對方|女生|我們|雙方|兩人|彼此|我家|我的|我|妳的|妳|你的|你|她的|她|自己)`;
const HAN_VALUE = String.raw`[\p{Script=Han}A-Za-z0-9·・._@+\-／/]{1,24}?`;
const PLACE_VALUE = String.raw`[\p{Script=Han}A-Za-z0-9·・]{2,18}?`;
const VALUE_END = String
  .raw`(?=$|[\s\p{P}\p{S}]|(?:妳|你|她)呢|平常|最近|目前|現在|又|而且|但是|但|所以|難怪|每週|每天|週末|剛|才|來|建立|製造|讓|好讓|以便)`;
const CHINESE_NUMBER = "零〇一二三四五六七八九十百千兩";
const NUMBER_TOKEN = `[0-9${CHINESE_NUMBER}]{1,4}`;
const ANIMAL = "貓|狗|兔|鳥|鸚鵡|倉鼠|天竺鼠|刺蝟|魚|烏龜";
const RELATIVE = "哥哥|弟弟|姐姐|姊姊|妹妹|姊妹|兄弟|兒子|女兒|小孩|孩子";
const SCHEDULE_DAY =
  "今天|明天|後天|今晚|明晚|明早|週末|這週|下週|上週|週[一二三四五六日天]|禮拜[一二三四五六日天]|星期[一二三四五六日天]";
const SCHEDULE_TIME =
  `(?:${SCHEDULE_DAY})(?:早上|中午|下午|晚上)?(?:${NUMBER_TOKEN}點(?:半)?)?|(?:今晚|明晚|明早|早上|中午|下午|晚上)`;
const SCHEDULE_STATUS =
  "沒空|不方便|已經有約|有約|有空|可以|能|沒事|方便|排得開|休假|下班|忙|有事|有安排|排滿|要開會|要上班|要上課|要看醫生|值班|出差|在公司|在學校|在家裡|在外面";
const HISTORY_TIME =
  `去年(?:春天|夏天|秋天|冬天|年初|年中|年底)?|前年|大前年|上個月|上週|上星期|上禮拜|昨天|前天|前幾天|疫情前|(?:${NUMBER_TOKEN}|半)(?:個月|週|星期|禮拜|年)前|(?:小學|國中|高中|大學|研究所)(?:時|時候)|${NUMBER_TOKEN}月${NUMBER_TOKEN}(?:日|號)|[0-9]{1,2}[/.\\-][0-9]{1,2}`;

const KNOWN_PROFESSIONS = new Set([
  "大學生",
  "研究生",
  "航空業空服員",
  "醫院護理師",
  "診所護理人員",
  "牙醫診所助理",
  "精品櫃姐",
  "咖啡師",
  "行銷企劃",
  "設計師",
  "瑜珈老師",
  "健身教練",
  "美甲師",
  "活動公關",
  "銀行行員",
  "攝影師",
  "產品經理",
  "甜點師",
  "寵物美容師",
  "造型師",
  "公務員",
  "職能治療師",
  "空間設計師",
  "花藝師",
  "插畫師",
  "髮型設計師",
  "數據分析師",
  "語言家教",
  "調飲吧台",
  "社工",
  "獨立書店店員",
  "獨立樂團貝斯手",
  "旅宿管家",
  "人資顧問",
  "藥師",
  "podcast剪輯",
  "餐廚主廚",
  "圖書館員",
  "陶藝創作者",
  "衝浪教練",
  "舞蹈老師",
  "建築師",
  "ux研究員",
]);

const ALWAYS_REQUIRE_SUPPORT = new Set<HintFactDomain>([
  "age",
  "name",
  "profession",
  "school",
  "residence",
  "work_location",
  "current_location",
  "phone",
  "email",
  "social",
  "schedule",
  "history",
  "pet",
  "family",
  "preference",
  "lifestyle",
  "venue",
]);

const CITY_ALIASES: Record<string, string> = {
  臺北: "台北",
  臺北市: "台北",
  台北市: "台北",
  新北市: "新北",
  桃園市: "桃園",
  臺中: "台中",
  臺中市: "台中",
  台中市: "台中",
  臺南: "台南",
  臺南市: "台南",
  台南市: "台南",
  高雄市: "高雄",
  基隆市: "基隆",
  新竹市: "新竹",
  嘉義市: "嘉義",
};

const SCHOOL_ALIASES: Record<string, string> = {
  國立臺灣大學: "台大",
  國立台灣大學: "台大",
  臺灣大學: "台大",
  台灣大學: "台大",
  國立政治大學: "政大",
  國立清華大學: "清大",
  國立成功大學: "成大",
  國立陽明交通大學: "陽明交大",
  國立交通大學: "交大",
};

function chineseNumberValue(raw: string): number | null {
  if (/^\d+$/u.test(raw)) return Number(raw);
  const digits: Record<string, number> = {
    零: 0,
    〇: 0,
    一: 1,
    二: 2,
    兩: 2,
    三: 3,
    四: 4,
    五: 5,
    六: 6,
    七: 7,
    八: 8,
    九: 9,
  };
  if (!/[十百千]/u.test(raw)) {
    const value = [...raw].map((char) => digits[char]).join("");
    return /^\d+$/u.test(value) ? Number(value) : null;
  }
  const units: Record<string, number> = { 十: 10, 百: 100, 千: 1000 };
  let total = 0;
  let pending = 0;
  for (const char of raw) {
    if (char in digits) {
      pending = digits[char];
      continue;
    }
    const unit = units[char];
    if (!unit) return null;
    total += (pending || 1) * unit;
    pending = 0;
  }
  return total + pending;
}

function normalizeBase(value: string): string {
  return value.normalize("NFKC").toLowerCase().replace(/臺/gu, "台").trim();
}

function normalizeAnchor(value: string): string {
  return normalizeBase(value)
    .replace(/^[「『“"'（(【《〈#＃]+|[」』”"'）)】》〉]+$/gu, "")
    .replace(/[\s\p{P}\p{S}]/gu, "")
    .replace(/^(?:其實|剛好|平常|最近|目前|真的|有點|也|都)/u, "")
    .replace(/(?:啦|耶|啊|喔|欸|吧)$/u, "");
}

function normalizePlace(value: string): string {
  const cleaned = value.replace(
    /^.*(?:記錄中的|紀錄中的|資料中的|事實中的|自己在|她在|妳在|你在|我在|回答|說出|接住|位於|靠近|路過|就在)/u,
    "",
  );
  const normalized = normalizeAnchor(cleaned).replace(/的具體素材$/u, "");
  return CITY_ALIASES[cleaned.trim()] ?? CITY_ALIASES[normalized] ?? normalized;
}

function normalizeSchool(value: string): string {
  const normalized = normalizeAnchor(value).replace(/^國立/u, "");
  return SCHOOL_ALIASES[value.trim()] ?? SCHOOL_ALIASES[normalized] ??
    normalized;
}

function normalizePhone(value: string): string {
  let digits = value.replace(/\D/gu, "");
  if (digits.startsWith("886") && digits.length >= 11) {
    digits = `0${digits.slice(3)}`;
  }
  return digits;
}

function normalizeSchedule(value: string): string {
  let normalized = normalizeBase(value)
    .replace(/上(?:星期|禮拜)/gu, "上週")
    .replace(/下(?:星期|禮拜)/gu, "下週")
    .replace(/這(?:星期|禮拜)/gu, "這週")
    .replace(/明晚/gu, "明天晚上")
    .replace(/明早/gu, "明天早上");
  normalized = normalized.replace(
    new RegExp(`[${CHINESE_NUMBER}]+(?=點|歲|隻|個|週|年|月|日|號)`, "gu"),
    (raw) => String(chineseNumberValue(raw) ?? raw),
  );
  return normalized.replace(/[\s\p{P}\p{S}]/gu, "");
}

function perspectiveOwners(perspective: FactPerspective): {
  first: HintFactOwner;
  second: HintFactOwner;
} {
  switch (perspective) {
    case "user_turn":
    case "reply":
      return { first: "user", second: "partner" };
    case "partner_turn":
    case "partner_context":
      return { first: "partner", second: "user" };
    case "coaching":
      return { first: "user", second: "user" };
    case "memory":
      return { first: "unknown", second: "unknown" };
  }
}

function explicitOwnerForToken(
  token: string,
  perspective: FactPerspective,
): HintFactOwner | null {
  const normalized = normalizeBase(token).replace(/的$/u, "");
  if (/^(?:使用者(?:本人)?|男方)$/u.test(normalized)) return "user";
  if (/^(?:對方|女生|她)$/u.test(normalized)) return "partner";
  if (/^(?:我們|雙方|兩人|彼此)$/u.test(normalized)) return "shared";
  if (/^(?:我|我家)$/u.test(normalized)) {
    return perspectiveOwners(perspective).first;
  }
  if (/^(?:妳|你)$/u.test(normalized)) {
    return perspectiveOwners(perspective).second;
  }
  return null;
}

function quoteOwnerAt(
  text: string,
  index: number,
  perspective: FactPerspective,
): HintFactOwner | null {
  const before = text.slice(0, index);
  const openIndex = Math.max(
    before.lastIndexOf("「"),
    before.lastIndexOf("『"),
    before.lastIndexOf("“"),
    before.lastIndexOf('"'),
  );
  const closeIndex = Math.max(
    before.lastIndexOf("」"),
    before.lastIndexOf("』"),
    before.lastIndexOf("”"),
  );
  if (openIndex < 0 || closeIndex > openIndex) return null;
  const prefix = text.slice(Math.max(0, openIndex - 24), openIndex);
  const speaker = prefix.match(
    new RegExp(
      `(${ACTOR_TOKEN}).{0,4}(?:說|回|回答|提|寫|傳)(?:來|成|一句)?[：:]?$`,
      "u",
    ),
  );
  if (!speaker) return null;
  return explicitOwnerForToken(speaker[1] ?? "", perspective);
}

function isSuppressedQuotedClaim(
  text: string,
  index: number,
  partnerQuoteSource?: string,
): boolean {
  const before = text.slice(0, index);
  const openIndex = Math.max(
    before.lastIndexOf("「"),
    before.lastIndexOf("『"),
    before.lastIndexOf("“"),
    before.lastIndexOf('"'),
  );
  const closeIndex = Math.max(
    before.lastIndexOf("」"),
    before.lastIndexOf("』"),
    before.lastIndexOf("”"),
  );
  if (openIndex < 0 || closeIndex > openIndex) return false;
  const prefix = text.slice(Math.max(0, openIndex - 20), openIndex);
  if (
    /(?:不要|別|不可|不能|不得|避免)(?:回|說|寫|傳|宣稱)?[：:]?$|(?:不是|並不是)(?:要|叫|讓)(?:你|妳|使用者)?(?:回|說|寫|傳|宣稱)?[：:]?$|(?:錯誤|亂補|瞎掰)(?:示範|說法)?[：:]?$/u
      .test(prefix.trim())
  ) {
    return true;
  }
  if (
    !partnerQuoteSource || !/(?:原話|她的原話|對方原話)[：:]?$/u.test(prefix)
  ) {
    return false;
  }
  const closeCandidates = [
    text.indexOf("」", index),
    text.indexOf("』", index),
    text.indexOf("”", index),
    text.indexOf('"', index),
  ].filter((candidate) => candidate >= 0);
  if (closeCandidates.length === 0) return false;
  const closeAfter = Math.min(...closeCandidates);
  const quote = normalizeAnchor(text.slice(openIndex + 1, closeAfter));
  const source = normalizeAnchor(partnerQuoteSource);
  return quote.length > 0 && (source.includes(quote) || quote.includes(source));
}

function ownerAt(
  text: string,
  index: number,
  token: string | undefined,
  perspective: FactPerspective,
  defaultOwner: HintFactOwner,
  predicateIndex?: number,
): HintFactOwner {
  if (predicateIndex !== undefined && predicateIndex >= index) {
    const beforePredicate = text.slice(0, predicateIndex);
    const clauseStart = Math.max(
      beforePredicate.lastIndexOf("。"),
      beforePredicate.lastIndexOf("！"),
      beforePredicate.lastIndexOf("？"),
      beforePredicate.lastIndexOf("；"),
      beforePredicate.lastIndexOf("，"),
      beforePredicate.lastIndexOf(","),
      beforePredicate.lastIndexOf("："),
      beforePredicate.lastIndexOf(":"),
    ) + 1;
    const actorMatches = [
      ...text.slice(clauseStart, predicateIndex).matchAll(
        new RegExp(`(${ACTOR_TOKEN})`, "gu"),
      ),
    ];
    const nearest = actorMatches.at(-1)?.[1];
    if (nearest && !/^自己(?:的)?$/u.test(nearest)) {
      const explicit = explicitOwnerForToken(nearest, perspective);
      if (explicit) {
        if (/^(?:我|我的|我家)$/u.test(nearest)) {
          return quoteOwnerAt(text, predicateIndex, perspective) ?? explicit;
        }
        return explicit;
      }
    }
  }
  if (token && !/^自己(?:的)?$/u.test(token)) {
    const explicit = explicitOwnerForToken(token, perspective);
    if (explicit) {
      if (/^(?:我|我的|我家)$/u.test(token)) {
        return quoteOwnerAt(text, index, perspective) ?? explicit;
      }
      return explicit;
    }
  }
  const before = text.slice(0, index);
  const clauseStart = Math.max(
    before.lastIndexOf("。"),
    before.lastIndexOf("！"),
    before.lastIndexOf("？"),
    before.lastIndexOf("；"),
    before.lastIndexOf("，"),
    before.lastIndexOf(","),
    before.lastIndexOf("："),
    before.lastIndexOf(":"),
  ) + 1;
  const actorMatches = [
    ...before.matchAll(new RegExp(`(${ACTOR_TOKEN})`, "gu")),
  ];
  for (let i = actorMatches.length - 1; i >= 0; i--) {
    const actor = actorMatches[i];
    if ((actor.index ?? 0) < Math.max(clauseStart, index - 28)) break;
    const explicit = explicitOwnerForToken(actor[1] ?? "", perspective);
    if (explicit) return explicit;
  }
  return defaultOwner;
}

function matchGroupIndex(
  match: RegExpMatchArray,
  groupIndex: number,
): number {
  const value = match[groupIndex] ?? "";
  const localIndex = value ? match[0].lastIndexOf(value) : 0;
  return (match.index ?? 0) + Math.max(0, localIndex);
}

function localClauseAt(text: string, index: number): string {
  const separators = /[\n。！？!?；;，,：:]/u;
  let start = index;
  while (start > 0 && !separators.test(text[start - 1])) start--;
  let end = index;
  while (end < text.length && !separators.test(text[end])) end++;
  return text.slice(start, end);
}

function isQuestionOrCondition(
  text: string,
  index: number,
  owner?: HintFactOwner,
): boolean {
  const clause = localClauseAt(text, index);
  const before = text.slice(0, index);
  const clauseStart = Math.max(
    before.lastIndexOf("。"),
    before.lastIndexOf("！"),
    before.lastIndexOf("？"),
    before.lastIndexOf("；"),
    before.lastIndexOf("，"),
    before.lastIndexOf(","),
    before.lastIndexOf("："),
    before.lastIndexOf(":"),
    before.lastIndexOf("\n"),
  ) + 1;
  const claimOffset = Math.max(0, index - clauseStart);
  if (/^(?:如果|假如|假設|要是)/u.test(clause.trim())) return true;
  if (
    (owner === "partner" || owner === "third_party") &&
    /(?:想聽|想知道|想問|想了解|請問|說說|告訴我|跟我說|分享)/u.test(
      clause.slice(0, claimOffset),
    )
  ) {
    return true;
  }
  const questionLike =
    /(?:[?？]|是不是|是否|有沒有|會不會|能不能|哪(?:裡|間|個|位|條)?|什麼|幾歲|嗎|呢)/u
      .test(clause) ||
    /(?:問|確認|猜).{0,8}(?:是不是|是否|有沒有|哪|什麼|幾|嗎)/u
      .test(clause);
  if (!questionLike) return false;
  const followUpPattern = owner === "user" || owner === "shared"
    ? /(?:妳|你|她)(?:呢|嗎)(?:[?？])?\s*$/u
    : owner === "partner"
    ? /(?:我|使用者)(?:呢|嗎)(?:[?？])?\s*$/u
    : null;
  const followUp = followUpPattern?.exec(clause);
  if (followUp && (followUp.index ?? 0) > claimOffset) return false;
  return true;
}

function polarityAt(text: string, index: number): "positive" | "negative" {
  const window = localClauseAt(text, index);
  return /(?:不是|並非|沒有|沒在|不同(?:年|歲|名|校|業|鄉|城)|不住|不叫|不念|不讀|不養|不喜歡|不愛|不當|不做)/u
      .test(window)
    ? "negative"
    : "positive";
}

function factKey(claim: HintFactClaim): string {
  return [
    claim.owner,
    claim.domain,
    claim.relation,
    claim.anchor,
    claim.quantity ?? "",
    claim.polarity,
  ].join("|");
}

function looksLikeSchool(value: string): boolean {
  return /(?:大學|學院|高中|高職|國中|國小|研究所|台大|政大|清大|交大|成大|北大|輔大|淡江|東吳|逢甲|文化|世新|台科|北科)/u
    .test(value);
}

function looksLikeProfession(value: string): boolean {
  const normalized = normalizeAnchor(value);
  return KNOWN_PROFESSIONS.has(normalized) ||
    /(?:社工|工程師|設計師|護理師|老師|教師|教練|醫師|醫生|律師|會計師|心理師|治療師|攝影師|藥師|營養師|建築師|咖啡師|美甲師|造型師|甜點師|花藝師|插畫師|公務員|研究員|分析師|學生|研究生|業務|行銷|企劃|經理|顧問|家教|行員|店員|館員|管家|主廚|剪輯|創作者|空服員|地勤|房仲|公關|吧台|貝斯手|PM|UX|UI)/iu
      .test(normalized);
}

function looksLikePersonName(value: string): boolean {
  if (/^[A-Za-z][A-Za-z0-9._-]{1,19}$/u.test(value)) return true;
  if (!/^[\p{Script=Han}·・]{2,4}$/u.test(value)) return false;
  return !/^(?:我|妳|你|她|我們|對方|使用者)/u.test(value) &&
    !/^(?:太|很|真|超|好|有點)/u.test(value) &&
    !/(?:本人|自己|生活|時間|空間|機會|答案|回覆|句子|感覺|確認|窗口|咖啡|低壓|邀約|版本|品味|畫面|話題)/u
      .test(value) &&
    !/(?:別|不要|快|先|再|說|回|鬧|看|聽|問|猜|去|來|住|叫|扯|累|忙|開心)$/u
      .test(value);
}

function looksLikePersonReference(value: string): boolean {
  return looksLikePersonName(value) ||
    /^(?:朋友|同事|同學|家人|室友|學長|學姊|學妹|學弟)$/u.test(value);
}

function looksLikeLocationAnchor(value: string): boolean {
  const normalized = normalizePlace(value);
  if (Object.values(CITY_ALIASES).includes(normalized)) return true;
  if (
    new Set([
      "家",
      "家裡",
      "公司",
      "學校",
      "外面",
      "路上",
      "車站",
      "捷運站",
      "火車站",
      "高鐵站",
    ]).has(normalized)
  ) {
    return true;
  }
  return /(?:站|路|街|巷|區|市|縣|鄉|鎮|村|里|町|山|公園|夜市|商圈|碼頭|廣場|大樓|中心|號|樓|101)$/u
    .test(normalized);
}

function normalizePreference(value: string): string {
  return normalizeAnchor(value)
    .replace(/(?:每週|每天|週末|平常|最近).*/u, "")
    .replace(/(?:這件事|這一點|這種感覺)$/u, "");
}

function isTransientReactionPreference(value: string): boolean {
  return /^(?:妳|你|她|對方)?(?:這個|這種|剛剛的|現在的)?(?:反應|回覆|語氣|說法|笑法|吐槽|問題|形容|比喻)$/u
    .test(value);
}

export function extractHintFactClaims(
  options: ExtractFactClaimsOptions,
): HintFactClaim[] {
  const text = options.text.normalize("NFKC").replace(/臺/gu, "台");
  const defaultOwner = options.defaultOwner ?? "unknown";
  const claims: HintFactClaim[] = [];
  const add = (
    input: Omit<HintFactClaim, "provenance"> & { index: number },
  ) => {
    if (
      !input.anchor || isQuestionOrCondition(text, input.index, input.owner) ||
      isSuppressedQuotedClaim(
        text,
        input.index,
        options.partnerQuoteSource,
      )
    ) return;
    claims.push({
      owner: input.owner,
      domain: input.domain,
      relation: input.relation,
      anchor: input.anchor,
      quantity: input.quantity,
      polarity: input.polarity,
      provenance: options.provenance,
    });
  };

  for (
    const match of text.matchAll(
      new RegExp(`(${ACTOR_TOKEN}).{0,8}?((?:${NUMBER_TOKEN}))歲`, "gu"),
    )
  ) {
    const value = chineseNumberValue(match[2] ?? "");
    if (value === null || value < 1 || value > 120) continue;
    add({
      owner: ownerAt(
        text,
        match.index ?? 0,
        match[1],
        options.perspective,
        defaultOwner,
        matchGroupIndex(match, 2),
      ),
      domain: "age",
      relation: "is_age",
      anchor: String(value),
      polarity: polarityAt(text, match.index ?? 0),
      index: match.index ?? 0,
    });
  }
  for (
    const match of text.matchAll(
      new RegExp(
        `(${ACTOR_TOKEN})[^，,。！？!?]{0,8}?(${HISTORY_TIME})[^，,。！？!?]{0,8}?(?:見過|碰過|遇過|認識)`,
        "gu",
      ),
    )
  ) {
    add({
      owner: ownerAt(
        text,
        match.index ?? 0,
        match[1],
        options.perspective,
        defaultOwner,
        matchGroupIndex(match, 2),
      ),
      domain: "history",
      relation: "met",
      anchor: normalizeSchedule(match[2] ?? ""),
      polarity: polarityAt(text, match.index ?? 0),
      index: match.index ?? 0,
    });
  }

  const residencePatterns = [
    new RegExp(
      `(${ACTOR_TOKEN})(?:平常|目前|現在|最近|其實|剛好|也|都|一直|就|大概|可能|差不多|沒有|沒){0,3}(住(?:(?:在)|(?:的地方(?:也)?(?:是|在))|(?!的地方|著))|(?:老家|家鄉|住處)(?:也)?(?:是|在))\\s*(${PLACE_VALUE})${VALUE_END}`,
      "gu",
    ),
    new RegExp(
      `(${PLACE_VALUE})(?:也)?是(${ACTOR_TOKEN})(?:目前|現在)?(?:的)?(家鄉|老家|住處|住的地方)${VALUE_END}`,
      "gu",
    ),
    new RegExp(
      `(?:^|[，,])(?:平常|目前|現在|最近|其實|剛好|也|都|一直|就){0,3}(住(?:在)?|(?:老家|家鄉|住處)(?:也)?(?:是|在))\\s*(${PLACE_VALUE})${VALUE_END}`,
      "gu",
    ),
  ];
  for (const [patternIndex, pattern] of residencePatterns.entries()) {
    for (const match of text.matchAll(pattern)) {
      const actorToken = patternIndex === 0
        ? match[1]
        : patternIndex === 1
        ? match[2]
        : undefined;
      const relationText = patternIndex === 0
        ? match[2]
        : patternIndex === 1
        ? match[3]
        : match[1];
      const rawPlace = patternIndex === 0
        ? match[3]
        : patternIndex === 1
        ? match[1]
        : match[2];
      add({
        owner: ownerAt(
          text,
          match.index ?? 0,
          actorToken,
          options.perspective,
          defaultOwner,
        ),
        domain: "residence",
        relation: /家鄉|老家/u.test(relationText ?? "")
          ? "hometown_is"
          : "lives_in",
        anchor: normalizePlace(rawPlace ?? ""),
        polarity: polarityAt(text, match.index ?? 0),
        index: match.index ?? 0,
      });
    }
  }
  for (
    const match of text.matchAll(
      new RegExp(
        `(${ACTOR_TOKEN})(?:願意|主動|有)?(?:分享|提到|說|表示)(?:了)?(?:自己)?(住(?:在)?|(?:老家|家鄉|住處)(?:也)?(?:是|在))\\s*(${PLACE_VALUE})${VALUE_END}`,
        "gu",
      ),
    )
  ) {
    add({
      owner: ownerAt(
        text,
        match.index ?? 0,
        match[1],
        options.perspective,
        defaultOwner,
        matchGroupIndex(match, 2),
      ),
      domain: "residence",
      relation: /家鄉|老家/u.test(match[2] ?? "") ? "hometown_is" : "lives_in",
      anchor: normalizePlace(match[3] ?? ""),
      polarity: polarityAt(text, match.index ?? 0),
      index: match.index ?? 0,
    });
  }

  const residenceParaphrases: Array<{
    pattern: RegExp;
    relation: "lives_in" | "hometown_is";
  }> = [
    {
      pattern: new RegExp(
        `(${ACTOR_TOKEN})(?:平常|目前|現在|最近|其實|剛好|也|都|一直|就){0,3}(?:的)?(?:生活圈|活動範圍)(?:也)?(?:就|主要)?(?:是|在)?\\s*(${PLACE_VALUE})${VALUE_END}`,
        "gu",
      ),
      relation: "lives_in",
    },
    {
      pattern: new RegExp(
        `(${ACTOR_TOKEN})(?:平常|目前|現在|最近|其實|剛好|也|都|一直|就){0,3}以\\s*(${PLACE_VALUE})\\s*為(?:生活)?基地${VALUE_END}`,
        "gu",
      ),
      relation: "lives_in",
    },
    {
      pattern: new RegExp(
        `(${ACTOR_TOKEN})(?:平常|目前|現在|最近|其實|剛好|也|都|一直|就){0,3}(?:是)?\\s*(${PLACE_VALUE})人${VALUE_END}`,
        "gu",
      ),
      relation: "hometown_is",
    },
    {
      pattern: new RegExp(
        `(${ACTOR_TOKEN})(?:平常|目前|現在|最近|其實|剛好|也|都|一直|就){0,3}來自\\s*(${PLACE_VALUE})${VALUE_END}`,
        "gu",
      ),
      relation: "hometown_is",
    },
  ];
  for (const config of residenceParaphrases) {
    for (const match of text.matchAll(config.pattern)) {
      add({
        owner: ownerAt(
          text,
          match.index ?? 0,
          match[1],
          options.perspective,
          defaultOwner,
        ),
        domain: "residence",
        relation: config.relation,
        anchor: normalizePlace(match[2] ?? ""),
        polarity: polarityAt(text, match.index ?? 0),
        index: match.index ?? 0,
      });
    }
  }

  const schoolPatterns = [
    new RegExp(
      `(${ACTOR_TOKEN})(?:平常|以前|之前|最近|也|都|剛好|原本){0,3}(讀|念|就讀)(?:的)?(?:也)?(?:是|在)?\\s*(${HAN_VALUE})${VALUE_END}`,
      "gu",
    ),
    new RegExp(
      `(${ACTOR_TOKEN})(?:的)?母校(?:也)?(?:是|在)\\s*(${HAN_VALUE})${VALUE_END}`,
      "gu",
    ),
    new RegExp(
      `(${HAN_VALUE})(?:也)?是(${ACTOR_TOKEN})(?:的)?母校${VALUE_END}`,
      "gu",
    ),
    new RegExp(
      `(${ACTOR_TOKEN})(?:平常|以前|之前|最近|也|都|剛好|原本){0,3}(?:是|當)\\s*(${HAN_VALUE})校友${VALUE_END}`,
      "gu",
    ),
  ];
  for (const [patternIndex, pattern] of schoolPatterns.entries()) {
    for (const match of text.matchAll(pattern)) {
      const actorToken = patternIndex === 2 ? match[2] : match[1];
      const rawSchool = patternIndex === 0
        ? match[3]
        : patternIndex === 3
        ? match[2]
        : match[1 + (patternIndex === 1 ? 1 : 0)];
      const school = normalizeSchool(rawSchool ?? "");
      if (!looksLikeSchool(school)) continue;
      add({
        owner: ownerAt(
          text,
          match.index ?? 0,
          actorToken,
          options.perspective,
          defaultOwner,
        ),
        domain: "school",
        relation: patternIndex === 0 ? "attended_school" : "alma_mater",
        anchor: school,
        polarity: polarityAt(text, match.index ?? 0),
        index: match.index ?? 0,
      });
    }
  }

  const professionPatterns = [
    new RegExp(
      `(${ACTOR_TOKEN})(?:的)?(?:工作|職業)(?:也)?(?:是|為|做)\\s*(${HAN_VALUE})${VALUE_END}`,
      "gu",
    ),
    new RegExp(
      `(${HAN_VALUE})(?:也)?是(${ACTOR_TOKEN})(?:的)?(?:工作|職業)${VALUE_END}`,
      "gu",
    ),
    new RegExp(
      `(${ACTOR_TOKEN})(?:平常|目前|現在|其實|也|都){0,3}(?:不是|是|不當|當|不做|做)\\s*(${HAN_VALUE})${VALUE_END}`,
      "gu",
    ),
    /profession\s*:\s*([^\n，,。！？!?；;]{1,30})/giu,
  ];
  for (const [patternIndex, pattern] of professionPatterns.entries()) {
    for (const match of text.matchAll(pattern)) {
      const actorToken = patternIndex === 1 ? match[2] : match[1];
      const rawProfession = patternIndex === 1
        ? match[1]
        : match[2] ?? match[1];
      const profession = normalizeAnchor(rawProfession ?? "");
      if (!looksLikeProfession(profession)) continue;
      add({
        owner: patternIndex === 3 ? defaultOwner : ownerAt(
          text,
          match.index ?? 0,
          actorToken,
          options.perspective,
          defaultOwner,
        ),
        domain: "profession",
        relation: "works_as",
        anchor: profession,
        polarity: polarityAt(text, match.index ?? 0),
        index: match.index ?? 0,
      });
    }
  }

  const namePatterns = [
    new RegExp(
      `(${ACTOR_TOKEN})(?:的)?(?:名字)(?:也)?(?:是|叫)\\s*(${HAN_VALUE})${VALUE_END}`,
      "gu",
    ),
    new RegExp(`(${ACTOR_TOKEN})(?:也)?叫\\s*(${HAN_VALUE})${VALUE_END}`, "gu"),
    new RegExp(
      `(${HAN_VALUE})(?:也)?是(${ACTOR_TOKEN})(?:的)?名字${VALUE_END}`,
      "gu",
    ),
    new RegExp(`(?:^|[，,])(?:也)?叫\\s*(${HAN_VALUE})${VALUE_END}`, "gu"),
  ];
  for (const [patternIndex, pattern] of namePatterns.entries()) {
    for (const match of text.matchAll(pattern)) {
      const actorToken = patternIndex === 2
        ? match[2]
        : patternIndex === 3
        ? undefined
        : match[1];
      const name = normalizeAnchor(
        patternIndex === 2
          ? match[1]
          : patternIndex === 3
          ? match[1]
          : match[2] ?? "",
      );
      if (name.length < 2 || name.length > 20 || !looksLikePersonName(name)) {
        continue;
      }
      add({
        owner: ownerAt(
          text,
          match.index ?? 0,
          actorToken,
          options.perspective,
          defaultOwner,
        ),
        domain: "name",
        relation: "is_named",
        anchor: name,
        polarity: polarityAt(text, match.index ?? 0),
        index: match.index ?? 0,
      });
    }
  }
  for (
    const match of text.matchAll(/name\s*:\s*([^\n，,。！？!?；;]{2,30})/giu)
  ) {
    const name = normalizeAnchor(match[1] ?? "");
    if (!looksLikePersonName(name)) continue;
    add({
      owner: defaultOwner,
      domain: "name",
      relation: "is_named",
      anchor: name,
      polarity: "positive",
      index: match.index ?? 0,
    });
  }
  const thirdPartyNamePatterns: Array<{ pattern: RegExp; valueIndex: number }> =
    [
      {
        pattern:
          /(?:(?:我|我的|妳的|你的|她的|他的)(?:朋友|同事|同學|室友|學長|學姊|學妹|學弟)|(?:朋友|同事|同學|室友|學長|學姊|學妹|學弟)(?:名字是|叫))\s*([\p{Script=Han}A-Za-z·・]{2,8}?)(?=也|很|會|要|想|[，,。！？!?；;\s]|$)/gu,
        valueIndex: 1,
      },
      {
        pattern:
          /(?:(?:傳|發|送|丟)(?:給)?|轉給|交給|給)\s*([\p{Script=Han}A-Za-z·・]{2,20})(?=[，,。！？!?；;\s]|$)/gu,
        valueIndex: 1,
      },
      {
        pattern:
          /(?:^|[，,。！？!?；;\s])(?:我|我們)?(?:會|要|想)?(?:跟|和)\s*([\p{Script=Han}A-Za-z·・]{2,20}?)(?=(?:一起)?(?:去|來|吃|喝|看|逛|玩|走|見|碰面|同行))/gu,
        valueIndex: 1,
      },
      {
        pattern:
          /(?:他|那個人|這個人)(?:的名字)?(?:是|叫)\s*([\p{Script=Han}A-Za-z·・]{2,20})(?=[，,。！？!?；;\s]|$)/gu,
        valueIndex: 1,
      },
      {
        pattern:
          /(?:^|[，,。！？!?；;\s])([\p{Script=Han}A-Za-z·・]{2,20})(?:會|能|可以)?收到(?:這張|照片|訊息)/gu,
        valueIndex: 1,
      },
    ];
  for (const config of thirdPartyNamePatterns) {
    for (const match of text.matchAll(config.pattern)) {
      const name = normalizeAnchor(match[config.valueIndex] ?? "");
      if (!looksLikePersonReference(name)) continue;
      add({
        owner: "third_party",
        domain: "name",
        relation: "is_named",
        anchor: name,
        polarity: "positive",
        index: match.index ?? 0,
      });
    }
  }

  const preferencePatterns = [
    new RegExp(
      `(${ACTOR_TOKEN})(?:平常|其實|真的|也|都|最|超|很){0,3}(最愛的|最喜歡的)(?:也)?(?:是)?\\s*(${HAN_VALUE})${VALUE_END}`,
      "gu",
    ),
    new RegExp(
      `(${ACTOR_TOKEN})(?:平常|其實|真的|也|都){0,3}(最愛|超愛|很愛|熱愛|喜歡)\\s*(${HAN_VALUE})${VALUE_END}`,
      "gu",
    ),
    new RegExp(
      `(${ACTOR_TOKEN})(?:的)?(興趣|嗜好)(?:也)?(?:是|有)\\s*(${HAN_VALUE})${VALUE_END}`,
      "gu",
    ),
    new RegExp(
      `(${HAN_VALUE})(?:也)?是(${ACTOR_TOKEN})(?:的)?(最愛|興趣|嗜好)${VALUE_END}`,
      "gu",
    ),
    /likes\s*:\s*([^\n。！？!?；;]{1,100})/giu,
  ];
  for (const [patternIndex, pattern] of preferencePatterns.entries()) {
    for (const match of text.matchAll(pattern)) {
      if (patternIndex === 4) {
        for (const rawLike of (match[1] ?? "").split(/[、,，／/]/u)) {
          const anchor = normalizePreference(rawLike);
          if (!anchor) continue;
          add({
            owner: defaultOwner,
            domain: "preference",
            relation: "likes",
            anchor,
            polarity: "positive",
            index: match.index ?? 0,
          });
        }
        continue;
      }
      const actorToken = patternIndex === 3 ? match[2] : match[1];
      const relationText = patternIndex === 3 ? match[3] : match[2];
      const rawPreference = patternIndex === 3 ? match[1] : match[3];
      const anchor = normalizePreference(rawPreference ?? "");
      if (
        !anchor || /^(?:哪|什麼|誰)/u.test(anchor) ||
        isTransientReactionPreference(anchor)
      ) continue;
      add({
        owner: ownerAt(
          text,
          match.index ?? 0,
          actorToken,
          options.perspective,
          defaultOwner,
        ),
        domain: "preference",
        relation: /最愛|最喜歡/u.test(relationText ?? "")
          ? "favorite"
          : /興趣|嗜好/u.test(relationText ?? "")
          ? "hobby"
          : "likes",
        anchor,
        polarity: polarityAt(text, match.index ?? 0),
        index: match.index ?? 0,
      });
    }
  }
  for (
    const match of text.matchAll(
      new RegExp(
        `(${ACTOR_TOKEN})(?:平常|其實|真的|也|都|根本|完全){0,3}(?:是)?\\s*(${HAN_VALUE})(?:控|派|粉|愛好者)${VALUE_END}`,
        "gu",
      ),
    )
  ) {
    const anchor = normalizePreference(match[2] ?? "");
    if (!anchor) continue;
    add({
      owner: ownerAt(
        text,
        match.index ?? 0,
        match[1],
        options.perspective,
        defaultOwner,
      ),
      domain: "preference",
      relation: "likes",
      anchor,
      polarity: polarityAt(text, match.index ?? 0),
      index: match.index ?? 0,
    });
  }

  const petPatterns = [
    new RegExp(
      `(${ACTOR_TOKEN})(?:家(?:裡)?)?(?:剛好|目前|現在|也|都)?(?:養(?:了|著)?|有(?!被))\\s*(?:(${NUMBER_TOKEN})\\s*隻)?\\s*(${ANIMAL})`,
      "gu",
    ),
    new RegExp(
      `(?:(${NUMBER_TOKEN})\\s*隻)?\\s*(${ANIMAL})\\s*(${ACTOR_TOKEN})(?:家(?:裡)?)?(?:剛好|真的|目前|也|都)?有(?!被)`,
      "gu",
    ),
    new RegExp(
      `(?:^|[，,])(?:我家|家裡)?(?:剛好|目前|現在|也|都)?(?:養(?:了|著)?|有(?!被))\\s*(?:(${NUMBER_TOKEN})\\s*隻)?\\s*(${ANIMAL})`,
      "gu",
    ),
  ];
  for (const [patternIndex, pattern] of petPatterns.entries()) {
    for (const match of text.matchAll(pattern)) {
      const actorToken = patternIndex === 0
        ? match[1]
        : patternIndex === 1
        ? match[3]
        : undefined;
      const quantityRaw = patternIndex === 0 ? match[2] : match[1];
      const animal = normalizeAnchor(
        patternIndex === 0 ? match[3] : match[2] ?? "",
      );
      const quantity = quantityRaw
        ? chineseNumberValue(quantityRaw) ?? undefined
        : undefined;
      add({
        owner: ownerAt(
          text,
          match.index ?? 0,
          actorToken,
          options.perspective,
          defaultOwner,
        ),
        domain: "pet",
        relation: "has_pet",
        anchor: animal,
        quantity,
        polarity: polarityAt(text, match.index ?? 0),
        index: match.index ?? 0,
      });
    }
  }
  for (
    const match of text.matchAll(
      new RegExp(
        `(${ACTOR_TOKEN})(?:家(?:裡)?)?住著\\s*(?:(${NUMBER_TOKEN})\\s*隻)?\\s*(${ANIMAL})`,
        "gu",
      ),
    )
  ) {
    add({
      owner: ownerAt(
        text,
        match.index ?? 0,
        match[1],
        options.perspective,
        defaultOwner,
      ),
      domain: "pet",
      relation: "has_pet",
      anchor: normalizeAnchor(match[3] ?? ""),
      quantity: match[2]
        ? chineseNumberValue(match[2]) ?? undefined
        : undefined,
      polarity: polarityAt(text, match.index ?? 0),
      index: match.index ?? 0,
    });
  }

  const familyPatterns = [
    new RegExp(
      `(${ACTOR_TOKEN})(?:家(?:裡)?)?(?:剛好|目前|也|都)?有(?!被)\\s*(?:(${NUMBER_TOKEN})\\s*個?)?\\s*(${RELATIVE})`,
      "gu",
    ),
    new RegExp(`(${ACTOR_TOKEN})(?:的)(${RELATIVE})`, "gu"),
    new RegExp(
      `(${RELATIVE})\\s*(${ACTOR_TOKEN})(?:剛好|也|都)?有\\s*(?:(${NUMBER_TOKEN})\\s*個?)?`,
      "gu",
    ),
  ];
  for (const [patternIndex, pattern] of familyPatterns.entries()) {
    for (const match of text.matchAll(pattern)) {
      const actorToken = patternIndex === 2 ? match[2] : match[1];
      const relation = normalizeAnchor(
        patternIndex === 2 ? match[1] : match[3] ?? match[2] ?? "",
      );
      const quantityRaw = patternIndex === 0
        ? match[2]
        : patternIndex === 2
        ? match[3]
        : undefined;
      add({
        owner: ownerAt(
          text,
          match.index ?? 0,
          actorToken,
          options.perspective,
          defaultOwner,
        ),
        domain: "family",
        relation: "has_relative",
        anchor: relation,
        quantity: quantityRaw
          ? chineseNumberValue(quantityRaw) ?? undefined
          : undefined,
        polarity: polarityAt(text, match.index ?? 0),
        index: match.index ?? 0,
      });
    }
  }

  for (
    const match of text.matchAll(
      new RegExp(
        `(${ACTOR_TOKEN})[^，,。！？!?]{0,10}?(${SCHEDULE_TIME})[^，,。！？!?]{0,8}?(${SCHEDULE_STATUS})`,
        "gu",
      ),
    )
  ) {
    if (/(?:想|要|可以)?約|一起|找(?:間|個)|去|來|問|建議/u.test(match[0])) {
      continue;
    }
    const following = text.slice(
      (match.index ?? 0) + match[0].length,
      (match.index ?? 0) + match[0].length + 8,
    );
    if (/^(?:想|要|打算|準備)/u.test(following)) continue;
    const busy =
      /沒空|不方便|有約|忙|有事|有安排|排滿|要開會|要上班|要上課|要看醫生|值班|出差|在公司|在學校|在家裡|在外面/u
        .test(match[3] ?? "");
    add({
      owner: ownerAt(
        text,
        match.index ?? 0,
        match[1],
        options.perspective,
        defaultOwner,
        matchGroupIndex(match, 2),
      ),
      domain: "schedule",
      relation: busy ? "busy_at" : "available_at",
      anchor: normalizeSchedule(match[2] ?? ""),
      polarity: polarityAt(text, match.index ?? 0),
      index: match.index ?? 0,
    });
  }
  const directSchedulePatterns: Array<{
    pattern: RegExp;
    actorIndex: number | null;
    timeIndex: number;
    statusIndex: number;
  }> = [
    {
      pattern: new RegExp(
        `(${ACTOR_TOKEN})\\s*(${SCHEDULE_TIME})(?:這邊|已經|也|都)?\\s*(${SCHEDULE_STATUS})`,
        "gu",
      ),
      actorIndex: 1,
      timeIndex: 2,
      statusIndex: 3,
    },
    {
      pattern: new RegExp(
        `(?:^|[，,])\\s*(${SCHEDULE_TIME})(?:這邊|已經|也|都)?\\s*(${SCHEDULE_STATUS})`,
        "gu",
      ),
      actorIndex: null,
      timeIndex: 1,
      statusIndex: 2,
    },
  ];
  for (const config of directSchedulePatterns) {
    for (const match of text.matchAll(config.pattern)) {
      const status = match[config.statusIndex] ?? "";
      const following = text.slice(
        (match.index ?? 0) + (match[0]?.length ?? 0),
        (match.index ?? 0) + (match[0]?.length ?? 0) + 8,
      );
      if (/^(?:想|要|打算|準備|計畫)/u.test(following)) continue;
      add({
        owner: ownerAt(
          text,
          match.index ?? 0,
          config.actorIndex === null ? undefined : match[config.actorIndex],
          options.perspective,
          defaultOwner,
          matchGroupIndex(match, config.timeIndex),
        ),
        domain: "schedule",
        relation:
          /沒空|不方便|有約|忙|有事|有安排|排滿|要開會|要上班|要上課|要看醫生|值班|出差|在公司|在學校|在家裡|在外面/u
              .test(status)
            ? "busy_at"
            : "available_at",
        anchor: normalizeSchedule(match[config.timeIndex] ?? ""),
        polarity: polarityAt(text, match.index ?? 0),
        index: match.index ?? 0,
      });
    }
  }
  for (
    const match of text.matchAll(
      new RegExp(
        `(${SCHEDULE_TIME}).{0,6}?(${ACTOR_TOKEN})(?:這邊)?(?:也|都)?(${SCHEDULE_STATUS})`,
        "gu",
      ),
    )
  ) {
    const busy =
      /沒空|不方便|有約|忙|有事|有安排|排滿|要開會|要上班|要上課|要看醫生|值班|出差|在公司|在學校|在家裡|在外面/u
        .test(match[3] ?? "");
    add({
      owner: ownerAt(
        text,
        match.index ?? 0,
        match[2],
        options.perspective,
        defaultOwner,
      ),
      domain: "schedule",
      relation: busy ? "busy_at" : "available_at",
      anchor: normalizeSchedule(match[1] ?? ""),
      polarity: polarityAt(text, match.index ?? 0),
      index: match.index ?? 0,
    });
  }

  const contactPatterns: Array<{
    domain: "phone" | "email" | "social";
    relation: "has_phone" | "has_email" | "has_social";
    pattern: RegExp;
    normalize: (value: string) => string;
  }> = [
    {
      domain: "phone",
      relation: "has_phone",
      pattern: new RegExp(
        `(${ACTOR_TOKEN})[^，,。！？!?]{0,12}?((?:\\+?886[\\s-]?)?(?:0?9\\d(?:[\\s-]?\\d){7}|0?\\d{1,2}(?:[\\s()-]?\\d){7,9}))`,
        "gu",
      ),
      normalize: normalizePhone,
    },
    {
      domain: "email",
      relation: "has_email",
      pattern: new RegExp(
        `(${ACTOR_TOKEN})[^，,。！？!?]{0,12}?([A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,})`,
        "giu",
      ),
      normalize: (value) => normalizeBase(value),
    },
    {
      domain: "social",
      relation: "has_social",
      pattern: new RegExp(
        `(${ACTOR_TOKEN})[^，,。！？!?]{0,12}?(?:line|ig|instagram|帳號|id)[^，,。！？!?]{0,5}?(@?[A-Z0-9._-]{3,30})`,
        "giu",
      ),
      normalize: (value) => normalizeBase(value).replace(/^@/u, ""),
    },
  ];
  for (const config of contactPatterns) {
    for (const match of text.matchAll(config.pattern)) {
      add({
        owner: ownerAt(
          text,
          match.index ?? 0,
          match[1],
          options.perspective,
          defaultOwner,
          matchGroupIndex(match, 2),
        ),
        domain: config.domain,
        relation: config.relation,
        anchor: config.normalize(match[2] ?? ""),
        polarity: polarityAt(text, match.index ?? 0),
        index: match.index ?? 0,
      });
    }
  }
  for (
    const match of text.matchAll(
      /(?:^|\D)((?:(?:\+?886|00886)[\s.-]*9|09)(?:[\s.-]*[0-9]){8})(?![0-9])/gu,
    )
  ) {
    add({
      owner: ownerAt(
        text,
        match.index ?? 0,
        undefined,
        options.perspective,
        defaultOwner,
      ),
      domain: "phone",
      relation: "has_phone",
      anchor: normalizePhone(match[1] ?? ""),
      polarity: polarityAt(text, match.index ?? 0),
      index: match.index ?? 0,
    });
  }
  for (
    const match of text.matchAll(
      /(?:^|[^0-9])((?:(?:\(?\+?886\)?|00886)[\s.-]*[2-8]|\(?0[2-8]\)?)[\s.-]*[0-9]{3,4}[\s.-]*[0-9]{4})(?![0-9])/gu,
    )
  ) {
    add({
      owner: ownerAt(
        text,
        match.index ?? 0,
        undefined,
        options.perspective,
        defaultOwner,
      ),
      domain: "phone",
      relation: "has_phone",
      anchor: normalizePhone(match[1] ?? ""),
      polarity: polarityAt(text, match.index ?? 0),
      index: match.index ?? 0,
    });
  }
  for (
    const match of text.matchAll(
      /(?:^|[^0-9])(\+[1-9](?:[\s.-]*[0-9]){7,14})(?![0-9])/gu,
    )
  ) {
    add({
      owner: ownerAt(
        text,
        match.index ?? 0,
        undefined,
        options.perspective,
        defaultOwner,
      ),
      domain: "phone",
      relation: "has_phone",
      anchor: normalizePhone(match[1] ?? ""),
      polarity: polarityAt(text, match.index ?? 0),
      index: match.index ?? 0,
    });
  }
  for (
    const match of text.matchAll(
      /[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/giu,
    )
  ) {
    add({
      owner: ownerAt(
        text,
        match.index ?? 0,
        undefined,
        options.perspective,
        defaultOwner,
      ),
      domain: "email",
      relation: "has_email",
      anchor: normalizeBase(match[0] ?? ""),
      polarity: polarityAt(text, match.index ?? 0),
      index: match.index ?? 0,
    });
  }
  const implicitSocialPatterns: Array<{
    pattern: RegExp;
    actorIndex: number | null;
    anchorIndex: number;
  }> = [
    {
      pattern:
        /(?:line|ig|instagram|帳號|id)?\s*(?:加|搜尋|搜|找)\s*(我|妳|你|她)?\s*[:：]?\s*(@?[A-Z][A-Z0-9._-]{2,29})(?!@)(?=$|[\s，,。！？!?；;]|就|直接|晚點)/giu,
      actorIndex: 1,
      anchorIndex: 2,
    },
    {
      pattern:
        /(我|妳|你|她)(?:的)?(?:line|ig|instagram|帳號|id)?(?:是|用)\s*(@?[A-Z][A-Z0-9._-]{2,29})(?!@)(?=$|[\s，,。！？!?；;]|就|直接|晚點)/giu,
      actorIndex: 1,
      anchorIndex: 2,
    },
  ];
  for (const config of implicitSocialPatterns) {
    for (const match of text.matchAll(config.pattern)) {
      add({
        owner: ownerAt(
          text,
          match.index ?? 0,
          config.actorIndex === null
            ? undefined
            : match[config.actorIndex] || undefined,
          options.perspective,
          defaultOwner,
        ),
        domain: "social",
        relation: "has_social",
        anchor: normalizeBase(match[config.anchorIndex] ?? "").replace(
          /^@/u,
          "",
        ),
        polarity: polarityAt(text, match.index ?? 0),
        index: match.index ?? 0,
      });
    }
  }

  const locationPatterns = [
    {
      relation: "works_at_location" as const,
      domain: "work_location" as const,
      pattern: new RegExp(
        `(${ACTOR_TOKEN})(?:的)?(?:公司|工作地點)(?:也)?(?:是|在)\\s*(${PLACE_VALUE})${VALUE_END}`,
        "gu",
      ),
    },
    {
      relation: "works_at_location" as const,
      domain: "work_location" as const,
      pattern: new RegExp(
        `(${ACTOR_TOKEN})(?:平常|目前|現在|也|都){0,3}在\\s*(${PLACE_VALUE})\\s*工作`,
        "gu",
      ),
    },
    {
      relation: "is_at" as const,
      domain: "current_location" as const,
      pattern: new RegExp(
        `(${ACTOR_TOKEN})(?:現在|目前|剛好|也|都){0,3}在\\s*(${PLACE_VALUE})${VALUE_END}`,
        "gu",
      ),
    },
    {
      relation: "works_at_location" as const,
      domain: "work_location" as const,
      pattern: new RegExp(
        `(?:^|[，,])(?:剛好|目前|現在|也|都)?在\\s*(${PLACE_VALUE})\\s*工作`,
        "gu",
      ),
      implicit: true,
    },
  ];
  for (const config of locationPatterns) {
    for (const match of text.matchAll(config.pattern)) {
      const actorToken = "implicit" in config && config.implicit
        ? undefined
        : match[1];
      const rawPlace = "implicit" in config && config.implicit
        ? match[1]
        : match[2];
      const anchor = normalizePlace(rawPlace ?? "");
      if (!looksLikeLocationAnchor(anchor)) continue;
      add({
        owner: ownerAt(
          text,
          match.index ?? 0,
          actorToken,
          options.perspective,
          defaultOwner,
        ),
        domain: config.domain,
        relation: config.relation,
        anchor,
        polarity: polarityAt(text, match.index ?? 0),
        index: match.index ?? 0,
      });
    }
  }

  for (
    const match of text.matchAll(
      new RegExp(
        `(${ACTOR_TOKEN}).{0,12}?(上週|上禮拜|上星期|去年|前年|前天|昨天|${NUMBER_TOKEN}(?:週|個月|年)前).{0,8}?(?:見過|碰過|遇過|認識)\\s*(${HAN_VALUE})${VALUE_END}`,
        "gu",
      ),
    )
  ) {
    add({
      owner: ownerAt(
        text,
        match.index ?? 0,
        match[1],
        options.perspective,
        defaultOwner,
      ),
      domain: "history",
      relation: "met",
      anchor: `${normalizeSchedule(match[2] ?? "")}:${
        normalizeAnchor(match[3] ?? "")
      }`,
      polarity: polarityAt(text, match.index ?? 0),
      index: match.index ?? 0,
    });
  }

  const genericPlaces = new Set([
    "車站",
    "捷運站",
    "火車站",
    "高鐵站",
    "公車站",
    "路上",
    "記路",
    "問路",
    "走路",
    "迷路",
    "街上",
    "市區",
    "公園",
    "山上",
    "山下",
    "公司",
    "學校",
    "家裡",
    "夜市",
    "商圈",
    "咖啡店",
    "餐廳",
    "酒吧",
    "爬山",
    "逛夜市",
  ]);
  const namedPlacePatterns = [
    /(?:^|[\s，,。！？!?；;：:\p{S}])(?:在|去|到|位於|路過|靠近|就在)?\s*([\p{Script=Han}0-9]{2,40}(?:路|街|大道)[\p{Script=Han}0-9]{0,20}(?:號|樓))/gu,
    /(?:^|[\s，,。！？!?；;：:\p{S}])(?:在|去|到|位於|路過|靠近|就在)?\s*([\p{Script=Han}A-Za-z0-9·・]{1,24}(?:站|路|街|巷|區|市|縣|鄉|鎮|村|里|町|山|公園|夜市|商圈|碼頭|廣場|大樓|中心|101))/gu,
    /(?:在|去|到|位於|路過|靠近|說出|說|回答|地點|位置|地址)\s*([\p{Script=Han}A-Za-z0-9·・]{1,24}(?:站|路|街|巷|區|市|縣|鄉|鎮|村|里|町|山|公園|夜市|商圈|碼頭|廣場|大樓|中心|101))/gu,
  ];
  for (const pattern of namedPlacePatterns) {
    for (const match of text.matchAll(pattern)) {
      if (
        /^(?:開場仍在|只停在).+(?:生活)?資訊交換$/u.test(
          localClauseAt(text, match.index ?? 0).trim(),
        )
      ) {
        continue;
      }
      const anchor = normalizePlace(
        (match[1] ?? "").replace(
          /^(?:(?:今天|明天|後天|昨天|前天|上週|這週|下週)(?:早上|中午|下午|晚上)?(?:也)?(?:在|到|去)|(?:在|到|去))/u,
          "",
        ),
      );
      const following = text.slice(
        (match.index ?? 0) + (match[0]?.length ?? 0),
        (match.index ?? 0) + (match[0]?.length ?? 0) + 2,
      );
      if (
        !anchor || genericPlaces.has(anchor) ||
        anchor.endsWith("同鄉") ||
        /^(?:去|到|在|逛|走|想|要|喝|吃|看|找)/u.test(anchor) ||
        /(?:我|妳|你|她|我們|是|也|家鄉|老家|住處|生活圈)/u.test(anchor) ||
        /^(?:明確|直接|先|一起)/u.test(anchor) ||
        /(?:哪|哪裡|哪兒|什麼|幾)/u.test(anchor) ||
        (anchor.endsWith("站") && /^在/u.test(following))
      ) continue;
      add({
        owner: "world",
        domain: "venue",
        relation: "located_at",
        anchor,
        polarity: "positive",
        index: match.index ?? 0,
      });
    }
  }

  for (
    const match of text.matchAll(
      /(?:店|店家|咖啡店|餐廳|酒吧|那間|這間).{0,8}?(?:是|叫|名為|稱作)\s*[「『“"]?([^」』”"，,。！？!?；;]{2,30})/gu,
    )
  ) {
    add({
      owner: "world",
      domain: "venue",
      relation: "venue_named",
      anchor: normalizeAnchor(match[1] ?? ""),
      polarity: "positive",
      index: match.index ?? 0,
    });
  }

  const deduped = new Map<string, HintFactClaim>();
  for (const claim of claims) {
    if (claim.owner === "unknown" || !claim.anchor) continue;
    deduped.set(factKey(claim), claim);
  }
  return [...deduped.values()];
}

function memoryDefaultOwner(text: string): HintFactOwner {
  if (/(?:我們|彼此|雙方|兩人|共同)/u.test(text)) return "shared";
  if (/(?:使用者|男方|\buser\b)/iu.test(text)) return "user";
  if (/(?:她|對方|女生|\b(?:she|assistant)\b)/iu.test(text)) {
    return "partner";
  }
  return "unknown";
}

export function buildHintFactContext(input: {
  turns?: readonly PracticeTurn[];
  factualEvidence?: readonly string[];
  sharedFactualEvidence?: readonly string[];
  partnerFactualEvidence?: readonly string[];
  trustedFactClaims?: readonly HintFactClaim[];
}): HintFactContext {
  const trustedClaims = [...(input.trustedFactClaims ?? [])];
  const latestPartnerText =
    [...(input.turns ?? [])].reverse().find((turn) => turn.role === "ai")
      ?.text ?? "";
  const trustedContext: HintFactContext = {
    claims: trustedClaims,
    latestPartnerText,
  };
  const claims: HintFactClaim[] = [...trustedClaims];
  for (const turn of input.turns ?? []) {
    claims.push(...extractHintFactClaims({
      text: turn.text,
      perspective: turn.role === "user" ? "user_turn" : "partner_turn",
      provenance: turn.role === "user" ? "user_turn" : "partner_turn",
      defaultOwner: turn.role === "user" ? "user" : "partner",
    }));
    if (turn.role === "user") {
      claims.push(
        ...inferClaimsFromKnownAnchors({
          text: turn.text,
          field: "reply",
          context: trustedContext,
        }).filter((claim) => claim.owner === "user").map((claim) => ({
          ...claim,
          provenance: "user_turn" as const,
        })),
      );
    }
  }
  for (
    const evidence of [
      ...(input.factualEvidence ?? []),
      ...(input.sharedFactualEvidence ?? []),
    ]
  ) {
    claims.push(...extractHintFactClaims({
      text: evidence,
      perspective: "memory",
      provenance: "memory",
      defaultOwner: memoryDefaultOwner(evidence),
    }));
  }
  for (const evidence of input.partnerFactualEvidence ?? []) {
    claims.push(...extractHintFactClaims({
      text: evidence,
      perspective: "partner_context",
      provenance: "partner_context",
      defaultOwner: "partner",
    }));
  }
  const deduped = new Map<string, HintFactClaim>();
  for (const claim of claims) deduped.set(factKey(claim), claim);
  return {
    claims: [...deduped.values()],
    latestPartnerText,
  };
}

export function partnerFactClaimsFromProfile(
  profile: PracticeProfile,
): HintFactClaim[] {
  const partnerClaim = (
    input: Omit<HintFactClaim, "owner" | "polarity" | "provenance">,
  ): HintFactClaim => ({
    owner: "partner",
    polarity: "positive",
    provenance: "partner_context",
    ...input,
  });
  const claims: HintFactClaim[] = [
    partnerClaim({
      domain: "name",
      relation: "is_named",
      anchor: normalizeAnchor(profile.girl.displayName),
    }),
    partnerClaim({
      domain: "age",
      relation: "is_age",
      anchor: String(profile.girl.age),
    }),
    partnerClaim({
      domain: "residence",
      relation: "lives_in",
      anchor: normalizePlace(profile.girl.city),
    }),
    partnerClaim({
      domain: "profession",
      relation: "works_as",
      anchor: normalizeAnchor(profile.girl.professionLabel),
    }),
    ...profile.girl.reactionModel.likes.map((value) =>
      partnerClaim({
        domain: "preference" as const,
        relation: "likes" as const,
        anchor: normalizePreference(value),
      })
    ),
    ...profile.girl.interestTags.map((value) =>
      partnerClaim({
        domain: "preference" as const,
        relation: "likes" as const,
        anchor: normalizePreference(value),
      })
    ),
    ...profile.girl.lifestyleTags.map((value) =>
      partnerClaim({
        domain: "lifestyle" as const,
        relation: "does_activity" as const,
        anchor: normalizeAnchor(value),
      })
    ),
  ];
  const deduped = new Map<string, HintFactClaim>();
  for (const claim of claims) {
    if (claim.anchor) deduped.set(factKey(claim), claim);
  }
  return [...deduped.values()];
}

function sameFactIdentity(
  output: HintFactClaim,
  evidence: HintFactClaim,
): boolean {
  if (output.domain !== evidence.domain || output.anchor !== evidence.anchor) {
    return false;
  }
  if (output.quantity !== undefined) {
    return evidence.quantity === output.quantity;
  }
  return true;
}

function relationSupports(
  output: HintFactClaim,
  evidence: HintFactClaim,
): boolean {
  if (output.relation === evidence.relation) return true;
  if (output.domain === "venue" && evidence.domain === "venue") return true;
  if (output.domain === "preference") {
    return output.relation === "likes" &&
      (evidence.relation === "favorite" || evidence.relation === "hobby");
  }
  return false;
}

function supportedBy(
  output: HintFactClaim,
  evidence: readonly HintFactClaim[],
  owners: readonly HintFactOwner[],
): boolean {
  return evidence.some((claim) =>
    owners.includes(claim.owner) && sameFactIdentity(output, claim) &&
    relationSupports(output, claim) && claim.polarity === output.polarity
  );
}

function hasConflictingOwnClaim(
  output: HintFactClaim,
  evidence: readonly HintFactClaim[],
  owners: readonly HintFactOwner[],
): boolean {
  return evidence.some((claim) =>
    owners.includes(claim.owner) && sameFactIdentity(output, claim) &&
    (claim.polarity !== output.polarity || !relationSupports(output, claim))
  );
}

function anchorCueMatches(domain: HintFactDomain, clause: string): boolean {
  switch (domain) {
    case "age":
      return /(?:歲|年紀|年齡)/u.test(clause);
    case "name":
      return /(?:名字|名叫|叫|喊|稱呼|是)/u.test(clause);
    case "profession":
      return /(?:工作|職業|任職|做|當|是)/u.test(clause);
    case "school":
      return /(?:讀|念|就讀|母校|校友|畢業)/u.test(clause);
    case "residence":
      return /(?:住|住處|生活圈|活動範圍|基地|來自|老家|家鄉|人)/u
        .test(clause);
    case "work_location":
      return /(?:公司|工作地點|工作|上班)/u.test(clause);
    case "current_location":
      return /(?:現在|目前|人在|待在|剛到)/u.test(clause);
    case "phone":
      return /(?:電話|手機|號碼|打給|聯絡|找我)/u.test(clause);
    case "email":
      return /(?:email|e-mail|信箱|郵件|寄給|聯絡)/iu.test(clause);
    case "social":
      return /(?:line|ig|instagram|帳號|id|加我|搜尋|搜|找到我|我用)/iu
        .test(clause);
    case "schedule":
      return new RegExp(SCHEDULE_STATUS, "u").test(clause);
    case "history":
      return /(?:見過|碰過|遇過|認識)/u.test(clause);
    case "pet":
      return /(?:養|我家|家裡|隻|寵物)/u.test(clause);
    case "family":
      return new RegExp(`(?:有|我的|我家|${RELATIVE})`, "u").test(clause);
    case "preference":
      return /(?:喜歡|愛|最愛|控|派|粉|愛好者|同好|興趣|嗜好)/u.test(
        clause,
      );
    case "lifestyle":
      return /(?:平常|通常|常常|每天|每週|週末|下班|會|都|也|跑|去|做|補眠|聚會|活動|生活)/u
        .test(clause);
    case "venue":
      return /(?:店|店家|咖啡店|餐廳|酒吧|叫|名為)/u.test(clause);
  }
}

function ownerNearAnchor(
  text: string,
  index: number,
  perspective: "reply" | "coaching",
): HintFactOwner {
  const clause = localClauseAt(text, index);
  const clauseStart = text.lastIndexOf(clause, index);
  const localIndex = Math.max(0, index - Math.max(0, clauseStart));
  const actorsBefore = [
    ...clause.slice(0, localIndex + 1).matchAll(
      new RegExp(`(${ACTOR_TOKEN})`, "gu"),
    ),
  ];
  const preceding = actorsBefore.at(-1)?.[1];
  if (preceding) {
    return ownerAt(
      text,
      index,
      preceding,
      perspective,
      perspective === "reply" ? "user" : "unknown",
    );
  }
  const following = clause.slice(localIndex).match(
    new RegExp(`.{0,12}?(${ACTOR_TOKEN})`, "u"),
  )?.[1];
  const explicitFollowing = following
    ? explicitOwnerForToken(following, perspective)
    : null;
  return explicitFollowing ?? (perspective === "reply" ? "user" : "unknown");
}

function knownAnchorOccurrences(
  text: string,
  evidence: HintFactClaim,
): number[] {
  const normalizedText = text.normalize("NFKC").replace(/臺/gu, "台")
    .toLowerCase();
  const occurrences = new Set<number>();
  const rawAnchor = evidence.anchor.toLowerCase();
  if (rawAnchor) {
    let cursor = normalizedText.indexOf(rawAnchor);
    while (cursor >= 0) {
      occurrences.add(cursor);
      cursor = normalizedText.indexOf(rawAnchor, cursor + rawAnchor.length);
    }
  }
  if (evidence.domain === "age" && /^\d+$/u.test(evidence.anchor)) {
    for (
      const match of text.matchAll(
        new RegExp(`(${NUMBER_TOKEN})(?=\\s*歲)`, "gu"),
      )
    ) {
      if (chineseNumberValue(match[1] ?? "") === Number(evidence.anchor)) {
        occurrences.add(match.index ?? 0);
      }
    }
  }
  if (evidence.domain === "schedule") {
    for (const match of text.matchAll(new RegExp(`(${SCHEDULE_TIME})`, "gu"))) {
      if (normalizeSchedule(match[1] ?? "") === evidence.anchor) {
        occurrences.add(match.index ?? 0);
      }
    }
  }
  if (evidence.domain === "phone") {
    for (
      const match of text.matchAll(
        /(?:\+?886|00886|0)?(?:[\s().-]*[0-9]){8,12}/gu,
      )
    ) {
      if (normalizePhone(match[0]) === evidence.anchor) {
        occurrences.add(match.index ?? 0);
      }
    }
  }
  return [...occurrences].sort((a, b) => a - b);
}

function inferClaimsFromKnownAnchors(input: {
  text: string;
  field: "reply" | "coaching";
  context: HintFactContext;
}): HintFactClaim[] {
  const text = input.text.normalize("NFKC").replace(/臺/gu, "台");
  const claims: HintFactClaim[] = [];
  for (const evidence of input.context.claims) {
    if (!evidence.anchor || evidence.owner === "unknown") continue;
    const rawAnchor = evidence.anchor.toLowerCase();
    if (
      !rawAnchor || /[:@]/u.test(rawAnchor) && evidence.domain === "history"
    ) {
      continue;
    }
    for (const cursor of knownAnchorOccurrences(text, evidence)) {
      const clause = localClauseAt(text, cursor);
      const hasExplicitActor = new RegExp(ACTOR_TOKEN, "u").test(clause);
      const looksLikeImplicitUserClaim = input.field === "reply" &&
        /^(?:也|同樣|剛好|目前|現在|其實)?(?:在|住|讀|念|做|當|是|有|養|來自|以)/u
          .test(clause.trim());
      const owner = ownerNearAnchor(text, cursor, input.field);
      const anchoredOwner = evidence.owner === "world" ||
          evidence.owner === "third_party"
        ? evidence.owner
        : evidence.owner === "partner" && !hasExplicitActor &&
            !looksLikeImplicitUserClaim
        ? "partner"
        : owner;
      if (
        !isQuestionOrCondition(text, cursor, anchoredOwner) &&
        !isSuppressedQuotedClaim(
          text,
          cursor,
          input.context.latestPartnerText,
        ) &&
        anchorCueMatches(evidence.domain, clause)
      ) {
        const isPartnerReaction = anchoredOwner === "user" &&
          evidence.owner === "partner" &&
          /(?:我|我們)(?:也)?(?:有)?(?:被|替|為|跟著|聽|看|想幫|好奇)/u
            .test(clause) &&
          !/(?:我家|我的|我養|我有|我是|我住|我讀|我念|我叫|我用)/u
            .test(clause);
        if (anchoredOwner !== "unknown" && !isPartnerReaction) {
          claims.push({
            ...evidence,
            owner: anchoredOwner,
            polarity: polarityAt(text, cursor),
            provenance: input.field === "reply"
              ? "generated_reply"
              : "generated_coaching",
          });
        }
      }
    }
  }
  const deduped = new Map<string, HintFactClaim>();
  for (const claim of claims) deduped.set(factKey(claim), claim);
  return [...deduped.values()];
}

function isNegatedCoreference(text: string, index: number): boolean {
  const prefix = text.slice(Math.max(0, index - 24), index);
  return /(?:不要|別|避免|不可|不能|不得).{0,16}(?:冒認|假裝|硬湊|亂湊|說成|寫成|當成|視為|說|寫|回)$/u
    .test(prefix) ||
    /不(?:替.{0,10})?(?:冒認|假裝|硬湊|亂湊|說成|寫成|當成|視為)$/u
      .test(prefix) ||
    /(?:未(?:形成|建立|證明|確認)|沒有(?:證據|根據)?)$/u.test(prefix);
}

function inferCoreferenceClaims(input: {
  text: string;
  field: "reply" | "coaching";
  context: HintFactContext;
}): HintFactClaim[] {
  const text = input.text.normalize("NFKC").replace(/臺/gu, "台");
  const provenance: HintFactProvenance = input.field === "reply"
    ? "generated_reply"
    : "generated_coaching";
  const claims: HintFactClaim[] = [];
  const evidenceFor = (
    domains: readonly HintFactDomain[],
  ): HintFactClaim | null => {
    const candidates = input.context.claims.filter((claim) =>
      domains.includes(claim.domain) && claim.polarity === "positive" &&
      (claim.owner === "user" || claim.owner === "partner" ||
        claim.owner === "shared")
    );
    const mentioned = candidates.filter((claim) =>
      knownAnchorOccurrences(text, claim).length > 0
    );
    return mentioned.at(-1) ?? candidates.at(-1) ?? null;
  };
  const addFromEvidence = (
    evidence: HintFactClaim | null,
    owner: HintFactOwner,
    index: number,
  ) => {
    if (
      !evidence || isQuestionOrCondition(text, index, owner) ||
      isSuppressedQuotedClaim(text, index, input.context.latestPartnerText) ||
      isNegatedCoreference(text, index)
    ) {
      return;
    }
    claims.push({
      ...evidence,
      owner,
      quantity: evidence.domain === "pet" || evidence.domain === "family"
        ? undefined
        : evidence.quantity,
      polarity: polarityAt(text, index),
      provenance,
    });
  };

  const commonalityPatterns: Array<{
    pattern: RegExp;
    domains: readonly HintFactDomain[];
    requireProfessionContext?: boolean;
    personalCue?: "pair" | "school" | "pet" | "preference";
  }> = [
    {
      pattern: /同名(?!專輯|作品|電影|歌曲|書|節目|品牌|角色)/u,
      domains: ["name"],
      personalCue: "pair",
    },
    {
      pattern: /(?:同年(?!上映|推出|出版|發行)|同歲|同一屆)/u,
      domains: ["age"],
      personalCue: "pair",
    },
    {
      pattern: /(?:同校|同一間學校)/u,
      domains: ["school"],
      personalCue: "school",
    },
    {
      pattern: /(?:同行業|同職業|同業|同行)/u,
      domains: ["profession"],
      requireProfessionContext: true,
    },
    {
      pattern: /(?:同鄉|同城)/u,
      domains: ["residence"],
      personalCue: "pair",
    },
    {
      pattern: /(?:貓奴|狗奴|鏟屎官)(?:同盟|聯盟)?/u,
      domains: ["pet"],
      personalCue: "pet",
    },
    {
      pattern: /同好/u,
      domains: ["preference"],
      personalCue: "preference",
    },
    {
      pattern: /(?:都有手足|手足同盟)/u,
      domains: ["family"],
      personalCue: "pair",
    },
    {
      pattern: /(?:那次|那回).{0,10}(?:我們|彼此|雙方).{0,8}(?:都)?在場/u,
      domains: ["history"],
    },
    {
      pattern:
        /(?:我們|彼此|雙方).{0,8}(?:都|也)?(?:在)?(?:附近|同一帶|同一區)/u,
      domains: ["current_location", "work_location", "residence"],
    },
  ];
  for (const config of commonalityPatterns) {
    const match = config.pattern.exec(text);
    if (!match) continue;
    const evidence = evidenceFor(config.domains);
    const clause = localClauseAt(text, match.index);
    const clauseStart = text.lastIndexOf(clause, match.index);
    const localMatchIndex = Math.max(0, match.index - Math.max(0, clauseStart));
    const prefix = clause.slice(0, localMatchIndex);
    const anchorMentioned = evidence !== null &&
      knownAnchorOccurrences(text, evidence).length > 0;
    const personalPair = /(?:我們|彼此|雙方|我也)/u.test(clause) ||
      /(?:原來|居然|竟然|沒想到).{0,8}(?:我們|彼此|雙方)?/u.test(
        prefix,
      ) ||
      /(?:我.{0,10}(?:妳|你|她)|(?:妳|你|她).{0,10}我)/u.test(prefix);
    const linkedThirdParty =
      /(?:她|妳|你)(?:跟|和|與|的).{0,12}$/u.test(prefix) &&
      !/(?:我|我們|彼此|雙方)/u.test(prefix);
    if (linkedThirdParty) continue;
    if (config.personalCue === "pair" && !personalPair) continue;
    if (
      config.personalCue === "school" && !personalPair &&
      !(anchorMentioned && /同校(?:學妹|學姊|學長|學弟|同學)?/u.test(match[0]))
    ) {
      continue;
    }
    if (
      config.personalCue === "pet" && !personalPair &&
      !/(?:同盟|聯盟|我也|都是|加一)/u.test(clause)
    ) {
      continue;
    }
    if (
      config.personalCue === "preference" && !personalPair &&
      !/(?:我也|加一|同盟|聯盟)/u.test(clause)
    ) {
      continue;
    }
    if (
      config.requireProfessionContext && evidence &&
      !anchorMentioned &&
      !/(?:同行業|同職業|同業)/u.test(match[0])
    ) {
      continue;
    }
    addFromEvidence(evidence, "shared", match.index);
  }

  const scheduleReference =
    /(?:(?:那個|這個|同一個)?(?:時段|時間)|那時|這時).{0,16}(?:我(?:這邊)?(?:也)?(?:行|可以|能|有空|排得開|方便)|我也能)/u
      .exec(text);
  if (scheduleReference) {
    addFromEvidence(
      evidenceFor(["schedule"]),
      "user",
      scheduleReference.index,
    );
  }

  const socialReference =
    /(?:line|ig|instagram|帳號|id|這串|那串|同一串).{0,20}(?:同一串|同一個|我(?:這邊)?也(?:用|收得到|找得到)|也是我的|找到我)/iu
      .exec(text);
  if (socialReference) {
    addFromEvidence(
      evidenceFor(["social"]),
      "user",
      socialReference.index,
    );
  }

  const deduped = new Map<string, HintFactClaim>();
  for (const claim of claims) deduped.set(factKey(claim), claim);
  return [...deduped.values()];
}

function contextualDirectAnswerClaims(input: {
  text: string;
  field: "reply" | "coaching";
  context: HintFactContext;
}): HintFactClaim[] {
  const latest = input.context.latestPartnerText;
  const text = input.text.normalize("NFKC").replace(/臺/gu, "台");
  const provenance: HintFactProvenance = input.field === "reply"
    ? "generated_reply"
    : "generated_coaching";
  const claims: HintFactClaim[] = [];
  const add = (claim: Omit<HintFactClaim, "provenance" | "polarity">) => {
    claims.push({ ...claim, polarity: "positive", provenance });
  };

  const asksPlace =
    /(?:在哪|哪裡|哪兒|哪間|店名|什麼店|位置|地址|怎麼去)|(?:店|店家|咖啡店|餐廳|酒吧|地方|地點).{0,8}(?:叫什麼|什麼名字)|叫什麼(?:店|餐廳|酒吧)/u
      .test(latest);
  if (asksPlace) {
    const safeDirectAnswers = new Set([
      "附近",
      "那附近",
      "轉角",
      "轉角那間",
      "巷口",
      "巷口那間",
      "公司",
      "公司旁邊",
      "學校",
      "學校附近",
      "家裡",
      "捷運站",
      "捷運站附近",
      "車站",
      "憑感覺",
      "不知道",
      "不記得",
      "忘了",
      "保密",
      "秘密",
      "猜猜看",
      "妳猜",
      "晚點揭曉",
      "等等再說",
    ]);
    const candidatePatterns = [
      /[「『“"（(【《〈〔\[]\s*([^」』”"）)】》〉〕\]]{2,60}?)\s*[」』”"）)】》〉〕\]]/gu,
      /(?:答案|店名|咖啡店名|餐廳名|酒吧名|店家|地址|地點|位置)(?:是|叫|為|名為|稱作|[：:])\s*([\p{L}\p{N}·・._'’\-–—／/\s]{2,60}?)(?=[，,。！？!?；;]|$)/gu,
      /(?:名為|稱作|叫做|那間(?:店)?(?:是|叫)|這間(?:店)?(?:是|叫))\s*([\p{L}\p{N}·・._'’\-–—／/\s]{2,40}?)(?=[，,。！？!?；;]|$)/gu,
      /(?:^|[，,。！？!?；;：:#＃\s\p{S}])([\p{L}\p{N}·・._'’\-–—／/]{2,30}(?:\s+[A-Za-z0-9·・._'’\-–—]+){0,3}?)(?=\s*(?:啦|啊|呀|喔|欸|附近|旁邊|正對面|對面|一帶|巷口|路口|那邊|那家|那間|這家|這間|那裡|[，,](?:妳|你)(?:應該|一定|可能|搞不好|大概)?(?:知道|聽過|去過|記得)))/gu,
    ];
    for (const pattern of candidatePatterns) {
      for (const match of text.matchAll(pattern)) {
        const anchor = normalizeAnchor(match[1] ?? "")
          .replace(/^(?:就是|是|叫|在|去|到|位於|靠近|就在)/u, "")
          .replace(
            /^(?:(?:昨天|前天|上週|上星期|上禮拜|去年|前年|前幾天|[0-9一二三四五六七八九十兩]+(?:週|個月|年)前)?在)/u,
            "",
          )
          .replace(/(?:見過|碰過|遇過|認識).*$/u, "")
          .replace(/(?:附近|旁邊|正對面|對面|一帶|巷口|路口)$/u, "");
        if (
          anchor.length < 2 || safeDirectAnswers.has(anchor) ||
          /(?:我|妳|你|她|我們|想|努力|回想|記憶|招供|逗|翻|問|找|給|知道|記得|忘)/u
            .test(anchor) ||
          /(?:不知道|不記得|忘了|沒記住|先確認|查一下|問一下)/u.test(
            anchor,
          )
        ) continue;
        add({
          owner: "world",
          domain: "venue",
          relation: "venue_named",
          anchor,
        });
      }
    }
  }

  const asksPerson =
    /(?:誰|哪位|哪個人|什麼人|同行|叫什麼名字|名字叫什麼|收件人)/u
      .test(latest);
  if (asksPerson) {
    const personPatterns = [
      /(?:那|這)(?:個人)?(?:就是|是|叫)\s*([\p{Script=Han}A-Za-z·・]{2,20})(?=[，,。！？!?；;\s]|$)/gu,
      /(?:^|[，,：:\s])(?:就是|是)?\s*([\p{Script=Han}A-Za-z·・]{2,12}?)(?:啦|啊|呀|喔|欸)?[。！？!?]?\s*$/gu,
    ];
    for (const pattern of personPatterns) {
      for (const match of text.matchAll(pattern)) {
        const anchor = normalizeAnchor(match[1] ?? "")
          .replace(
            /^(?:(?:他|她)?(?:的)?名字(?:是|叫)|(?:他|她)(?:是|叫))/u,
            "",
          )
          .replace(/^(?:(?:之前|前面|剛才)(?:有)?(?:提過|說過|聊過)的)/u, "");
        if (
          !looksLikePersonReference(anchor) ||
          /(?:不知道|不記得|確認|問一下|保密)/u.test(anchor)
        ) continue;
        add({
          owner: "third_party",
          domain: "name",
          relation: "is_named",
          anchor,
        });
      }
    }
  }

  const asksHistory =
    /(?:什麼時候|哪年|哪天|何時|幾年前|多久前).{0,8}(?:見過|認識|碰過|遇過)?|(?:見過|認識|碰過|遇過).{0,8}(?:什麼時候|哪年|哪天|何時)/u
      .test(latest);
  if (asksHistory) {
    for (const match of text.matchAll(new RegExp(`(${HISTORY_TIME})`, "gu"))) {
      add({
        owner: "shared",
        domain: "history",
        relation: "met",
        anchor: normalizeSchedule(match[1] ?? ""),
      });
    }
  }

  if (/(?:電話|手機|市話|號碼|幾號|分機)/u.test(latest)) {
    for (
      const match of text.matchAll(
        /分機(?:號碼)?(?:是|為|[：:])?\s*([0-9]{3,6})(?![0-9])/gu,
      )
    ) {
      add({
        owner: input.field === "reply" ? "user" : "unknown",
        domain: "phone",
        relation: "has_phone",
        anchor: `ext${match[1] ?? ""}`,
      });
    }
  }

  return claims;
}

export function assertHintFactClaimsSupported(input: {
  text: string;
  field: "reply" | "coaching";
  context: HintFactContext;
  errorCode?: string;
}): void {
  const errorCode = input.errorCode ??
    "hint_quality_invalid_unsupported_detail";
  const unsupported = (claim: HintFactClaim): Error =>
    new Error(
      `${errorCode}:${claim.owner}:${claim.domain}:${claim.relation}`,
    );
  const outputClaimsByKey = new Map<string, HintFactClaim>();
  for (
    const claim of [
      ...extractHintFactClaims({
        text: input.text,
        perspective: input.field,
        provenance: input.field === "reply"
          ? "generated_reply"
          : "generated_coaching",
        defaultOwner: input.field === "reply" ? "user" : "unknown",
        partnerQuoteSource: input.context.latestPartnerText,
      }),
      ...inferClaimsFromKnownAnchors(input),
      ...inferCoreferenceClaims(input),
      ...contextualDirectAnswerClaims(input),
    ]
  ) {
    outputClaimsByKey.set(factKey(claim), claim);
  }
  const outputClaims = [...outputClaimsByKey.values()];

  for (const output of outputClaims) {
    if (output.owner === "world" || output.owner === "third_party") {
      const supportedWorld = supportedBy(
        output,
        input.context.claims,
        [output.owner, "world", "shared"],
      );
      if (ALWAYS_REQUIRE_SUPPORT.has(output.domain) && !supportedWorld) {
        throw unsupported(output);
      }
      continue;
    }
    if (output.owner === "unknown") continue;

    if (output.owner === "shared") {
      const explicitShared = supportedBy(output, input.context.claims, [
        "shared",
      ]);
      const bothSides = supportedBy(output, input.context.claims, ["user"]) &&
        supportedBy(output, input.context.claims, ["partner"]);
      if (!explicitShared && !bothSides) {
        throw unsupported(output);
      }
      continue;
    }

    const ownOwners: HintFactOwner[] = [output.owner, "shared"];
    if (supportedBy(output, input.context.claims, ownOwners)) continue;
    if (hasConflictingOwnClaim(output, input.context.claims, ownOwners)) {
      throw unsupported(output);
    }

    const oppositeOwner: HintFactOwner = output.owner === "user"
      ? "partner"
      : "user";
    const oppositeHasSameFact = input.context.claims.some((claim) =>
      claim.owner === oppositeOwner && sameFactIdentity(output, claim)
    );
    if (oppositeHasSameFact || ALWAYS_REQUIRE_SUPPORT.has(output.domain)) {
      throw unsupported(output);
    }
  }
}
