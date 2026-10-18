// 新話題的共用部分（2026-10-01 進階路徑實作規格 §1／§4）：先問兩題的答案
// （topicContext）驗證、「這次的局面」那段的規則、紅燈收尾、今天的日期、
// telemetry 與品質稽核。提示詞本身在 new_topic_slots.ts（結構刀，ADR #53）；
// v2.3／v2.4 的整份提示詞與隨機角度 2026-10-09 移除。
//
// 純 helper：不 import server、不碰 DB。提示詞裡只出現中文標籤，絕不出現
// enum 代碼；素材原文不進 log。

import { isPlainObject } from "../_shared/quota.ts";
import {
  allowsNewTopicSharedFrame,
  type NewTopicModelTopic,
  type NewTopicSituation,
} from "./new_topic_payload.ts";
import { graphemeLength } from "./opener_stage.ts";

/**
 * 目前 production 新話題提示詞的版本（結構刀，ADR #53，new_topic_slots.ts）。
 * telemetry、ai_logs 與失敗事件都記這個。
 */
export const NEW_TOPIC_PROMPT_VERSION = "new-topic-slots-v1";
export const NEW_TOPIC_MATERIAL_TEXT_MAX_GRAPHEMES = 150;
/** grapheme 上限擋不住一個字疊幾百個組合符號／ZWJ：另外以 UTF-16 長度封頂。 */
export const NEW_TOPIC_MATERIAL_TEXT_MAX_CODE_UNITS = 1500;
/**
 * 格式字元（零寬、雙向控制、軟連字號…）會把粗俗詞拆開躲過擋字：一律拿掉。
 * 只留夾在兩個 emoji 之間的 ZWJ（👨‍👩‍👧 這類組合），拿掉會把一個 emoji
 * 拆成好幾個、grapheme 數變多，與 App 的計數對不上；emoji 本身就隔開文字，
 * 留著不會幫忙拆詞。看起來空白的填充字（韓文填充字、點字空白）一併拿掉。
 * 組合符號（Mn）不在此列（規格 §9 已接受風險）。
 */
const FORMAT_CHARS =
  /(?<![\p{Extended_Pictographic}\p{Emoji_Modifier}\u{FE0F}])\u{200D}|\u{200D}(?!\p{Extended_Pictographic})|[^\P{Cf}\u{200D}]|[\u{115F}\u{1160}\u{3164}\u{FFA0}\u{2800}]/gu;

export const NEW_TOPIC_COLD_DURATIONS = [
  "days",
  "weeks",
  "month_plus",
] as const;
export const NEW_TOPIC_COLD_STOPS = [
  "faded",
  "she_no_reply",
  "i_no_reply",
  "she_cold",
] as const;
export const NEW_TOPIC_ENGAGEMENTS = ["green", "yellow", "red"] as const;
export const NEW_TOPIC_MATERIAL_KINDS = [
  "past_topic",
  "trigger",
  "my_story",
  "inside_joke",
  "none",
] as const;

export type NewTopicColdDuration = typeof NEW_TOPIC_COLD_DURATIONS[number];
export type NewTopicColdStop = typeof NEW_TOPIC_COLD_STOPS[number];
export type NewTopicEngagement = typeof NEW_TOPIC_ENGAGEMENTS[number];
export type NewTopicMaterialKind = typeof NEW_TOPIC_MATERIAL_KINDS[number];

/** 正規化後的進階答案；缺席一律是 null，materialText 已 trim＋收合空白。 */
export type NewTopicTopicContext = {
  coldDuration: NewTopicColdDuration | null;
  coldStop: NewTopicColdStop | null;
  engagement: NewTopicEngagement | null;
  materialKind: NewTopicMaterialKind | null;
  materialText: string | null;
};

export type NewTopicTopicContextSanitizeResult =
  | { ok: true; topicContext: NewTopicTopicContext | null }
  | { ok: false; reason: string };

