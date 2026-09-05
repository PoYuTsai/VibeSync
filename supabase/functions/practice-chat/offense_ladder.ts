// 練習室 Phase 5 WP6：性冒犯三段階梯（Eric 2026-09-06 定案）。
//
// 真實女生對階段不對的性邀約會先給一次機會、第二次已讀、第三次封鎖。這是
// **底線**，三種模式（beginner／standard／game）× 三難度都吃，不走
// `allowsCheckOut` 那道難度閘門。
//
// 計分（只看玩家最新一則）：
//   - 羞辱型（`containsCrudeSexualOffense`：婊子、裸照、輪姦…）        → +2
//   - 一般越界（`OFFENSE_ADVANCE_TERMS`：打炮／打砲、約砲、開房、上床）    → +1
//   - 下一輪補記：詞表沒中而學習分類器判 `boundary === "overstep"`     → +1
//
// 階梯（看**當輪加完詞表**後的累計）：
//   1 → 冷回（chat prompt 當輪尾巴多一行 hidden guidance）
//   2 → 這一輪 forced `read_only`（不打模型，回「（已讀）」）
//   ≥3 → 封鎖（這一輪與之後每一輪都不打任何模型，回「（已封鎖）」）
//
// 分類器補記的**前提**（Codex R1 P1-4）：beginner／game 讀逐輪分類器
// （`judgeLearningState`），standard 讀 4.5b 的精簡分類器——後者只有
// `PRACTICE_STANDARD_AGENCY_CLASSIFIER=true` 時才跑。所以 standard 在那支旗標
// 關著時**階梯只有詞表**，沒有分類器補記（明確降級，不是 bug；production 兩支
// 都開）。`index_test.ts` 有一條測試釘住這個行為。
//
// 衰減（2026-09-06 黑箱實測依據）：逐輪分類器對正常調情的
// `boundary === "overstep"` 誤殺率約 11%，累計不歸零時正常玩家一場 20 輪會被
// 記到約 2 次，有機會無辜被封。所以**連續 3 輪完全沒加分就把累計歸零**；
// `blocked` 一旦成立不受衰減影響（她已經封了就是封了）。

import {
  containsCrudeSexualOffense,
  normalizedOffenseText,
} from "./game_fsm.ts";

/** 累計到這個值就封鎖。 */
export const OFFENSE_BLOCK_STRIKES = 3;
/** 連續這麼多輪沒有任何加分就把累計歸零。 */
export const OFFENSE_DECAY_CLEAN_TURNS = 3;

export type OffenseStage = "none" | "cold" | "read_only" | "blocked";
export type OffenseSource = "crude" | "boundary" | "classifier" | null;

/** 持久化在 `ConversationAgencyState` 的四個數字／布林。 */
export interface OffenseState {
  readonly strikes: number;
  readonly cleanStreak: number;
  /**
   * Codex R1 P1-3：**已經執行到第幾階**（0／1／2／3）。
   *
   * 沒有它的時候，階梯只在「這一輪詞表有加分」時往前走一格，於是分類器
   * 自己累的分永遠跳過冷回與已讀——玩家看不到任何警告，第四輪突然被封。
   * 有了它，只要 `stage(累計) > 已執行`，這一輪就補做那一階，就算玩家這則
   * 是正常話。
   */
  readonly servedStage: number;
  readonly blocked: boolean;
}

export const INITIAL_OFFENSE_STATE: OffenseState = {
  strikes: 0,
  cleanStreak: 0,
  servedStage: 0,
  blocked: false,
};

/** 累計對應到第幾階（0＝還沒到）。 */
function stageIndexFor(strikes: number): number {
  return strikes >= OFFENSE_BLOCK_STRIKES
    ? 3
    : strikes >= 2
    ? 2
    : strikes >= 1
    ? 1
    : 0;
}

const STAGE_NAMES: readonly OffenseStage[] = [
  "none",
  "cold",
  "read_only",
  "blocked",
];

