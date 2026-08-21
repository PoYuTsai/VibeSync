// 練習室動態貼文的每日排程（純函式、零 DB 狀態、可 deno test）。
//
// 這支檔案回答「今天這位角色發不發文、幾點發、發什麼題材、要不要配圖」，
// 但**不產生任何可見文字**——文字一律由 DeepSeek 依這裡選定的題材寫，
// 避免罐頭貼文（practice_ai_no_canned 鐵則）。
//
// 為什麼隨機性由種子決定而不是讓模型自由發想（設計報告決定 B）：
// - 同一天重跑得到同一份計畫 → 生成失敗可安全重試，不會冒出第二則不同內容。
// - 每一種題材都能事先測試，模型只負責「寫得像人」這一件事。
// - 每日生成次數可事先算出上界，成本不會隨使用者數擴張。
//
// 範式沿用 life_schedule.ts（她「今天在幹嘛」也是同一套 seed 選擇）。
//
// 刻意不與 life_schedule.ts 共用 fnv1a：抽共用 helper 會動到已上線的每日場景
// 選擇路徑，那是另一個 PR 的事。若複審認為該抽，我另開 PR 處理。

import type {
  PersonaId,
  PracticeGirlProfile,
  ProfessionId,
} from "./practice_persona.ts";
import type { TaipeiDayPart, TaipeiTimeContext } from "./time_context.ts";
import {
  momentImagesForTags,
  type MomentImageTag,
} from "./moments_image_catalog.ts";

/** 一天最多兩則；第二則機率遠低於第一則。 */
export const MAX_MOMENT_SLOTS_PER_DAY = 2;

/** 第二則的機率折扣：她偶爾一天發兩則，但不會天天。 */
const SECOND_SLOT_FACTOR = 0.3;

/** 配圖機率（題材允許配圖時才擲）。 */
const IMAGE_PROBABILITY = 0.45;

/** 發文傾向下限／上限：再內向的人也偶爾發，再外向的人也不是天天。 */
const MIN_PROPENSITY = 0.15;
const MAX_PROPENSITY = 0.85;

export interface MomentSlotPlan {
  slot: number;
  dayPart: TaipeiDayPart;
  themeId: string;
  /** 注入生成 prompt 的題材描述（server 事實，不是可見文字）。 */
  brief: string;
  wantsImage: boolean;
  /** wantsImage 為 false 時必為空陣列。 */
  imageCandidates: readonly string[];
}

export interface MomentDayPlan {
  profileId: string;
  isoDate: string;
  slots: readonly MomentSlotPlan[];
}

interface MomentTheme {
  id: string;
  brief: string;
  /** 缺席＝除清晨外全時段可用。 */
  dayParts?: readonly TaipeiDayPart[];
  /** 空陣列＝這個題材只發純文字。 */
  imageTags: readonly MomentImageTag[];
}

// 清晨（05-07）全域排除：真人幾乎不在這個時段發朋友圈，留著只會讓貼文看起來像機器。
const POSTABLE_DAY_PARTS: readonly TaipeiDayPart[] = [
  "morning",
  "noon",
  "afternoon",
  "early_evening",
  "evening",
  "late_night",
];

// ── 主題池 ─────────────────────────────────────────────────────────────
// brief 是給生成端的題材線索，不是給使用者看的文案；模型要用自己的口氣重寫。