const TOPIC_CONTEXT_KEYS = new Set([
  "coldDuration",
  "coldStop",
  "engagement",
  "materialKind",
  "materialText",
]);

/** null＝缺席；false＝值不在清單。 */
function enumOrNull<T extends string>(
  value: unknown,
  allowed: readonly T[],
): T | null | false {
  if (value === undefined || value === null) return null;
  return (allowed as readonly unknown[]).includes(value) ? value as T : false;
}

/**
 * topicContext 驗證（規格 §1）：全部在 claim、限流、模型、扣費之前；
 * 失敗由呼叫端回 400 NEW_TOPIC_REQUEST_INVALID。超長不截斷。
 */
export function sanitizeNewTopicTopicContext(
  raw: unknown,
  situation: NewTopicSituation | null,
): NewTopicTopicContextSanitizeResult {
  const fail = (reason: string) => ({ ok: false as const, reason });
  if (raw === undefined || raw === null) {
    return { ok: true, topicContext: null };
  }
  if (!isPlainObject(raw)) return fail("topic_context_invalid");
  for (const key of Object.keys(raw)) {
    if (!TOPIC_CONTEXT_KEYS.has(key)) {
      return fail(`topic_context_unknown_field:${key}`);
    }
  }
  if (
    [...TOPIC_CONTEXT_KEYS].every((key) =>
      raw[key] === undefined || raw[key] === null
    )
  ) {
    return fail("topic_context_empty");
  }

  const coldDuration = enumOrNull(raw.coldDuration, NEW_TOPIC_COLD_DURATIONS);
  if (coldDuration === false) {
    return fail("topic_context_cold_duration_invalid");
  }
  const coldStop = enumOrNull(raw.coldStop, NEW_TOPIC_COLD_STOPS);
  if (coldStop === false) return fail("topic_context_cold_stop_invalid");
  const engagement = enumOrNull(raw.engagement, NEW_TOPIC_ENGAGEMENTS);
  if (engagement === false) return fail("topic_context_engagement_invalid");
  const materialKind = enumOrNull(raw.materialKind, NEW_TOPIC_MATERIAL_KINDS);
  if (materialKind === false) {
    return fail("topic_context_material_kind_invalid");
  }

  if (
    (coldDuration !== null || coldStop !== null) && situation !== "went_cold"
  ) {
    return fail("topic_context_cold_fields_without_went_cold");
  }
  if (
    engagement !== null && (situation === null || situation === "went_cold")
  ) {
    return fail("topic_context_engagement_situation_mismatch");
  }

  let materialText: string | null = null;
  const rawText = raw.materialText;
  if (materialKind === null || materialKind === "none") {
    if (rawText !== undefined && rawText !== null) {
      return fail("topic_context_material_text_unexpected");
    }
  } else {
    if (rawText === undefined || rawText === null) {
      return fail("topic_context_material_text_required");
    }
    if (typeof rawText !== "string") {
      return fail("topic_context_material_text_invalid");
    }
    materialText = rawText.replace(FORMAT_CHARS, "").trim().replace(
      /\s+/g,
      " ",
    );
    if (materialText.length === 0) {
      return fail("topic_context_material_text_required");
    }
    if (
      materialText.length > NEW_TOPIC_MATERIAL_TEXT_MAX_CODE_UNITS ||
      graphemeLength(materialText) > NEW_TOPIC_MATERIAL_TEXT_MAX_GRAPHEMES
    ) {
      return fail("topic_context_material_text_too_long");
    }
  }

  return {
    ok: true,
    topicContext: {
      coldDuration,
      coldStop,
      engagement,
      materialKind,
      materialText,
    },
  };
}

/**
 * 冷掉了才看；「怎麼停」比「多久」優先：她沒回／她很冷時不提空窗，用戶沒回她
 * 也不提（不解釋消失，ADR #51 產品裁決 5）。
 */