/** 這一輪要做什麼（在生成之前就算得出來，因為只看詞表）。 */
export interface OffenseTurn {
  readonly stage: OffenseStage;
  /** 詞表加完後的累計（分類器補記還沒發生）。 */
  readonly strikes: number;
  /** 這一輪詞表加了幾分（0＝沒加分，分類器才有補記資格）。 */
  readonly delta: number;
  readonly source: Exclude<OffenseSource, "classifier">;
  /** 上一輪之前就已經封了（這一輪連狀態都不必寫）。 */
  readonly wasBlocked: boolean;
  /** 這一輪結束後「已執行到第幾階」（P1-3）。 */
  readonly servedStage: number;
}

/**
 * 「打炮／打砲／約炮／約砲」同時躺在兩張既有詞表裡：`CRUDE_SEXUAL_OFFENSE_TERMS`
 * （Game FSM 的 GREASY／spicy 判定）與 `BOUNDARY_RE`。Eric 2026-09-06 對階梯的
 * 定義是「這幾個字是階段不對的**欲望**，1 分，不是羞辱」，所以判羞辱型之前先
 * 把它們從文字裡拿掉——**只影響本檔的階梯計分**，兩張原表一個字都沒動
 * （Game FSM 照舊把它們當粗俗冒犯）。
 */
const DESIRE_NOT_INSULT_TERMS: readonly string[] = [
  "打炮",
  "打砲",
  "約炮",
  "约炮",
  "約砲",
];

function withoutDesireTerms(text: string): string {
  let stripped = text;
  for (const term of DESIRE_NOT_INSULT_TERMS) {
    stripped = stripped.split(term).join("");
  }
  return stripped;
}

/**
 * +1 那一層的詞表（Codex R1 P1-2）。
 *
 * 舊版借用 `looksBoundaryCrossing`，而它背後的 `BOUNDARY_RE` 含「泳裝｜內衣｜
 * 身材照」這種**沒有上下文的話題詞**——「我的泳裝放在健身房」講三次就被封。
 * 這裡改成自己的、只收**明確性邀約／性暗示**的清單：取
 * `visible_text_guard.ts` 的 `SPICY_VISIBLE_PATTERNS` 扣掉羞辱型（那些留在
 * +2）、扣掉裸名詞（`胸部` 與泳裝同一類假陽性），再補幾個口語形。需要語境
 * 才算數的兩個詞（開房／上床）在 `OFFENSE_ADVANCE_PATTERNS`。
 *
 * 刻意不收英文（`sex`／`nude` 這些在 `SPICY_VISIBLE_PATTERNS` 裡是子字串比對，
 * `sexy`／`unisex` 會誤中）。這是階梯專用的窄表；`BOUNDARY_RE` 那條給 planner
 * 用的路徑一個字都沒動。
 */
const OFFENSE_ADVANCE_TERMS: readonly string[] = [
  "脫衣",
  "脱衣",
  "脫光",
  "脱光",
  "裸體",
  "裸体",
  "私密照",
  "摸你",
  "摸妳",
  "性交",
  "打炮",
  "打砲",
  "約炮",
  "约炮",
  "約砲",
  "一夜情",
  "炮友",
  "砲友",
  "來我家過夜",
  "去我家過夜",
  "睡我家",
  "來我房間",
  "去你房間",
  "去妳房間",
  "直接睡你",
  "直接睡妳",
];

/**
 * 需要語境才算數的兩個詞（Codex R2 P1-B）。純 `includes` 會把
 * 「我去開房門」「今天想早點上床休息」判成性邀約，三輪就把正常玩家封掉。
 *
 * 「回家睡」整條拿掉——「累了，我先回家睡」是最普通的生活句，而真的邀約已經
 * 被「睡我家／來我房間／去你房間／來我家過夜」蓋住。
 */
const OFFENSE_ADVANCE_PATTERNS: readonly RegExp[] = [
  // 沿用 `turn_response_plan.ts` 原 regex 的 `(?!門)`：開房門不是開房。
  /開房(?!門)/u,
  /开房(?!门)/u,
  // 只算性邀約語境；單獨的「上床」（早點上床休息）不算。
  /(?:跟|和|與|与|想|要|一起)(?:你|妳|我)?上床(?!睡|休息)/u,
];