const BASE_THEMES: readonly MomentTheme[] = [
  {
    id: "morning_commute",
    brief: "通勤路上的一個小片段：天氣、車廂、或還沒完全醒的狀態。",
    dayParts: ["morning"],
    imageTags: ["commute", "sky"],
  },
  {
    id: "coffee_start",
    brief: "今天的第一杯咖啡或早餐，用來啟動一天。",
    dayParts: ["morning", "noon"],
    imageTags: ["coffee", "cafe"],
  },
  {
    id: "work_grind",
    brief: "工作卡關或事情一件接一件，帶點無奈但不抱怨到底。",
    dayParts: ["morning", "afternoon"],
    imageTags: ["desk", "work"],
  },
  {
    id: "lunch_break",
    brief: "午餐吃了什麼，或難得的空檔。",
    dayParts: ["noon"],
    imageTags: ["food"],
  },
  {
    id: "afternoon_slump",
    brief: "下午沒電，需要糖分或咖啡因續命。",
    dayParts: ["afternoon"],
    imageTags: ["dessert", "coffee"],
  },
  {
    id: "off_work_walk",
    brief: "下班路上的空檔，走一段路或發個呆。",
    dayParts: ["early_evening"],
    imageTags: ["walk", "city", "sky"],
  },
  {
    id: "sunset_catch",
    brief: "剛好看到很好的天色，忍不住停下來。",
    dayParts: ["early_evening"],
    imageTags: ["sky"],
  },
  {
    id: "dinner_simple",
    brief: "晚餐，可能是隨便吃或難得認真煮。",
    dayParts: ["early_evening", "evening"],
    imageTags: ["food", "cooking"],
  },
  {
    id: "home_unwind",
    brief: "回到家癱下來，這一天終於結束。",
    dayParts: ["evening"],
    imageTags: ["calm"],
  },
  {
    id: "night_thoughts",
    brief: "睡前的一個小念頭或小結論，不說教、不勵志。",
    dayParts: ["evening", "late_night"],
    imageTags: [],
  },
  {
    id: "late_snack",
    brief: "宵夜，明知不該但還是吃了。",
    dayParts: ["late_night"],
    imageTags: ["food", "night"],
  },
  {
    id: "rainy_mood",
    brief: "下雨天帶來的情緒或行程變化。",
    imageTags: ["rain"],
  },
];

// 週末限定：只在 isWeekend 時進池（見 themePoolFor），不另設旗標欄位。
const WEEKEND_THEMES: readonly MomentTheme[] = [
  {
    id: "weekend_brunch",
    brief: "週末的早午餐，節奏整個慢下來。",
    dayParts: ["morning", "noon"],
    imageTags: ["food", "cafe"],
  },
  {
    id: "weekend_outing",
    brief: "週末出門晃，跟朋友或自己一個人都好。",
    dayParts: ["afternoon", "early_evening"],
    imageTags: ["walk", "city", "self"],
  },
  {
    id: "weekend_slow",
    brief: "週末刻意什麼都不做，賴在家裡。",
    dayParts: ["morning", "afternoon"],
    imageTags: ["calm"],
  },
];

/** 興趣／生活標籤命中才進池；關鍵字比對沿用 life_schedule 的做法。 */
const INTEREST_THEMES: readonly {
  keywords: readonly string[];
  theme: MomentTheme;
}[] = [
  {
    keywords: ["咖啡"],
    theme: {
      id: "cafe_hunt",
      brief: "踩到一間還不錯的咖啡店，或今天的手沖成果。",
      dayParts: ["morning", "noon", "afternoon"],
      imageTags: ["coffee", "cafe"],
    },
  },
  {
    keywords: ["烘焙", "做菜", "健康料理"],
    theme: {
      id: "home_kitchen",
      brief: "自己做的東西，成功或失敗都可以講。",
      dayParts: ["noon", "early_evening", "evening"],
      imageTags: ["cooking", "dessert"],
    },
  },
  {
    keywords: ["看書"],
    theme: {
      id: "book_note",
      brief: "最近在看的書，或看到一句停下來的話。",
      dayParts: ["afternoon", "evening", "late_night"],
      imageTags: ["book"],
    },
  },
  {
    keywords: ["追劇", "電影"],
    theme: {
      id: "screen_night",
      brief: "在追的劇或剛看完的電影，講感覺不爆雷。",
      dayParts: ["evening", "late_night"],
      imageTags: ["calm"],
    },
  },
  {
    keywords: ["音樂祭"],
    theme: {
      id: "live_music",
      brief: "現場演出或最近單曲循環的歌。",
      dayParts: ["evening", "late_night"],
      imageTags: ["music", "night"],
    },
  },
  {
    keywords: ["拍照"],
    theme: {
      id: "photo_walk",
      brief: "隨手拍到的一個畫面，帶點自己的觀察。",
      imageTags: ["city", "sky", "walk"],
    },
  },
  {
    keywords: ["旅行", "自助旅行"],
    theme: {
      id: "travel_plan",
      brief: "在查下一趟要去哪，或想起上一趟的某個片段。",
      dayParts: ["afternoon", "evening", "late_night"],
      imageTags: ["travel", "commute"],
    },
  },
  {
    keywords: ["潛水或海邊活動"],
    theme: {
      id: "sea_day",
      brief: "海邊或水下的一天，人是放空的。",
      dayParts: ["noon", "afternoon", "early_evening"],
      imageTags: ["sea", "outdoor"],
    },
  },
  {
    keywords: ["瑜珈", "健身"],
    theme: {
      id: "workout_done",
      brief: "剛練完，累但心情不錯。",
      dayParts: ["morning", "early_evening", "evening"],
      imageTags: ["fitness", "self"],
    },
  },
  {
    keywords: ["戶外爬山"],
    theme: {
      id: "trail_day",
      brief: "上山走一趟，講風景或講腿痠都行。",
      dayParts: ["morning", "noon", "afternoon"],
      imageTags: ["outdoor", "nature"],
    },
  },
  {
    keywords: ["寵物"],
    theme: {
      id: "pet_moment",
      brief: "家裡那隻今天做了什麼。",
      imageTags: ["pet"],
    },
  },
  {
    keywords: ["美食"],
    theme: {
      id: "food_find",
      brief: "吃到不錯的東西，講味道不講店名。",
      dayParts: ["noon", "early_evening", "evening"],
      imageTags: ["food"],
    },
  },
  {
    keywords: ["藝術", "文青展覽"],
    theme: {
      id: "exhibition_visit",
      brief: "看展的一個片段或一個很有感的作品。",
      dayParts: ["afternoon", "early_evening"],
      imageTags: ["art"],
    },
  },
  {
    keywords: ["穿搭", "保養", "選物", "做指甲"],
    theme: {
      id: "style_note",
      brief: "今天的搭配、指甲或剛入手的小東西。",
      dayParts: ["morning", "afternoon", "early_evening"],
      imageTags: ["self", "calm"],
    },
  },
  {
    keywords: ["夜景散步"],
    theme: {
      id: "night_walk",
      brief: "晚上出門走一段，城市安靜下來的感覺。",
      dayParts: ["evening", "late_night"],
      imageTags: ["night", "city", "walk"],
    },
  },
];