export function newTopicGapMentionAllowed(
  situation: NewTopicSituation | null,
  topicContext: NewTopicTopicContext | null,
): boolean {
  return situation === "went_cold" &&
    topicContext?.coldDuration === "month_plus" &&
    topicContext.coldStop !== "she_no_reply" &&
    topicContext.coldStop !== "she_cold" &&
    topicContext.coldStop !== "i_no_reply";
}

/** 基本模式＝請求沒帶 topicContext；兩種模式用同一份系統提示詞。 */
export function newTopicPromptVariant(
  topicContext: NewTopicTopicContext | null,
): "basic" | "advanced" {
  return topicContext === null ? "basic" : "advanced";
}

/** telemetry 只記答案代碼與字數，絕不記原文。 */
export function newTopicTwoStageTelemetry(
  topicContext: NewTopicTopicContext | null,
) {
  return {
    promptVariant: newTopicPromptVariant(topicContext),
    promptVersion: NEW_TOPIC_PROMPT_VERSION,
    coldDuration: topicContext?.coldDuration ?? null,
    coldStop: topicContext?.coldStop ?? null,
    engagement: topicContext?.engagement ?? null,
    materialKind: topicContext?.materialKind ?? null,
    materialTextLength: topicContext?.materialText
      ? graphemeLength(topicContext.materialText)
      : 0,
  };
}

// ---------------------------------------------------------------------------
// 「這次的局面」（規格 §4.2–§4.4：規則行逐字，每次只送相關的幾條）
// ---------------------------------------------------------------------------

const SITUATION_LABELS: Record<NewTopicSituation, string> = {
  went_cold: "冷掉了，想重新聊",
  stuck: "還在聊，但接不下去",
  after_date: "剛約完會",
  warm_up: "聊得不錯，想更靠近",
};

const SITUATION_RULES: Record<NewTopicSituation, string> = {
  went_cold:
    "冷掉了：低壓重啟。不責問對方消失、不陰陽怪氣、不討拍；openingLine 收在 30 字內，像順手丟的。",
  stuck: "還在聊但接不下去：一次只開一條線，不像面試連環問。",
  after_date:
    "剛約完會：承接約會的餘溫，不急著約第二次，不索取評價（不問她覺得你怎樣）。",
  warm_up: "聊得不錯想更靠近：可以多一點個人感，但不突然告白、不越界。",
};
// 剛約完會但素材沒寫約會裡的事（基本模式一定是這樣）：只知道約完會，地點、
// 過程、聊了什麼都不知道（nt3 盲測 B6 編了約會附近的店和「笑了好幾次」）。
const AFTER_DATE_NO_DETAILS_RULE =
  "剛約完會：你只知道剛約完，不知道去了哪、做了什麼、聊了什麼——不寫地點、店家、當時的互動或她的反應。不急著約第二次，不索取評價（不問她覺得你怎樣）。";
const NO_SITUATION_RULE = "沒選狀況：當作日常重啟，自然、低壓、好接。";

const COLD_DURATION_LABELS: Record<NewTopicColdDuration, string> = {
  days: "幾天到一週",
  weeks: "一到四週",
  month_plus: "一個月以上",
};
const COLD_STOP_LABELS: Record<NewTopicColdStop, string> = {
  faded: "聊著聊著就停了",
  she_no_reply: "她沒回我",
  i_no_reply: "我沒回她",
  she_cold: "她最近都回很冷",
};