/** 詞表對單一則的判分。羞辱型優先（+2），明確性邀約 +1。 */
export function offenseTermDelta(
  text: string,
): { delta: number; source: Exclude<OffenseSource, "classifier"> } {
  // Codex R1 P1-5：**先正規化再抽欲望詞**。舊版對原文 split，「打 炮」抽不掉
  // 卻被 `containsCrudeSexualOffense` 自己的 normalize 命中 → 判成 +2 羞辱。
  const normalized = normalizedOffenseText(text);
  if (containsCrudeSexualOffense(withoutDesireTerms(normalized))) {
    return { delta: 2, source: "crude" };
  }
  if (
    OFFENSE_ADVANCE_TERMS.some((term) =>
      normalized.includes(normalizedOffenseText(term))
    ) ||
    OFFENSE_ADVANCE_PATTERNS.some((pattern) => pattern.test(normalized))
  ) {
    return { delta: 1, source: "boundary" };
  }
  return { delta: 0, source: null };
}

/**
 * 這一輪的階梯判定。`latestUserText`＝逐字稿裡玩家最新的那一則。
 *
 * 階梯走「累計對應的階 > 已執行的階」就補做那一階（Codex R1 P1-3）——所以
 * 分類器在上一輪補的分，下一輪就算玩家這則是正常話也會補做冷回／已讀，
 * 不會無預警跳到封鎖。累計沒往上就是 `none`（她不會平白一直冷下去）。
 */
export function offenseTurnFor(
  prev: OffenseState,
  latestUserText: string,
): OffenseTurn {
  if (prev.blocked || prev.servedStage >= 3) {
    return {
      stage: "blocked",
      strikes: prev.strikes,
      delta: 0,
      source: null,
      wasBlocked: true,
      servedStage: 3,
    };
  }
  const { delta, source } = offenseTermDelta(latestUserText);
  const strikes = prev.strikes + delta;
  const target = stageIndexFor(strikes);
  const advance = target > prev.servedStage;
  return {
    stage: advance ? STAGE_NAMES[target] : "none",
    strikes,
    delta,
    source,
    wasBlocked: false,
    servedStage: advance ? target : prev.servedStage,
  };
}

/**
 * 寫回狀態時的最終累計：詞表沒加分而分類器判 `overstep` 才補 +1（同一則不會
 * 算兩次）。分類器失敗／沒有這個欄位時傳 `false`＝不補分。
 *
 * 連續 `OFFENSE_DECAY_CLEAN_TURNS` 輪完全沒加分就歸零；`blocked` 不衰減。
 */
export function offenseStateAfter(
  prev: OffenseState,
  turn: OffenseTurn,
  classifierOverstep: boolean,
): OffenseState & { readonly source: OffenseSource } {
  if (turn.wasBlocked) return { ...prev, source: null };
  const classifierScored = turn.delta === 0 && classifierOverstep;
  const strikes = turn.strikes + (classifierScored ? 1 : 0);
  const source: OffenseSource = classifierScored ? "classifier" : turn.source;
  const servedStage = turn.servedStage;
  // 封鎖不衰減、也不再累計。
  if (servedStage >= 3) {
    return { strikes, cleanStreak: 0, servedStage: 3, blocked: true, source };
  }
  if (source === null) {
    const cleanStreak = prev.cleanStreak + 1;
    return cleanStreak >= OFFENSE_DECAY_CLEAN_TURNS
      ? {
        strikes: 0,
        cleanStreak: 0,
        servedStage: 0,
        blocked: false,
        source: null,
      }
      : { strikes, cleanStreak, servedStage, blocked: false, source: null };
  }
  return { strikes, cleanStreak: 0, servedStage, blocked: false, source };
}

/**
 * 這一輪 chat system prompt 當輪尾巴要注入的那一行（累計 1 的冷回格）。
 * 只有旗標開著且 `stage === "cold"` 時才會被接上去。
 */
export const OFFENSE_COLD_GUIDANCE =
  "\n\n這一輪還有一件事（hidden guidance，不要向對方提及）：他最新那句在推性／身體的界線。這輪冷淡、不順著他，可以短短反問或酸一句；不解釋、不說教，也不要說什麼封鎖、刪除、檢舉。";