/** 職業題材：她的工作日常本身就是最有生活感的素材。 */
const PROFESSION_THEMES: Record<string, MomentTheme> = {
  nurse_hospital: {
    id: "shift_end",
    brief: "下班或下夜班後的狀態，體力被抽乾但不講病人的事。",
    dayParts: ["morning", "evening", "late_night"],
    imageTags: ["calm", "food"],
  },
  nurse_clinic: {
    id: "clinic_day",
    brief: "診所一天結束，規律但站到腳痠。",
    dayParts: ["early_evening", "evening"],
    imageTags: ["calm"],
  },
  flight_attendant: {
    id: "layover",
    brief: "落地或準備出勤，時差跟移動感。",
    dayParts: ["morning", "evening", "late_night"],
    imageTags: ["travel", "commute", "sky"],
  },
  college_student: {
    id: "campus_grind",
    brief: "報告、考試或課堂間的空檔。",
    dayParts: ["afternoon", "evening", "late_night"],
    imageTags: ["desk", "book"],
  },
  graduate_student: {
    id: "lab_grind",
    brief: "論文或實驗進度，腦袋還卡在資料裡。",
    dayParts: ["afternoon", "evening", "late_night"],
    imageTags: ["desk", "coffee"],
  },
  barista: {
    id: "shop_open",
    brief: "開店或收店的片段，店裡的氣味與節奏。",
    dayParts: ["morning", "early_evening"],
    imageTags: ["coffee", "cafe"],
  },
  designer: {
    id: "deadline_night",
    brief: "趕稿或改稿，對美感有原則所以更煩。",
    dayParts: ["evening", "late_night"],
    imageTags: ["desk", "work"],
  },
  yoga_teacher: {
    id: "class_done",
    brief: "帶完課後的身體感與空掉的教室。",
    dayParts: ["morning", "early_evening", "evening"],
    imageTags: ["fitness", "calm"],
  },
  fitness_coach: {
    id: "coach_day",
    brief: "帶完課自己再練一輪。",
    dayParts: ["morning", "early_evening", "evening"],
    imageTags: ["fitness", "self"],
  },
  florist: {
    id: "flower_shop",
    brief: "今天處理的花材或包好的一束。",
    dayParts: ["morning", "afternoon"],
    imageTags: ["nature", "calm"],
  },
};