// 模型看不到對話紀錄：「接上次的話題」只在素材寫明了那件事時才成立。
const COLD_DURATION_RULES = {
  daysSharedHistory:
    "幾天到一週沒聊：直接接素材裡那件事，像昨天才聊過；不說好久沒聊。",
  days:
    "幾天到一週沒聊：像昨天才聊過一樣自然；不說好久沒聊，也不假裝接上次的話題。",
  weeks: "一到四週沒聊：輕鬆出現就好，不檢討「我們怎麼都沒聊了」。",
  monthPlusGapAllowed:
    "一個月以上沒聊：可以用一句輕鬆承認有陣子沒聊（只能一句，不檢討、不問原因），接著直接講內容；不一上來就曖昧。",
  monthPlusNoGap: "一個月以上沒聊：不提很久沒聊，也不一上來就曖昧。",
  unknown: "沒說多久：低壓力、不追討；不提很久沒聊。",
} as const;
// faded 不加行。
const COLD_STOP_RULES: Partial<Record<NewTopicColdStop, string>> = {
  she_no_reply:
    "她沒回上一則：傳一則全新的內容，當作沒這回事；不提上一則、不提很久沒聊，不寫「在嗎」「妳怎麼沒回」。",
  // ADR #51 產品裁決 5（Bruce＋Claude Code，2026-10-06）：不解釋消失、不道歉。
  i_no_reply:
    "上次是用戶沒回她：直接傳一個新內容，像平常聊天；不解釋為什麼沒回、不道歉、不替自己辯解，也不提很久沒聊。",
  she_cold:
    "她最近都回很冷：一則就好、很輕、她不用費力就能回；不連續丟話題、不加曖昧、不約她。",
};

type EngagementSituation = Exclude<NewTopicSituation, "went_cold">;
const ENGAGEMENT_LABELS: Record<
  EngagementSituation,
  Record<NewTopicEngagement, string>
> = {
  stuck: {
    green: "會反問、聊很多",
    yellow: "有回，但很短",
    red: "常只回哈哈、嗯",
  },
  warm_up: {
    green: "會反問、聊很多",
    yellow: "有回，但很短",
    red: "常只回哈哈、嗯",
  },
  after_date: {
    green: "主動傳訊息或說開心",
    yellow: "有回，但普通",
    red: "還沒回或很冷淡",
  },
};
const ENGAGEMENT_RULES: Record<
  EngagementSituation,
  Record<NewTopicEngagement, string>
> = {
  stuck: {
    green: "她有在投入：可以多一點用戶的看法，開點小玩笑。",
    yellow: "她有回但很短：不加長、不連問，每題都要好回。",
    // 紅燈收尾：第一題的任務就是收尾句（new_topic_slots.ts），推薦由伺服器固定第一題。
    red: "她常只回哈哈、嗯：其他題也都很輕、很短，不連問、不加曖昧。",
  },
  after_date: {
    green:
      "約完她主動傳訊息或說開心：用約會裡的事或梗延續，可以輕提「下次」，但不約時間。",
    yellow:
      "約完她反應普通：用約會裡一件小事輕輕接，不問她覺得你怎樣，先不約下次。",
    red:
      "約完她還沒回或很冷淡：最多一則輕鬆的內容，她沒接就先停；不追問感受、不約下次。",
  },
  warm_up: {
    green:
      "她很投入：可以多一點個人感、「我們」一起做某件事的小想像；不突然告白、不越界。",
    yellow: "她有回但普通：先讓聊天重新好玩，不加曖昧。",
    red: "她常只回哈哈、嗯：現在不升溫，其他題也只給輕的；不加曖昧、不約。",
  },
};

// 沒有共同經歷可接時（素材不是之前聊過的事或你們的梗）不能叫模型「用約會裡的事」。
const AFTER_DATE_NO_HISTORY_RULES: Partial<Record<NewTopicEngagement, string>> =
  {
    green:
      "約完她主動傳訊息或說開心：延續約會的好心情，可以輕提「下次」，但不約時間；你不知道約會細節，不編約會裡發生的事。",
    yellow:
      "約完她反應普通：輕輕的就好，不問她覺得你怎樣，先不約下次；不編約會裡發生的事。",
  };
const WARM_UP_GREEN_INSIDE_JOKE_RULE =
  "她很投入：可以多一點個人感、「我們」一起做某件事的小想像、輕輕回勾你們的曖昧梗；不突然告白、不越界。";

const MEET_ALLOWED_RULE =
  "見面：nextMove 可以提「聊熱了再從話題帶出見面，她說好才約時間」；第一則仍然不約。";
const MEET_DEFAULT_RULE = "見面：五題的第一則都不約，nextMove 也不建議約她。";
const COOL_NEXT_MOVE_RULE =
  "nextMove 多寫一句：她沒回就別追，只回很短就自然收掉。";
// Bruce 2026-10-18（#97）：冷掉停手算兩次，跟對話分析 C1「他連續主動兩次、她都敷衍就先別回」一致。
// 她沒回上一則、或最近都回很冷，這則就是他第二次主動；App 的教練提醒（new_topic_two_stage_copy.dart）同一句。
const COLD_SECOND_TRY_RULE =
  "這是用戶第二次主動找她（上一則她沒回或回很冷）：nextMove 寫明她這則還是沒回或只回很短，就先停手、等她主動，不要再傳第三則。";
// 與輸出守門同一個判準（allowsNewTopicSharedFrame），提示詞與守門不打架。
const SHARED_FRAME_ALLOWED_RULE =
  "「我們」：可以寫你們一起的事或一起做某件事的小想像，但不越級。";
const SHARED_FRAME_DENIED_RULE =
  "「我們」：不寫「我們」接動作或「我們兩個」「我們家」「我們以後」這類句子，也不寫一起養、一起住；提到過去的事用「上次」「那次」「妳那句」。";

const MATERIAL_LABELS: Record<NewTopicMaterialKind, string> = {
  past_topic: "之前聊過的事（她提過的）",
  trigger: "看到想到她的東西",
  my_story: "用戶最近遇到的事",
  inside_joke: "你們之間的梗",
  none: "沒有，請教練想",
};
const AFTER_DATE_PAST_TOPIC_LABEL = "約會時聊到的事";
/** 還在聊／想更靠近＋她常只回哈哈、嗯：第一題寫成收尾，推薦固定第一題（規格 §9.4）。 */
export function isNewTopicRedClose(
  situation: NewTopicSituation | null,
  topicContext: NewTopicTopicContext | null,
): boolean {
  return (situation === "stuck" || situation === "warm_up") &&
    topicContext?.engagement === "red";
}

/**
 * 紅燈收尾時用戶看到的推薦理由。固定句：模型寫的理由會漏出指示措辭
 * （「局面規定第一題要是收尾句」，nt2-red-r2 3/4），寫給別題的也不能用。
 */
export const NEW_TOPIC_RED_CLOSE_REASON =
  "她最近常只回很短，先自然收尾、留一個下次可以接的點，比硬開新話題更不會把她推遠。";

/**
 * 紅燈收尾的伺服器端保證：推薦固定第一題、理由一律換成固定句。
 * 純函式，只動推薦，不動五題內容。
 */
export function enforceNewTopicRedClose<
  T extends {
    recommendationIndex: number;
    recommendationReason: string | null;
  },
>(
  normalized: T,
  input: {
    situation: NewTopicSituation | null;
    topicContext: NewTopicTopicContext | null;
  },
): { normalized: T; applied: boolean; overridden: boolean } {
  const applied = isNewTopicRedClose(input.situation, input.topicContext);
  const overridden = applied && normalized.recommendationIndex !== 0;
  return {
    normalized: applied
      ? {
        ...normalized,
        recommendationIndex: 0,
        recommendationReason: NEW_TOPIC_RED_CLOSE_REASON,
      }
      : normalized,
    applied,
    overridden,
  };
}