/**
 * 她在上班／上課／帶課，不太可能發文的時段。
 *
 * 型別是 `Record<ProfessionId, ...>` 而不是 `Partial<...>`：43 種職業每一種都
 * 必須明講，新增職業時編譯器會強迫作者想過作息，不會默默被當成「全天都有空」
 * （複審 2026-08-21 P2：原本只覆蓋 9 種，其餘 34 種等於沒有安靜時段，
 * 但 PR 承諾的是「上班時段不發文」）。
 *
 * 空陣列＝作息本來就不固定（接案、自由工作、輪班無定式），不是「還沒填」。
 * 清晨已由 POSTABLE_DAY_PARTS 全域排除，這裡不必重複列。
 * 任何一種職業都不得填滿所有可發文時段——那會讓她整個從動態消失，
 * 由 professionsWithoutPostableDayParts() 的測試守住。
 */
const PROFESSION_QUIET_DAY_PARTS: Record<
  ProfessionId,
  readonly TaipeiDayPart[]
> = {
  // ── 固定日班（約 9-18）：上班中不滑手機，午休與下班路上可以 ──────────
  marketing_planner: ["morning", "afternoon"],
  product_manager: ["morning", "afternoon"],
  data_analyst: ["morning", "afternoon"],
  ux_researcher: ["morning", "afternoon"],
  hr_consultant: ["morning", "afternoon"],
  bank_staff: ["morning", "afternoon"],
  civil_servant: ["morning", "afternoon"],
  social_worker: ["morning", "afternoon"],
  occupational_therapist: ["morning", "afternoon"],
  pharmacist: ["morning", "afternoon"],
  librarian: ["morning", "afternoon"],
  architect: ["morning", "afternoon"],

  // ── 醫療／診所：跟診與輪班，白天整段被吃掉 ─────────────────────────
  nurse_hospital: ["morning", "afternoon"],
  nurse_clinic: ["morning", "afternoon"],
  dental_assistant: ["morning", "afternoon"],

  // ── 學生：上課與實驗室 ─────────────────────────────────────────────
  college_student: ["morning", "noon"],
  graduate_student: ["morning"],

  // ── 飛行：整段航班加上落地後的時差 ────────────────────────────────
  flight_attendant: ["morning", "noon", "afternoon"],

  // ── 接案／創作：作息不固定，但趕稿多在白天 ────────────────────────
  designer: ["afternoon"],
  illustrator: ["afternoon"],
  interior_designer: ["morning", "afternoon"],
  podcast_editor: ["afternoon"],
  ceramic_artist: ["afternoon"],
  photographer: ["afternoon", "early_evening"],

  // ── 門市／服務業：尖峰在下午到晚上 ────────────────────────────────
  luxury_sales: ["afternoon", "early_evening"],
  stylist: ["afternoon", "early_evening"],
  hair_stylist: ["afternoon", "early_evening"],
  nail_artist: ["afternoon", "early_evening"],
  pet_groomer: ["morning", "afternoon"],
  bookstore_staff: ["afternoon", "early_evening"],

  // ── 餐飲：開店早、出餐時段忙 ──────────────────────────────────────
  barista: ["morning"],
  pastry_chef: ["morning"],
  chef: ["noon", "early_evening"],
  mixologist: ["evening", "late_night"],

  // ── 課程／教練：早課與晚課 ────────────────────────────────────────
  yoga_teacher: ["morning", "evening"],
  fitness_coach: ["morning", "evening"],
  dance_teacher: ["early_evening", "evening"],
  language_tutor: ["early_evening", "evening"],
  surf_instructor: ["morning", "noon", "afternoon"],

  // ── 現場／夜間 ────────────────────────────────────────────────────
  event_pr: ["early_evening", "evening"],
  indie_musician: ["evening", "late_night"],

  // ── 作息本來就不固定 ──────────────────────────────────────────────
  florist: ["morning"],
  inn_host: ["morning", "early_evening"],
};

// ── 發文傾向 ───────────────────────────────────────────────────────────
// 外向的人發得多、慢熱的人發得少。數值是「今天第一則的機率」。