function situationRules(
  situation: NewTopicSituation | null,
  topicContext: NewTopicTopicContext,
  sharedFrameAllowed: boolean,
): string[] {
  const { coldDuration, coldStop, engagement, materialKind, materialText } =
    topicContext;
  const sharedHistory = materialText !== null &&
    (materialKind === "past_topic" || materialKind === "inside_joke");
  const rules = [
    situation === "after_date" && !sharedHistory
      ? AFTER_DATE_NO_DETAILS_RULE
      : situation
      ? SITUATION_RULES[situation]
      : NO_SITUATION_RULE,
  ];
  if (situation === "went_cold") {
    // 「怎麼停」比「多久」優先，所以排在前面。
    const stopRule = coldStop === null ? undefined : COLD_STOP_RULES[coldStop];
    if (stopRule) rules.push(stopRule);
    // 她沒回上一則時不能「接上次聊到的事」（那等於追上一則）：多久那行讓給怎麼停。
    if (coldDuration === "days" && coldStop === "she_no_reply") {
      return rulesTail();
    }
    rules.push(
      coldDuration === "days"
        ? sharedHistory
          ? COLD_DURATION_RULES.daysSharedHistory
          : COLD_DURATION_RULES.days
        : coldDuration === "weeks"
        ? COLD_DURATION_RULES.weeks
        : coldDuration === "month_plus"
        ? newTopicGapMentionAllowed(situation, topicContext)
          ? COLD_DURATION_RULES.monthPlusGapAllowed
          : COLD_DURATION_RULES.monthPlusNoGap
        : COLD_DURATION_RULES.unknown,
    );
  } else if (situation !== null && engagement !== null) {
    const noHistoryRule = situation === "after_date" && !sharedHistory
      ? AFTER_DATE_NO_HISTORY_RULES[engagement]
      : undefined;
    const insideJoke = materialKind === "inside_joke" && materialText !== null;
    rules.push(
      noHistoryRule ??
        (situation === "warm_up" && engagement === "green" && insideJoke
          ? WARM_UP_GREEN_INSIDE_JOKE_RULE
          : ENGAGEMENT_RULES[situation][engagement]),
    );
  }
  return rulesTail();

  function rulesTail(): string[] {
    rules.push(
      (situation === "after_date" || situation === "warm_up") &&
        engagement === "green"
        ? MEET_ALLOWED_RULE
        : MEET_DEFAULT_RULE,
    );
    if (
      situation === "went_cold" || engagement === "yellow" ||
      engagement === "red"
    ) {
      rules.push(
        situation === "went_cold" &&
          (coldStop === "she_no_reply" || coldStop === "she_cold")
          ? COLD_SECOND_TRY_RULE
          : COOL_NEXT_MOVE_RULE,
      );
    }
    rules.push(
      sharedFrameAllowed ? SHARED_FRAME_ALLOWED_RULE : SHARED_FRAME_DENIED_RULE,
    );
    return rules;
  }
}

const TAIPEI_DATE_PARTS = new Intl.DateTimeFormat("en-US", {
  timeZone: "Asia/Taipei",
  year: "numeric",
  month: "numeric",
  day: "numeric",
  weekday: "short",
});
const WEEKDAY_LABELS: Record<string, string> = {
  Mon: "一",
  Tue: "二",
  Wed: "三",
  Thu: "四",
  Fri: "五",
  Sat: "六",
  Sun: "日",
};

/**
 * 使用者提示詞的「今天」（台灣時間）。提示詞要每句看得出為什麼現在說，模型
 * 卻不知道日期，會從作戰板的最後互動日期猜季節（ADR #51 預審 P2-2）。
 */
export function newTopicTodayLabel(nowMs: number): string {
  const parts: Record<string, string> = {};
  for (const part of TAIPEI_DATE_PARTS.formatToParts(new Date(nowMs))) {
    parts[part.type] = part.value;
  }
  return `${parts.year} 年 ${parts.month} 月 ${parts.day} 日（週${
    WEEKDAY_LABELS[parts.weekday]
  }）`;
}

/** 基本模式（請求沒帶 topicContext）＝兩題都沒答。 */
const EMPTY_TOPIC_CONTEXT: NewTopicTopicContext = {
  coldDuration: null,
  coldStop: null,
  engagement: null,
  materialKind: null,
  materialText: null,
};

/** 用戶素材的類型標籤；剛約完會時「之前聊過的事」改稱約會時聊到的事。 */
export function newTopicMaterialLabel(
  materialKind: NewTopicMaterialKind,
  situation: NewTopicSituation | null,
): string {
  return materialKind === "past_topic" && situation === "after_date"
    ? AFTER_DATE_PAST_TOPIC_LABEL
    : MATERIAL_LABELS[materialKind];
}

/**
 * 「這次的局面」段：狀況、多久沒聊、上次怎麼停、她的反應，加上每次只送相關幾條
 * 的做法（節奏、見面、「我們」）。內容由五題的任務決定，這段只管輕重與分寸。
 */
export function newTopicSituationLines(input: {
  partnerSummary: string | null;
  situation: NewTopicSituation | null;
  topicContext: NewTopicTopicContext | null;
}): string[] {
  const situation = input.situation;
  const topicContext = input.topicContext ?? EMPTY_TOPIC_CONTEXT;
  const { coldDuration, coldStop, engagement } = topicContext;
  const lines = [
    "## 這次的局面（用戶自己說的現況，照這裡的做法寫）",
    `- 狀況：${situation ? SITUATION_LABELS[situation] : "沒有選"}`,
  ];
  if (coldDuration !== null) {
    lines.push(`- 多久沒聊：${COLD_DURATION_LABELS[coldDuration]}`);
  }
  if (coldStop !== null) {
    lines.push(`- 上次怎麼停：${COLD_STOP_LABELS[coldStop]}`);
  }
  if (engagement !== null && situation !== null && situation !== "went_cold") {
    const title = situation === "after_date"
      ? "約完之後她的反應"
      : "她最近回你的樣子";
    lines.push(`- ${title}：${ENGAGEMENT_LABELS[situation][engagement]}`);
  }
  lines.push("做法：");
  const sharedFrameAllowed = allowsNewTopicSharedFrame({
    partnerSummary: input.partnerSummary,
    situation,
    topicContext,
  });
  for (
    const rule of situationRules(situation, topicContext, sharedFrameAllowed)
  ) {
    lines.push(`- ${rule}`);
  }
  return lines;
}

// ---------------------------------------------------------------------------
// 只記錄、不擋的品質稽核（規格 §4.6）：回傳純數字／布林，不含原文
// ---------------------------------------------------------------------------

export type NewTopicTwoStageAudit = {
  materialUsedInRecommended: boolean | null;
  topicsUsingMaterial: number | null;
  gapMentionLines: number;
  gapMentionAllowed: boolean;
  bannedOpenerLines: number;
  inviteLines: number;
  apologyLines: number;
  multiEmojiLines: number;
  /** 一句裡有兩個以上問句的開場句數（連續的問號算一個；評測工具的「一句兩問」同算法）。 */
  multiQuestionLines: number;
  /** 這筆是紅燈收尾（還在聊／想更靠近＋她常只回哈哈、嗯）。 */
  redCloseApplied: boolean;
  /** 紅燈收尾時第一題 openingLine 有沒有收尾字眼（0／1）；不是紅燈收尾為 null。 */
  redCloseCueInFirst: number | null;
};

// 提空窗、道歉兩組樣式另給評測工具算「我沒回她」的句子（tools/new-topic-two-stage-eval）。
export const GAP_MENTION_PATTERN =
  /好久|很久沒|一陣子沒|有陣子沒|這陣子沒|最近都沒|怎麼沒回|沒消息/;
const BANNED_OPENER_PATTERN =
  /在嗎|最近好嗎|最近在幹嘛|最近在忙什麼|有件事想跟妳說|有件事想跟你說/;