const PERSONA_POST_PROPENSITY: Record<PersonaId, number> = {
  playful_extrovert: 0.78,
  teasing_humor: 0.62,
  clear_boundaries: 0.46,
  slow_worker: 0.38,
  cool_rational: 0.34,
};

const OUTGOING_LIFESTYLE_KEYWORDS: readonly string[] = [
  "跟朋友出門",
  "追展覽",
  "揪團出遊",
  "聚會",
  "逛街",
  "跑活動",
  "小旅行",
  "小酌",
];

const HOMEBODY_LIFESTYLE_KEYWORDS: readonly string[] = [
  "耍廢",
  "補眠",
  "放空",
  "規律作息",
  "在家",
];

const LIFESTYLE_PROPENSITY_STEP = 0.08;

// ── 種子工具 ───────────────────────────────────────────────────────────

function fnv1a(value: string): number {
  let hash = 0x811c9dc5;
  for (let index = 0; index < value.length; index++) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash >>> 0;
}

/** [0, 1) 的穩定亂數。每個決策用不同的子種子，避免決策之間相關。 */
function rollUnit(seed: string): number {
  return fnv1a(seed) / 0x100000000;
}

function pickFrom<T>(items: readonly T[], seed: string): T {
  return items[fnv1a(seed) % items.length];
}

function slotSeed(profileId: string, isoDate: string, slot: number): string {
  return `${profileId}|${isoDate}|moment|${slot}`;
}

// ── 組池 ───────────────────────────────────────────────────────────────

function interestThemesFor(girl: PracticeGirlProfile): MomentTheme[] {
  const haystack = [
    ...girl.interestTags,
    ...girl.lifestyleTags,
  ].join("、");
  return INTEREST_THEMES
    .filter((entry) =>
      entry.keywords.some((keyword) => haystack.includes(keyword))
    )
    .map((entry) => entry.theme);
}

/** 題材 + 它對這位角色實際可用的時段；`dayParts` 由建構方式保證非空。 */
interface EligibleTheme {
  theme: MomentTheme;
  dayParts: readonly TaipeiDayPart[];
}

/**
 * 當日題材池：每個項目都已經算好可用時段，且保證非空。
 *
 * 這裡把「可用時段」跟題材綁在一起回傳，而不是讓呼叫端事後再算一次——
 * 事後再算就得處理「算出來是空的」這個情況，而任何 fallback 寫法都會直接
 * 違反 PROFESSION_QUIET_DAY_PARTS 的硬規則（複審 2026-08-21 抓到：原本的
 * `parts.length > 0 ? parts : POSTABLE_DAY_PARTS` 雖然當下不可達，但後人擴充
 * 作息表時會靜默讓角色在上班時段發文）。綁在一起就沒有那個分支可寫。
 */
function themePoolFor(
  girl: PracticeGirlProfile,
  isWeekend: boolean,
): EligibleTheme[] {
  const professionTheme = PROFESSION_THEMES[girl.professionId];
  const pool = [
    ...BASE_THEMES,
    ...(isWeekend ? WEEKEND_THEMES : []),
    ...interestThemesFor(girl),
    ...(professionTheme ? [professionTheme] : []),
  ]
    .map((theme) => ({
      theme,
      dayParts: eligibleDayParts(theme, girl.professionId),
    }))
    .filter((entry) => entry.dayParts.length > 0);

  if (pool.length === 0) {
    // 不可達，且刻意不做 fallback：走到這裡代表有人把某個職業的
    // PROFESSION_QUIET_DAY_PARTS 填滿了所有可發文時段。那是設定錯誤，
    // 必須大聲壞掉讓測試抓到，不能默默讓她在上班時段發文。
    // 呼叫端（feed handler）負責降級成「今天沒有新貼文」，不是在這裡吞掉。
    throw new Error(`moment_schedule_empty_theme_pool:${girl.professionId}`);
  }
  return pool;
}

function dayPartsForTheme(theme: MomentTheme): readonly TaipeiDayPart[] {
  return theme.dayParts ?? POSTABLE_DAY_PARTS;
}

/**
 * 這個題材對這位角色實際可用的時段：題材允許的時段，扣掉清晨與她的上班時段。
 *
 * 刻意不做「濾空就退回未濾清單」的 fallback：那會讓護理師在上班時段發文，
 * 等於白寫 PROFESSION_QUIET_DAY_PARTS。濾空的題材直接退出當日題材池即可
 * （池子夠大，見 themePoolFor 的保底）。
 */
function eligibleDayParts(
  theme: MomentTheme,
  professionId: ProfessionId,
): readonly TaipeiDayPart[] {
  const quiet = PROFESSION_QUIET_DAY_PARTS[professionId];
  return dayPartsForTheme(theme).filter((part) =>
    POSTABLE_DAY_PARTS.includes(part) && !quiet.includes(part)
  );
}

function propensityFor(girl: PracticeGirlProfile): number {
  let value = PERSONA_POST_PROPENSITY[girl.personaId];
  const lifestyle = girl.lifestyleTags.join("、");
  if (
    OUTGOING_LIFESTYLE_KEYWORDS.some((keyword) => lifestyle.includes(keyword))
  ) {
    value += LIFESTYLE_PROPENSITY_STEP;
  }
  if (
    HOMEBODY_LIFESTYLE_KEYWORDS.some((keyword) => lifestyle.includes(keyword))
  ) {
    value -= LIFESTYLE_PROPENSITY_STEP;
  }
  return Math.min(MAX_PROPENSITY, Math.max(MIN_PROPENSITY, value));
}

// ── 對外 API ───────────────────────────────────────────────────────────

/** 她今天第一則貼文的機率（測試與觀測用；不含第二則的折扣）。 */
export function momentPostPropensityFor(girl: PracticeGirlProfile): number {
  return propensityFor(girl);
}

/**
 * 作息表健康檢查：回傳「安靜時段已覆蓋所有可發文時段」的職業。
 *
 * 正常一定是空陣列。非空代表那個職業一則都發不了——themePoolFor 會丟錯。
 * 這個函式存在的唯一理由是讓「後人擴充 PROFESSION_QUIET_DAY_PARTS 把某個
 * 職業寫死」這件事在測試就被抓到，而不是等上線後才發現她整個消失。
 */
export function momentQuietDayPartsFor(
  professionId: ProfessionId,
): readonly TaipeiDayPart[] {
  return PROFESSION_QUIET_DAY_PARTS[professionId];
}

/** 作息表涵蓋的職業數；型別已保證 exhaustive，這裡供測試再擋一次退化。 */
export const PROFESSION_SCHEDULE_COVERAGE =
  Object.keys(PROFESSION_QUIET_DAY_PARTS).length;

export function professionsWithoutPostableDayParts(): string[] {
  return Object.entries(PROFESSION_QUIET_DAY_PARTS)
    .filter(([, quiet]) =>
      POSTABLE_DAY_PARTS.every((part) => quiet.includes(part))
    )
    .map(([professionId]) => professionId);
}

/**
 * 算出這位角色在這一天的貼文計畫。純函式：同樣的 profile + 日期永遠得到
 * 同樣的結果，故生成端可安全重試而不會產生第二則不同內容的貼文。
 *
 * 回傳的 slots 已依 slot 序排列；空陣列＝她今天不發文（多數日子如此）。
 */
export function momentPlanFor(opts: {
  girl: PracticeGirlProfile;
  time: TaipeiTimeContext;
}): MomentDayPlan {
  const { girl, time } = opts;
  const propensity = propensityFor(girl);
  const pool = themePoolFor(girl, time.isWeekend);
  const slots: MomentSlotPlan[] = [];

  for (let slot = 0; slot < MAX_MOMENT_SLOTS_PER_DAY; slot++) {
    const seed = slotSeed(girl.profileId, time.isoDate, slot);
    const threshold = slot === 0 ? propensity : propensity * SECOND_SLOT_FACTOR;
    if (rollUnit(`${seed}|post`) >= threshold) continue;

    const { theme, dayParts } = pickFrom(pool, `${seed}|theme`);
    const dayPart = pickFrom(dayParts, `${seed}|part`);
    const candidates = momentImagesForTags(theme.imageTags);
    const wantsImage = candidates.length > 0 &&
      rollUnit(`${seed}|image`) < IMAGE_PROBABILITY;

    slots.push({
      slot,
      dayPart,
      themeId: theme.id,
      brief: theme.brief,
      wantsImage,
      imageCandidates: wantsImage ? candidates : [],
    });
  }

  return { profileId: girl.profileId, isoDate: time.isoDate, slots };
}