const INVITE_PATTERN = /約妳|約你|見面|出來吃|出來喝|出來玩|一起去/;
export const APOLOGY_PATTERN = /抱歉|不好意思|對不起|sorry/i;
const RED_CLOSE_CUE_PATTERN =
  /先去忙|晚點|改天|下次|再跟妳|再跟你|先這樣|報告|先睡|先忙|回頭再|有空再/;
const EMOJI_GRAPHEME = /\p{Extended_Pictographic}|\p{Regional_Indicator}/u;
const graphemeSegmenter = new Intl.Segmenter("zh-Hant", {
  granularity: "grapheme",
});

/** 以 grapheme 計：ZWJ 組合、國旗都只算一個 emoji。 */
function emojiCount(text: string): number {
  let count = 0;
  for (const { segment } of graphemeSegmenter.segment(text)) {
    if (EMOJI_GRAPHEME.test(segment)) count++;
  }
  return count;
}

function cjkBigrams(text: string): Set<string> {
  const bigrams = new Set<string>();
  for (const run of text.match(/\p{Script=Han}+/gu) ?? []) {
    const chars = [...run];
    for (let i = 0; i + 1 < chars.length; i++) {
      bigrams.add(chars[i] + chars[i + 1]);
    }
  }
  return bigrams;
}

function englishWords(text: string): Set<string> {
  return new Set(
    (text.match(/[a-z]{3,}/gi) ?? []).map((word) => word.toLowerCase()),
  );
}

export function auditNewTopicTwoStageTopics(input: {
  topics: NewTopicModelTopic[];
  recommendationIndex: number;
  topicContext: NewTopicTopicContext | null;
  situation: NewTopicSituation | null;
}): NewTopicTwoStageAudit {
  const { topics } = input;
  const topicContext = input.topicContext ?? EMPTY_TOPIC_CONTEXT;
  const count = (pattern: RegExp) =>
    topics.filter((topic) => pattern.test(topic.openingLine)).length;

  let usesMaterial: ((topic: NewTopicModelTopic) => boolean) | null = null;
  if (topicContext.materialText !== null) {
    const materialBigrams = cjkBigrams(topicContext.materialText);
    const materialWords = englishWords(topicContext.materialText);
    usesMaterial = (topic) => {
      // 換行隔開，避免 direction 尾字與 openingLine 首字湊出假二字詞。
      const text = `${topic.direction}\n${topic.openingLine}`;
      const topicBigrams = cjkBigrams(text);
      let shared = 0;
      for (const bigram of materialBigrams) {
        if (topicBigrams.has(bigram)) shared++;
      }
      if (shared >= 2) return true;
      const topicWords = englishWords(text);
      return [...materialWords].some((word) => topicWords.has(word));
    };
  }

  const redCloseApplied = isNewTopicRedClose(input.situation, topicContext);
  return {
    materialUsedInRecommended: usesMaterial === null
      ? null
      : usesMaterial(topics[input.recommendationIndex]),
    topicsUsingMaterial: usesMaterial === null
      ? null
      : topics.filter(usesMaterial).length,
    gapMentionLines: count(GAP_MENTION_PATTERN),
    gapMentionAllowed: newTopicGapMentionAllowed(input.situation, topicContext),
    bannedOpenerLines: count(BANNED_OPENER_PATTERN),
    inviteLines: count(INVITE_PATTERN),
    apologyLines: count(APOLOGY_PATTERN),
    multiEmojiLines:
      topics.filter((topic) => emojiCount(topic.openingLine) >= 2).length,
    multiQuestionLines:
      topics.filter((topic) =>
        (topic.openingLine.match(/[?？]+/gu) ?? []).length >= 2
      ).length,
    redCloseApplied,
    redCloseCueInFirst: redCloseApplied
      ? Number(RED_CLOSE_CUE_PATTERN.test(topics[0].openingLine))
      : null,
  };
}
