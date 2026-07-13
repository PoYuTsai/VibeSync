// 教練拆解卡 JSON 解析（純函式、可 deno test）。
// 防御性：去 markdown 圍欄、缺核心欄位丟出、vibe 非法則回退「中性」、長度 clamp。

import {
  rejectL4UnsafeVisibleText,
  rejectVisibleInternalLabelLeak,
  rejectVisibleTemperatureMechanismLeak,
} from "./visible_text_guard.ts";
import { temperatureBandFor } from "./temperature.ts";
import type { AppliedHintTurn, PracticeTurn } from "./validate.ts";
import { latestAssistantShowsHostility } from "./conversation_signals.ts";
import {
  assertPracticeTextGroundedInTurns,
  isGenericPracticeComplimentOrEcho,
  normalizedPracticeText,
  rejectGenericPasteablePracticeText,
  rejectKnownCannedPracticeText,
} from "./practice_visible_quality.ts";
import {
  type PracticeInviteLevel,
  practiceInviteLevelFor,
} from "./practice_invite.ts";
import {
  assertHintFactClaimsSupported,
  buildHintFactContext,
  type HintFactClaim,
} from "./hint_fact_ledger.ts";

export const VIBES = ["暖", "中性", "冷"];
export const DATE_CHANCES = ["low", "medium", "high"];
export const DEBRIEF_QUALITY_SCHEMA_VERSION = "typed-facts-v1";

export interface GameBreakdown {
  phaseReached: string;
  missedVariable: string;
  failureState: string;
  nextFirstLine: string;
  inviteDirection: string;
}

const GENERATED_DEBRIEF_PROSE_MAX_LENGTH = 120;
const GENERATED_DEBRIEF_LIST_ITEM_MAX_LENGTH = 100;
const GENERATED_GAME_BREAKDOWN_MAX_LENGTH = 140;

export interface DebriefCard {
  summary: string;
  strengths: string[];
  watchouts: string[];
  suggestedLine: string;
  vibe: string;
  /** 約出來機會：low｜medium｜high。 */
  dateChance: string;
  dateChanceReason: string;
  nextInviteMove: string;
  gameBreakdown: GameBreakdown | null;
}

/** fallback 卡上會隨溫度檔位變化的欄位（其餘欄位維持各路徑罐頭）。 */
interface FallbackChanceTone {
  vibe: string;
  dateChance: string;
  dateChanceReason: string;
  nextInviteMove: string;
  /** Game breakdown 的邀約方向；neutral 檔沿用各路徑罐頭。 */
  inviteDirection: string | null;
}

function fallbackTranscriptSignals(turns?: PracticeTurn[]): {
  userTurnCount: number;
  questionCount: number;
  selfShareCount: number;
} {
  const userTurns = (turns ?? []).filter((turn) => turn.role === "user");
  return {
    userTurnCount: userTurns.length,
    questionCount: userTurns.filter((turn) => /[?？]/u.test(turn.text)).length,
    selfShareCount:
      userTurns.filter((turn) =>
        /(?:^|[，。！？!?\s])我(?:也|會|覺得|喜歡|平常|最近|今天|自己|剛|其實|有)/u
          .test(turn.text)
      ).length,
  };
}

function latestAssistantText(turns?: PracticeTurn[]): string {
  for (let index = (turns?.length ?? 0) - 1; index >= 0; index--) {
    if (turns?.[index]?.role === "ai") return turns[index].text;
  }
  return "";
}

function appliedHintFollowUpLine(turns?: PracticeTurn[]): string {
  const latest = latestAssistantText(turns).normalize("NFKC").toLowerCase();
  // Prefer the concrete topic over broad energy words: 「忙著準備演唱會」
  // and 「休息時找餐廳」 are topic openings, not evidence that she is tired.
  if (/(?:咖啡|拿鐵|美式|手沖|咖啡廳)/u.test(latest)) {
    return "妳剛提到咖啡，我自己偏愛有香氣、不太甜的；妳通常喝哪一種？";
  }
  if (/(?:電影|影集|戲劇|影片|片單|紀錄片|動畫片|netflix)/u.test(latest)) {
    return "妳剛提到電影，我最近比較愛節奏俐落的故事；妳通常看哪一類？";
  }
  if (/(?:旅行|旅遊|出國|日本|韓國|行程)/u.test(latest)) {
    return "妳剛提到旅行，我自己喜歡慢慢逛小店；妳會排滿行程還是隨興走？";
  }
  if (/(?:音樂|歌|演唱會|樂團)/u.test(latest)) {
    return "妳剛提到音樂，我最近也在挖新歌；妳最常重播哪一首？";
  }
  if (
    /(?:餐廳|甜點|宵夜|料理|美食|吃飯|吃了|想吃|好吃|難吃|小吃|早餐|午餐|晚餐)/u
      .test(latest)
  ) {
    return "妳剛提到吃的，我自己最容易被有特色的小店吸引；妳最近有私藏嗎？";
  }
  if (/(?:新工作|換(?:了)?工作|轉職|升遷|新職位)/u.test(latest)) {
    return "換新工作是個不小的變化，聽起來妳很開心；妳現在最期待哪一部分？";
  }
  if (
    /(?:好累|很累|超累|太累|累死|有點累|疲倦|疲累|沒精神|想睡|睏|加班|忙到|忙翻|忙爆|忙死|忙不過來|想(?:先)?休息|需要休息|先去休息|回家休息)/u
      .test(latest)
  ) {
    return "聽起來妳今天真的累了，先好好休息；等妳有空我們再聊。";
  }
  if (/(?:今天|最近|這陣子).{0,5}(?:很忙|好忙|超忙|事情很多)/u.test(latest)) {
    return "聽起來妳今天事情很多，先忙妳的；等妳有空我們再聊。";
  }
  return "妳剛說的那個點我有記住，我先分享我的版本，再聽妳的。";
}

function boundaryRepairFallbackCard(practiceMode?: string): DebriefCard {
  const suggestedLine = "抱歉讓妳不舒服了，我會尊重妳的意思，不再打擾。";
  return {
    summary: "她已明確要求停下來，這場先收住；現在最重要的是尊重她的界線。",
    strengths: ["這次能清楚看見她的界線"],
    watchouts: ["不要再追問、辯解或另找話題"],
    suggestedLine,
    vibe: "冷",
    dateChance: "low",
    dateChanceReason: "她已要求停止聯絡，現在沒有適合邀約或繼續推進的窗口。",
    nextInviteMove: "不邀約，也不要再追訊息；真誠道歉後給她完整空間。",
    gameBreakdown: practiceMode === "game"
      ? {
        phaseReached: "界線修復",
        missedVariable: "安全感",
        failureState: "她已明確要求停下來",
        nextFirstLine: suggestedLine,
        inviteDirection: "停止推進，不邀約，給她完整空間。",
      }
      : null,
  };
}

/**
 * 溫度檔位 → fallback 卡語氣（分檔唯一依據＝temperatureBandFor 五檔）。
 * 溫度缺席或非法時回 null＝fail-safe 維持現行中性罐頭；可見文字絕不
 * 提及溫度機制或內部詞，只改語氣與機會判斷。
 */
function fallbackChanceToneFor(
  temperatureScore: number | undefined,
): FallbackChanceTone | null {
  if (
    temperatureScore === undefined || !Number.isFinite(temperatureScore)
  ) {
    return null;
  }
  const band = temperatureBandFor(temperatureScore);
  if (band === "frozen" || band === "cold") {
    return {
      vibe: "冷",
      dateChance: "low",
      dateChanceReason: "這場收在她比較保留的狀態，先把安全感補回來比較實際。",
      nextInviteMove:
        "先不約，下一句降壓接住她說過的點，等她願意多說再看窗口。",
      inviteDirection: "先不約，降壓接住她說過的點，等她願意多說再看窗口。",
    };
  }
  if (band === "warm") {
    return {
      vibe: "暖",
      dateChance: "medium",
      dateChanceReason:
        "她的投入有起來，開始鋪一個具體的低壓邀約窗口正是時候。",
      nextInviteMove:
        "下一句先呼應她聊得起勁的點，再丟一個改天短聚的低壓窗口。",
      inviteDirection: "先呼應她聊得起勁的點，再丟一個改天短聚的低壓窗口。",
    };
  }
  if (band === "hot") {
    return {
      vibe: "暖",
      dateChance: "high",
      dateChanceReason: "她整場投入感很高，窗口已經開了，可以往具體邀約收。",
      nextInviteMove:
        "把她感興趣的話題收成一個具體的小邀約，時間短、好答應也好拒絕。",
      inviteDirection:
        "把她感興趣的話題收成具體小邀約，時間短、好答應也好拒絕。",
    };
  }
  return null;
}

export function buildFallbackDebriefCard(
  opts: {
    practiceMode?: string;
    appliedHintTurns?: AppliedHintTurn[];
    temperatureScore?: number;
    turns?: PracticeTurn[];
  } = {},
): DebriefCard {
  const tone = fallbackChanceToneFor(opts.temperatureScore);
  if (latestAssistantShowsHostility(latestAssistantText(opts.turns))) {
    return boundaryRepairFallbackCard(opts.practiceMode);
  }
  const hasAppliedHint = (opts.appliedHintTurns?.length ?? 0) > 0;
  if (hasAppliedHint) {
    const hasExactHint = opts.appliedHintTurns?.some((hint) => hint.exact) ??
      false;
    const suggestedLine = appliedHintFollowUpLine(opts.turns);
    return {
      summary: hasExactHint
        ? "你有照提示接住她，這步是對的；只是這個提示偏保守，能穩住對話，但推進投入感有限。"
        : "你有參考提示接住她，但這句已經被你改寫；下一步要看改寫有沒有加壓或偏題。",
      strengths: [
        hasExactHint ? "有照提示承接她的回覆" : "有參考提示延續對話",
      ],
      watchouts: [
        hasExactHint
          ? "提示偏保守，需要補自己的感受"
          : "改寫後要避免加壓或偏題",
      ],
      suggestedLine,
      vibe: tone?.vibe ?? "中性",
      dateChance: tone?.dateChance ?? "low",
      dateChanceReason: tone?.dateChanceReason ??
        "目前比較像穩住話題，還沒看到足夠投入或明確窗口。",
      nextInviteMove: tone?.nextInviteMove ??
        "先不急約，下一句補自己的感受；如果她接住，再丟低壓邀約窗口。",
      gameBreakdown: opts.practiceMode === "game"
        ? {
          phaseReached: "開場到測試",
          missedVariable: "投入感",
          failureState: "提示偏保守",
          nextFirstLine: suggestedLine,
          inviteDirection: tone?.inviteDirection ??
            "先補感受與投入，再接低壓邀約窗口。",
        }
        : null,
    };
  }
  const signals = fallbackTranscriptSignals(opts.turns);
  const mostlyQuestions = signals.questionCount >= 2 &&
    signals.questionCount * 2 >= Math.max(1, signals.userTurnCount);
  const hasSelfShare = signals.selfShareCount > 0;
  const hasInviteWindow = tone?.dateChance === "medium" ||
    tone?.dateChance === "high";
  const suggestedLine = hasInviteWindow
    ? "妳剛說的那個點我有興趣，改天找 30 分鐘喝杯咖啡，妳方便再說。"
    : mostlyQuestions
    ? "我先補我的版本：最近我最容易被有畫面的細節吸引，妳剛說的我有記住。"
    : "我對妳剛說的那個點有點好奇，我先說我的版本，再聽妳的。";
  const summary = hasInviteWindow
    ? "她有持續投入這段互動，下一步可以把窗口收成具體又低壓的邀約。"
    : mostlyQuestions
    ? "這場有把話接下去，但問句比較密；下一步先補自己的感受再把球給她。"
    : hasSelfShare
    ? "你有分享自己的狀態，也有順著她回覆；下一步再把她的反應接深一點。"
    : "你有把對話延續下來；下一步抓住她的具體細節，再補一點自己的感受。";
  const strength = hasInviteWindow
    ? "有讓她持續投入互動"
    : hasSelfShare
    ? "有分享自己的狀態"
    : "有順著她的回覆接話";
  const watchout = hasInviteWindow
    ? "邀約要具體、低壓且保留拒絕空間"
    : mostlyQuestions
    ? "問句偏密，先補自己的感受"
    : "別只停在問答，補一個自己的觀點";
  const gamePhaseReached = hasInviteWindow ? "邀約窗口已出現" : "互動建立中";
  const gameMissedVariable = hasInviteWindow
    ? "收尾具體度"
    : mostlyQuestions
    ? "自己的觀點"
    : hasSelfShare
    ? "承接她的反應"
    : "互相投入";
  const gameFailureState = hasInviteWindow
    ? "還沒把窗口收成行動"
    : mostlyQuestions
    ? "問句偏密"
    : hasSelfShare
    ? "她的反應接得不夠深"
    : "話題仍偏表面";
  return {
    summary,
    strengths: [strength],
    watchouts: [watchout],
    suggestedLine,
    vibe: tone?.vibe ?? "中性",
    dateChance: tone?.dateChance ?? "low",
    dateChanceReason: tone?.dateChanceReason ??
      "熟悉度還在建立中，先把話題聊開比較穩。",
    nextInviteMove: tone?.nextInviteMove ??
      "先接她的答案，再分享一點自己的感受。",
    gameBreakdown: opts.practiceMode === "game"
      ? {
        phaseReached: gamePhaseReached,
        missedVariable: gameMissedVariable,
        failureState: gameFailureState,
        nextFirstLine: suggestedLine,
        inviteDirection: tone?.inviteDirection ??
          "先不急約，接她興趣後再丟低壓窗口。",
      }
      : null,
  };
}

export function clampStr(v: unknown, max: number): string {
  return typeof v === "string" ? v.trim().slice(0, max) : "";
}

export function clampList(
  v: unknown,
  maxItems: number,
  maxLen: number,
): string[] {
  if (!Array.isArray(v)) return [];
  return v
    .map((x) => clampStr(x, maxLen))
    .filter((x) => x.length > 0)
    .slice(0, maxItems);
}

function generatedVisibleString(
  value: unknown,
  legacyMax: number,
  generatedMax: number,
  enforceGeneratedQuality: boolean,
): string {
  if (typeof value !== "string") return "";
  const trimmed = value.trim();
  if (enforceGeneratedQuality && trimmed.length > generatedMax) {
    throw new Error("debrief_quality_invalid_overlong");
  }
  return enforceGeneratedQuality ? trimmed : trimmed.slice(0, legacyMax);
}

function generatedVisibleList(
  value: unknown,
  maxItems: number,
  legacyMaxLength: number,
  generatedMaxLength: number,
  enforceGeneratedQuality: boolean,
): string[] {
  if (!Array.isArray(value)) return [];
  if (!enforceGeneratedQuality) {
    return clampList(value, maxItems, legacyMaxLength);
  }
  return value.slice(0, maxItems)
    .map((item) =>
      generatedVisibleString(
        item,
        legacyMaxLength,
        generatedMaxLength,
        enforceGeneratedQuality,
      )
    )
    .filter((item) => item.length > 0);
}

function rejectInternalLabelLeak(value: string) {
  rejectVisibleInternalLabelLeak(value, "debrief_internal_label_leak");
}

function guardVisibleText(value: string): string {
  rejectInternalLabelLeak(value);
  // 批3 P1：debrief prompt 注入 band 詞後，模型可能把溫度內部詞或 1.2 原詞
  // 抄進可見欄位；被拒→handler 重試→band-aware fallback 卡兜底。
  rejectVisibleTemperatureMechanismLeak(value, "debrief_temperature_leak");
  rejectL4UnsafeVisibleText(value, "debrief_l4_unsafe");
  return value;
}

function parseGameBreakdown(
  value: unknown,
  enforceGeneratedQuality: boolean,
): GameBreakdown {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new Error("debrief_game_breakdown_missing_fields");
  }
  const p = value as Record<string, unknown>;
  const gameBreakdown = {
    phaseReached: guardVisibleText(
      generatedVisibleString(
        p.phaseReached,
        60,
        GENERATED_GAME_BREAKDOWN_MAX_LENGTH,
        enforceGeneratedQuality,
      ),
    ),
    missedVariable: guardVisibleText(
      generatedVisibleString(
        p.missedVariable,
        60,
        GENERATED_GAME_BREAKDOWN_MAX_LENGTH,
        enforceGeneratedQuality,
      ),
    ),
    failureState: guardVisibleText(
      generatedVisibleString(
        p.failureState,
        60,
        GENERATED_GAME_BREAKDOWN_MAX_LENGTH,
        enforceGeneratedQuality,
      ),
    ),
    nextFirstLine: guardVisibleText(
      generatedVisibleString(
        p.nextFirstLine,
        70,
        GENERATED_GAME_BREAKDOWN_MAX_LENGTH,
        enforceGeneratedQuality,
      ),
    ),
    inviteDirection: guardVisibleText(
      generatedVisibleString(
        p.inviteDirection,
        60,
        GENERATED_GAME_BREAKDOWN_MAX_LENGTH,
        enforceGeneratedQuality,
      ),
    ),
  };
  if (Object.values(gameBreakdown).some((field) => field.length === 0)) {
    throw new Error("debrief_game_breakdown_missing_fields");
  }
  return gameBreakdown;
}

function debriefVisibleFields(card: DebriefCard): string[] {
  return [
    card.summary,
    ...card.strengths,
    ...card.watchouts,
    card.suggestedLine,
    card.dateChanceReason,
    card.nextInviteMove,
    ...(card.gameBreakdown
      ? [
        card.gameBreakdown.phaseReached,
        card.gameBreakdown.missedVariable,
        card.gameBreakdown.failureState,
        card.gameBreakdown.nextFirstLine,
        card.gameBreakdown.inviteDirection,
      ]
      : []),
  ];
}

function hasCompleteHintDecision(hint: AppliedHintTurn): boolean {
  const decision = hint.decision;
  return decision !== undefined &&
    [
      decision.phase,
      decision.targetVariable,
      decision.move,
      decision.inviteRoute,
      decision.rationale,
    ].every((field) => typeof field === "string" && field.trim().length > 0);
}

type HintStrategyRoute = "repair" | "build" | "soft" | "direct";

function authoritativeHintRoute(hint: AppliedHintTurn): HintStrategyRoute {
  const decision = hint.decision!;
  const route = `${decision.inviteRoute} ${decision.move}`.toLowerCase();
  if (/(?:repair|safety|降壓|修復|停止)/u.test(route)) return "repair";
  if (/(?:direct|明確邀約|直接邀約)/u.test(route)) return "direct";
  if (/(?:soft|低壓邀約|試探邀約)/u.test(route)) return "soft";
  return "build";
}

/**
 * Reads explicit strategy claims, not ordinary retrospective prose. Ordering
 * matters: 「先累積投入，等她再接才丟窗口」is a build route even though it
 * mentions a later invitation.
 */
function explicitNarrativeRoute(value: string): HintStrategyRoute | null {
  const text = value.normalize("NFKC").replace(/\s+/gu, "");
  if (
    /(?:先|需要|應該|這輪|現在).{0,10}(?:道歉|降壓|修復|修補安全|停下|退開)|(?:停止|不要|不再).{0,8}(?:推進|邀約|打擾)/u
      .test(text)
  ) {
    return "repair";
  }
  if (
    /(?:先|這輪|現在|目前).{0,12}(?:不約|不急著約|別急著約|不硬約|不適合約|鋪墊|累積|建立|延伸|補足|補感受|補投入|熟悉|安全|穩住)|(?:先不要|先別|暫時不要|不要|別|不急著).{0,4}(?:約她|邀她|約對方|邀對方|問她(?:哪天|何時|什麼時候).{0,6}有空|定.{0,4}時間)|(?:還要|還需|需要)?再.{0,6}(?:累積|建立|延伸|補足|補感受|補投入|穩住)|等.{0,14}(?:再|才).{0,12}(?:約|邀|窗口)|(?:還沒|尚未|未到).{0,10}(?:窗口|時機)|(?:邀約)?窗口(?:還沒|尚未|仍未)(?:開|成熟)|先.{0,14}再.{0,12}(?:約|邀|窗口)/u
      .test(text)
  ) {
    return "build";
  }
  if (
    /(?:沒有|沒)(?:做|給|丟|推)?(?:出)?(?:直接|明確)?邀約.{0,10}(?:失誤|錯|問題|可惜)|(?:太被動|偏保守|早該).{0,12}(?:直接)?(?:約|邀約)|(?:現在|這輪|下一句|下一步|接下來|應該|可以|建議|不妨|適合|立刻|趁現在).{0,12}(?:直接|明確)?(?:約她|邀她|約對方|邀對方|問她(?:哪天|何時|什麼時候).{0,6}有空|把.{1,12}收成.{0,4}(?:見面|咖啡|邀約)|去(?:喝咖啡|吃飯|散步|看展|逛街))|(?:直接|明確|立刻|趁現在)(?:約|邀約)|(?:約|邀約).{0,8}(?:時機|窗口)(?:已經)?成熟/u
      .test(text)
  ) {
    return "direct";
  }
  if (
    /(?:低壓|試探|模糊|輕量)(?:約|邀約)|(?:丟|開|給).{0,6}(?:低壓|試探|短聚|短咖啡)?窗口|短(?:咖啡|聚).{0,6}(?:邀約|窗口)/u
      .test(text)
  ) {
    return "soft";
  }
  return null;
}

function strategyBearingFields(card: DebriefCard): string[] {
  return [
    card.summary,
    ...card.watchouts,
    card.suggestedLine,
    card.nextInviteMove,
    ...(card.gameBreakdown
      ? [
        card.gameBreakdown.failureState,
        card.gameBreakdown.nextFirstLine,
        card.gameBreakdown.inviteDirection,
      ]
      : []),
  ];
}

function inviteLevelContradicts(
  authoritative: HintStrategyRoute,
  actual: PracticeInviteLevel,
): boolean {
  if (actual === "none") return false;
  if (authoritative === "repair" || authoritative === "build") return true;
  return authoritative === "soft" && actual === "direct";
}

function cardContradictsHintStrategy(
  card: DebriefCard,
  appliedHintTurns: AppliedHintTurn[],
): boolean {
  const latestHint = appliedHintTurns.reduce((latest, hint) =>
    hint.turnIndex >= latest.turnIndex ? hint : latest
  );
  const authoritative = authoritativeHintRoute(latestHint);
  const narrativeRoutes = strategyBearingFields(card)
    .map(explicitNarrativeRoute)
    .filter((route): route is HintStrategyRoute => route !== null);
  if (narrativeRoutes.some((route) => route !== authoritative)) return true;

  const pasteableInviteLevels = [
    practiceInviteLevelFor(card.suggestedLine),
    ...(card.gameBreakdown
      ? [practiceInviteLevelFor(card.gameBreakdown.nextFirstLine)]
      : []),
  ];
  return pasteableInviteLevels.some((level) =>
    inviteLevelContradicts(authoritative, level)
  );
}

const PRESERVED_HINT_CRITIQUE_PATTERN =
  /(?:只(?:回|問|停)|只是.{0,8}(?:禮貌|收尾|附和)|禮貌收尾|停在|沒給球|沒有給.{0,8}(?:球|接球|空間)|球(?:沒有|沒)丟回|(?:沒有|沒)丟回|沒有接|沒接住|很難繼續|查戶口|盤問|偏保守|太保守|太客套|客套|無效|扣分|沒留(?:接點|鉤子)|沒有留(?:接點|鉤子|回應空間)|沒有把話題往前帶|回覆收得太乾淨|互動斷在這裡|像把門關上|收得太死|沒有延伸|缺少鉤子|少了.{0,8}(?:鉤子|接點|溫度|生活感|畫面)|缺乏.{0,8}(?:鉤子|接點|溫度|生活感|畫面)|(?:容易)?冷場|(?:讓人)?接不下去|敷衍|平庸|話題.{0,4}句點|像句點|封閉話題|讓對話停住|把.{0,10}話題聊死|沒有讓對話延續|太乾|收尾感太重|對話沒有出口|沒有留下下一球|很難接下去)/u;

type PreservedHintCritiqueMatch = {
  index: number;
  text: string;
};

function preservedHintCritiqueMatches(
  compact: string,
): PreservedHintCritiqueMatch[] {
  const globalPattern = new RegExp(
    PRESERVED_HINT_CRITIQUE_PATTERN.source,
    `${PRESERVED_HINT_CRITIQUE_PATTERN.flags}g`,
  );
  return [...compact.matchAll(globalPattern)].map((match) => ({
    index: match.index,
    text: match[0],
  }));
}

function lastPatternIndex(text: string, pattern: RegExp): number {
  let latest = -1;
  for (const match of text.matchAll(pattern)) {
    if (match.index !== undefined) latest = match.index;
  }
  return latest;
}

function lastPartnerSubjectIndex(text: string): number {
  return lastPatternIndex(
    text,
    /(?:^|[，,:：；;]|但|不過|可是|然而|(?:做)?後|目前|這輪|從|結果|最後|當下|現在)(?:目前|最後|後來|仍然|只|現在|這次)?(?:她|對方)/gu,
  );
}

function hasPartnerRecipientReference(value: string): boolean {
  const compact = normalizedPracticeText(value);
  return /(?:她|對方)(?:收到|看到|讀到|接到|面對)(?:的)?(?:這句|回覆|訊息)/u
    .test(compact);
}

function partnerPerceptionTargetsUserReply(value: string): boolean {
  const compact = normalizedPracticeText(value);
  return /(?:^|[，,:：；;]|但|不過|可是|然而|結果|最後|當下|現在)(?:她|對方).{0,8}(?:覺得|認為|感覺|說|表示).{0,8}(?:你的回覆|你這句|這個回應|這個回答|這句|回覆|回答|訊息)/u
    .test(compact);
}

function hasPartnerSubject(value: string): boolean {
  return value.split(/[。！？；;，,:：\n]+/u).some((clause) =>
    !hasPartnerRecipientReference(clause) &&
    !partnerPerceptionTargetsUserReply(clause) &&
    lastPartnerSubjectIndex(normalizedPracticeText(clause)) >= 0
  );
}

function critiqueClearlyTargetsPartner(
  compact: string,
  criticalIndex: number,
): boolean {
  const prefix = compact.slice(0, criticalIndex);
  if (hasPartnerRecipientReference(prefix)) return false;
  if (partnerPerceptionTargetsUserReply(prefix)) return false;
  if (
    /(?:她|對方)(?:看完|讀完|收到後|看到後).{0,6}(?:覺得|認為|感覺)/u
      .test(prefix)
  ) {
    return false;
  }
  if (
    /(?:她|對方).{0,12}(?:對|看到|收到|讀到|接到)(?:了)?你的回覆(?:後)?.{0,8}(?:覺得|認為|感覺|嫌|評為)/u
      .test(prefix)
  ) {
    return false;
  }
  if (
    /(?:她|對方).{0,8}(?:對|看到|收到|讀到|接到)(?:了)?你的回覆(?:後)?/u
      .test(prefix)
  ) {
    return true;
  }
  const partnerSubjectIndex = lastPartnerSubjectIndex(prefix);
  const userOrHintIndex = lastPatternIndex(
    prefix,
    /(?:照提示|照貼|提示那句|原本提示|提示|hint|你的回覆|你這句|你剛才|你剛剛|你後來|使用者|這個回應|剛才那句|剛剛那句|你)/giu,
  );
  return partnerSubjectIndex > userOrHintIndex;
}

function critiqueIsNegatedPraise(
  compact: string,
  criticalIndex: number,
): boolean {
  const prefix = compact.slice(0, criticalIndex);
  return /(?:(?:沒有|沒|不會|不是|不像|並非|避免|不算).{0,5}|(?:不只|不僅)(?:是)?.{0,8}|不)$/u
    .test(prefix);
}

function critiqueClearlyTargetsAnotherUserTurn(
  clause: string,
  turns: PracticeTurn[] | undefined,
  appliedHintTurns: AppliedHintTurn[],
): boolean {
  const compact = normalizedPracticeText(clause);
  if (/(?:照提示|照貼|提示那句|hint)/iu.test(compact)) return false;
  if (
    /(?:提示前|照貼前|前一(?:句|輪|則)|上一(?:句|輪|則)|前面那句|第[一二三四五六七八九十\d]+句)/u
      .test(compact)
  ) {
    return true;
  }
  const latestHintIndex = Math.max(
    ...appliedHintTurns.map((hint) => hint.turnIndex),
  );
  const laterUserTurns = (turns ?? []).filter((turn, index) =>
    index > latestHintIndex && turn.role === "user"
  );
  if (laterUserTurns.length === 0) return false;
  if (/(?:你後來|後來你|下一輪你|提示後你又)/u.test(compact)) return true;
  return laterUserTurns.some((turn) => {
    const laterText = normalizedPracticeText(turn.text);
    return laterText.length >= 2 && compact.includes(laterText);
  });
}

function hasForwardCoachingScope(value: string): boolean {
  const compact = normalizedPracticeText(value);
  return /^(?:下一步|下次|接下來|之後|後續|先|接著|等她|延續|沿著|順著|可以|建議|不妨|記得)/u
    .test(
      compact,
    ) ||
    /(?:可以再|可再|還能再|再補|再加|先(?:觀察|等|延續|補|聊|接|看)|(?:邀約)?窗口(?:還沒|尚未|仍未)(?:開|成熟).{0,10}(?:繼續|先|再)(?:累積|延續|建立|多聊))/u
      .test(compact);
}

function debriefAnalyticalFields(card: DebriefCard): string[] {
  return [
    card.summary,
    ...card.strengths,
    ...card.watchouts,
    card.dateChanceReason,
    card.nextInviteMove,
    ...(card.gameBreakdown
      ? [
        card.gameBreakdown.phaseReached,
        card.gameBreakdown.missedVariable,
        card.gameBreakdown.failureState,
        card.gameBreakdown.inviteDirection,
      ]
      : []),
  ];
}

function isVagueDebriefTopicAction(value: string): boolean {
  const compact = normalizedPracticeText(value);
  const hasThinForwardAction =
    /(?:下一步|下次|接下來|之後|後續|接著|繼續|可以|建議|不妨).{0,8}(?:問|聊|延伸|接住|接)|^(?:接著|繼續|再)(?:問|聊|延伸|接住|接)/u
      .test(compact);
  const hasConcreteMethodOrTarget =
    /(?:哪|什麼|怎麼|為什麼|最常|偏好|感受|原因|畫面|時間|時段|哪一|哪裡|幾|自己的|交換|回呼|選擇|如果|等她|看她|再看|因為|別|不要|避免|改成|換成|一句|一個|二選一|生活習慣)/u
      .test(compact);
  return hasThinForwardAction && !hasConcreteMethodOrTarget &&
    compact.length <= 24;
}

function isGenericDebriefDateReason(value: string): boolean {
  const compact = normalizedPracticeText(value);
  const onlyRestatesSharing =
    /^(?:她|對方)(?:願意|有)?(?:說|分享|聊)(?:了)?(?:自己)?(?:住)?[\p{Script=Han}a-z0-9]{1,28}$/u
      .test(compact);
  const explainsReadiness =
    /(?:但|不過|所以|而且|同時|開玩笑|回問|窗口|時間|時段|見面|邀|投入|拒絕|冷|短|主動|延伸|接球|多聊)/u
      .test(compact);
  return onlyRestatesSharing && !explainsReadiness;
}

function assertGeneratedDebriefFieldSubstance(card: DebriefCard): void {
  const summary = normalizedPracticeText(card.summary);
  if (
    /(?:這個)?(?:話題|資訊)(?:有)?(?:接到|聊到|回應到|延伸到)$/u.test(
      summary,
    )
  ) {
    throw new Error("debrief_quality_invalid_summary_substance");
  }

  for (const strength of card.strengths) {
    const compact = normalizedPracticeText(strength);
    const onlyRestatesAcknowledge = /(?:接到|接住|承接|回應)/u.test(compact) &&
      !/(?:讓|所以|因此|沒有|避免|變成|延伸|分享自己|提問|問句|畫面|幽默|選擇|具體|降低|保留|回呼|交換|自己的)/u
        .test(compact);
    if (onlyRestatesAcknowledge) {
      throw new Error("debrief_quality_invalid_strength_substance");
    }
  }

  for (const watchout of card.watchouts) {
    if (isVagueDebriefTopicAction(watchout)) {
      throw new Error("debrief_quality_invalid_watchout_substance");
    }
  }

  if (isGenericPracticeComplimentOrEcho(card.suggestedLine)) {
    throw new Error("debrief_quality_invalid_suggested_line");
  }
  if (isGenericDebriefDateReason(card.dateChanceReason)) {
    throw new Error("debrief_quality_invalid_date_reason_substance");
  }
  if (isVagueDebriefTopicAction(card.nextInviteMove)) {
    throw new Error("debrief_quality_invalid_next_move_substance");
  }
}

function partnerTurnContainsInviteEvidence(value: string): boolean {
  const compact = normalizedPracticeText(value);
  return practiceInviteLevelFor(value) !== "none" ||
    /(?:約|邀)[妳你]|要不要.{0,8}一起|(?:跟|和)[妳你].{0,10}(?:見面|碰面|喝咖啡|吃飯|散步|看展|逛街)/u
      .test(compact);
}

function claimsPartnerInitiatedInvite(value: string): boolean {
  const compact = normalizedPracticeText(value);
  if (
    /(?:還沒|尚未|沒有|沒|未|不).{0,12}(?:見面|碰面|邀約|約|邀)/u.test(
      compact,
    )
  ) {
    return false;
  }
  return /(?:她|對方).{0,28}(?:主動(?:提(?:了|出)?|說|問|給|丟|發出)?|(?:提(?:了|出)?|說想|說要|問|給|丟|發出|表示想|想|要|願意)).{0,12}(?:見面|碰面|邀約|約你|邀你)/u
    .test(compact) ||
    /(?:她|對方)的.{0,10}(?:邀約|見面提議|約見)/u.test(compact);
}

function assertNoInventedPartnerInitiative(
  card: DebriefCard,
  turns: PracticeTurn[] | undefined,
): void {
  if (!debriefVisibleFields(card).some(claimsPartnerInitiatedInvite)) return;
  const hasPartnerInviteEvidence = (turns ?? []).some((turn) =>
    turn.role === "ai" && partnerTurnContainsInviteEvidence(turn.text)
  );
  if (!hasPartnerInviteEvidence) {
    throw new Error("debrief_quality_invalid_partner_initiative");
  }
}

function assertGeneratedDebriefFieldRoles(card: DebriefCard): void {
  const summary = normalizedPracticeText(card.summary);
  if (
    !/(?:你|使用者|她|對方|雙方|提示|回覆|這句|話題|梗).{0,18}(?:接|回|問|提|說|分享|延伸|交換|照|聊|停|投入|開玩笑|升溫|降溫)|(?:這輪|本輪|對話|互動).{0,24}(?:接|回|問|提|說|分享|延伸|交換|照|聊|投入|開玩笑|升溫|降溫)|(?:接|回|問|提|說|分享|延伸|交換|照|聊|停|投入).{0,18}(?:她|對方|話題|梗|提示|回覆)/u
      .test(summary)
  ) {
    throw new Error("debrief_quality_invalid_summary_role");
  }

  for (const strength of card.strengths) {
    if (
      !/(?:你|使用者|回覆|這句|提示|有照|有接|接住|承接|延伸|分享|提問|問句|把.{0,12}變成|梗有延續)/u
        .test(normalizedPracticeText(strength))
    ) {
      throw new Error("debrief_quality_invalid_strength_role");
    }
  }

  for (const watchout of card.watchouts) {
    if (
      !/(?:下一步|下次|接下來|可以|建議|不妨|記得|先|再|少|多留|多放|補|問|分享|延伸|接|回|改|換|等|別|不要)/u
        .test(normalizedPracticeText(watchout)) ||
      /^(?:可以|建議|不妨)?(?:增加|加強|提升)(?:一點)?(?:投入感|生活感|互動感|熟悉感)[。！]?$/u
        .test(normalizedPracticeText(watchout))
    ) {
      throw new Error("debrief_quality_invalid_watchout_role");
    }
  }

  const dateReason = normalizedPracticeText(card.dateChanceReason);
  if (
    !/(?:她|對方).{0,20}(?:回|問|提|說|分享|延伸|接|開玩笑|主動|願意|拒絕|冷|短)|雙方.{0,16}(?:提|聊|分享|交換)|(?:尚未|還沒|還沒有|沒有|未見|仍未).{0,12}(?:窗口|見面|時間|意願|投入|訊號)|(?:窗口|時間|意願|投入).{0,10}(?:出現|明確|不足|不夠|未開|沒開|還沒開|尚未成熟)/u
      .test(dateReason)
  ) {
    throw new Error("debrief_quality_invalid_date_reason_role");
  }

  const nextMove = normalizedPracticeText(card.nextInviteMove);
  if (
    /^(?:先)?(?:累積|建立)(?:一點|更多)?(?:熟悉感|投入感|生活感)?(?:，|再)?(?:再)?找(?:自然)?(?:邀約)?窗口[。！]?$/u
      .test(nextMove) ||
    /^(?:先)?聊.{1,12}(?:，|再)+(?:再)?找(?:自然)?(?:邀約)?窗口[。！]?$/u
      .test(nextMove) ||
    !/(?:問|分享|交換|延伸|接|回|補|改|換|等|看|丟|約|邀|收成|保留|玩|聊)/u
      .test(nextMove)
  ) {
    throw new Error("debrief_quality_invalid_next_move_role");
  }

  const game = card.gameBreakdown;
  if (!game) return;
  if (
    !/(?:階段|開場|熟悉|測試|升溫|邀約|投入|窗口|進度|進到|仍在|已到|到達)/u
      .test(normalizedPracticeText(game.phaseReached))
  ) {
    throw new Error("debrief_quality_invalid_game_phase_role");
  }
  if (
    !/(?:缺|少|不足|不夠|還沒|尚未|未能|沒有|目標|投入|感受|畫面|接點|窗口)/u
      .test(normalizedPracticeText(game.missedVariable))
  ) {
    throw new Error("debrief_quality_invalid_game_variable_role");
  }
  const failure = normalizedPracticeText(game.failureState);
  if (
    /^(?:話題|互動|對話)?.{0,12}(?:目前)?(?:有點)?卡住[。！]?$/u.test(
      failure,
    ) ||
    !/(?:停|卡|斷|冷|硬|表面|問答|失速|無法|沒|未|不足|太|偏|風險|句點|聊死|難接)/u
      .test(failure)
  ) {
    throw new Error("debrief_quality_invalid_game_failure_role");
  }
  const inviteDirection = normalizedPracticeText(game.inviteDirection);
  if (
    /^(?:先)?聊.{1,12}(?:，|再)+(?:再)?找(?:自然)?(?:邀約)?窗口[。！]?$/u
      .test(inviteDirection) ||
    !/(?:問她|分享|交換|延伸|接|補|換|等她|看她|丟|約|邀|收成|保留|玩)/u
      .test(inviteDirection)
  ) {
    throw new Error("debrief_quality_invalid_game_invite_role");
  }
}

function hasNegativeReplyEvaluation(value: string): boolean {
  const compact = normalizedPracticeText(value)
    .replace(
      /(?:沒有|沒|不會|並不|不)(?:造成|帶來|顯得|讓她感到|給她)?(?:太)?(?:加壓|壓力|壓迫|逼迫|逼人|急|用力|突兀|冒進|油膩|刻意)/gu,
      "",
    )
    .replace(
      /(?:沒有|沒|不會|不是|並非)(?:(?:不夠|缺少|欠缺|不足|少了|缺乏)(?:生活感|溫度|鉤子|接點|畫面|具體|有趣|自然|承接|投入|誠意|真誠)|(?:太|過於|偏|顯得|略嫌)?(?:單薄|客套|平淡|乾|冷|硬|制式|普通|尷尬|無聊|敷衍|平庸)|(?:容易)?冷場|(?:讓人)?接不下去)/gu,
      "",
    );
  const target = compact.match(/(?:這句|回覆|訊息|回答)/u);
  const tail = target?.index === undefined
    ? compact
    : compact.slice(target.index + target[0].length);
  if (/(?:不夠|缺少|欠缺|不足|沒有).{1,12}/u.test(tail)) return true;
  if (
    /(?:少了|缺乏).{1,12}|(?:容易)?冷場|(?:讓人)?接不下去|(?:顯得)?敷衍|(?:略嫌)?平庸/u
      .test(tail)
  ) {
    return true;
  }
  if (/(?:像|像是)(?:客服|罐頭|機器|公關|面試|句點|制式)/u.test(tail)) {
    return true;
  }
  if (/(?:很|有點)(?:無聊|平淡|乾|冷|硬|制式|普通|尷尬)/u.test(tail)) {
    return true;
  }
  return /(?:太|過於|偏)(?!好|自然|順|有趣|生動|舒服|真誠|具體|剛好).{1,8}/u
    .test(tail);
}

function hintCreditHasUnscopedAdversative(value: string): boolean {
  const compact = normalizedPracticeText(value);
  const creditPattern =
    /(?:(?:有|已)(?:照|採用|使用)提示|照著提示|照提示|照貼提示|提示那句)/gu;
  for (const credit of compact.matchAll(creditPattern)) {
    const remainder = compact.slice(credit.index + credit[0].length);
    for (
      const adversative of remainder.matchAll(
        /(?:但|不過|可是|然而|卻|只是|唯獨)/gu,
      )
    ) {
      if (
        adversative[0] === "只是" &&
        remainder[adversative.index - 1] === "不"
      ) {
        continue;
      }
      const tail = remainder.slice(adversative.index + adversative[0].length);
      const targetsOtherUserTurn =
        /(?:提示前|照貼前|前一(?:句|輪|則)|上一(?:句|輪|則)|前面那句|你後來|後來你|下一輪你|提示後你又)/u
          .test(tail);
      const isForwardCoaching = hasForwardCoachingScope(tail) &&
        !/(?:照提示|照貼|提示那句|原本提示|hint)/iu.test(tail);
      const describesRouteState =
        /^(?:(?:目前|現在|這輪|現階段)(?:的)?(?:階段|時機|窗口)?|(?:階段|時機|窗口))(?:還|尚|暫時|仍)?(?:不適合|不急|不到|未到|不宜|先不|先別|還沒|尚未).{0,10}(?:邀約|約|見面|推進|升溫|丟窗口)?$/u
          .test(tail) ||
        /^(?:還要|還需|需要)?再(?:累積|建立|延伸|補足|補感受|補投入|穩住).{0,8}$/u
          .test(tail) ||
        /^(?:這輪|現在|目前)?先(?:穩住|延續|累積|建立|補足|補感受|補投入).{0,8}$/u
          .test(tail) ||
        /^(?:邀約)?窗口(?:還沒|尚未|仍未)(?:開|成熟).{0,4}$/u.test(
          tail,
        );
      if (
        hasPartnerSubject(tail) || targetsOtherUserTurn ||
        isForwardCoaching || describesRouteState
      ) {
        continue;
      }
      return true;
    }
  }
  return false;
}

function hasDateOutcomeScope(value: string): boolean {
  const compact = normalizedPracticeText(value);
  if (
    hasPartnerSubject(value) ||
    /(?:目前|這輪|現階段|現在|尚未|還沒|未見|仍未).{0,18}(?:窗口|邀約|見面|投入|回覆|互動|時間|意願)/u
      .test(compact) ||
    /(?:邀約)?窗口(?:尚未|還沒|仍未)(?:出現|開|成熟)/u.test(compact)
  ) {
    return true;
  }
  if (
    /(?:你的回覆|你這句|這句|這個回應)/u.test(compact) &&
    /(?:自然|接住|延續|舒服|有來有往|順|輕鬆|有畫面|有互動|有承接|沒有加壓|不會太急|沒有太用力|不突兀)/u
      .test(compact) &&
    !hasNegativeReplyEvaluation(value)
  ) {
    return true;
  }
  return !/(?:照提示|照貼|提示那句|原本提示|hint|你的回覆|你這句|這句|剛才那句|剛剛那句|這個回應)/iu
    .test(compact);
}

function hasGamePhaseScope(value: string): boolean {
  const compact = normalizedPracticeText(value);
  return hasPartnerSubject(value) ||
    /(?:階段|開場|建立熟悉|熟悉建立|測試|升溫|邀約|投入|窗口|進度|進到|仍在|已到|到達|stage|phase)/iu
      .test(compact);
}

function isObjectiveGameOutcome(value: string): boolean {
  const compact = normalizedPracticeText(value);
  if (
    /(?:照提示|照貼|提示那句|原本提示|hint|你的回覆|你這句|這句|剛才那句|剛剛那句|這個回應)/iu
      .test(compact)
  ) {
    return false;
  }
  return /^(?!把|讓)(?:[\p{Script=Han}A-Za-z0-9·・]{0,10})?(?:話題|互動|對話|節奏)(?:(?:沒有|沒|尚未|還沒|未能|仍未)(?:延伸|繼續|往前|往深處走|升溫|展開|推進|打開|接下去)|(?:停住|中斷|停在表面))(?:了)?$/u
    .test(compact);
}

function preservedCardCritiquesExactHint(
  card: DebriefCard,
  appliedHintTurns: AppliedHintTurn[],
  turns?: PracticeTurn[],
): boolean {
  if (!appliedHintTurns.some((hint) => hint.exact)) return false;
  if (
    [card.summary, ...card.strengths].some(
      hintCreditHasUnscopedAdversative,
    )
  ) {
    return true;
  }
  if (!hasDateOutcomeScope(card.dateChanceReason)) return true;
  if (
    card.gameBreakdown && !hasGamePhaseScope(card.gameBreakdown.phaseReached)
  ) {
    return true;
  }
  const hasClearScope = (value: string): boolean => {
    const compact = normalizedPracticeText(value);
    const forward = hasForwardCoachingScope(value);
    const partner = hasPartnerSubject(value);
    const otherUserTurn =
      /(?:提示前|照貼前|前一(?:句|輪|則)|上一(?:句|輪|則)|前面那句|你後來|後來你|下一輪你|提示後你又)/u
        .test(compact);
    const critiqueMatches = preservedHintCritiqueMatches(compact);
    const explicitPraise = critiqueMatches.length > 0 &&
      critiqueMatches.every((match) =>
        critiqueIsNegatedPraise(compact, match.index)
      );
    return forward || partner || otherUserTurn || explicitPraise;
  };
  const negativeEvaluationFields: Array<{
    value: string;
    allowObjectiveGameOutcome?: boolean;
  }> = [
    { value: card.summary },
    ...card.strengths.map((value) => ({ value })),
    ...card.watchouts.map((value) => ({ value })),
    { value: card.dateChanceReason },
    { value: card.nextInviteMove },
    ...(card.gameBreakdown
      ? [
        { value: card.gameBreakdown.phaseReached },
        {
          value: card.gameBreakdown.missedVariable,
          allowObjectiveGameOutcome: true,
        },
        {
          value: card.gameBreakdown.failureState,
          allowObjectiveGameOutcome: true,
        },
      ]
      : []),
  ];
  if (
    negativeEvaluationFields.some((
      { value: field, allowObjectiveGameOutcome },
    ) =>
      !(allowObjectiveGameOutcome && isObjectiveGameOutcome(field)) &&
      field.split(/[。！？；;\n]+/u).some((clause) =>
        hasNegativeReplyEvaluation(clause) && !hasClearScope(clause)
      )
    )
  ) {
    return true;
  }
  if (card.watchouts.some((field) => !hasClearScope(field))) return true;
  const nextMoveCompact = normalizedPracticeText(card.nextInviteMove);
  const nextMoveNeedsScope =
    preservedHintCritiqueMatches(nextMoveCompact).length > 0 ||
    hasNegativeReplyEvaluation(card.nextInviteMove) ||
    /(?:照提示|照貼|提示那句|原本提示|hint|你的回覆|你這句|這句|剛才那句|剛剛那句|這個回應)/iu
      .test(nextMoveCompact);
  if (nextMoveNeedsScope && !hasClearScope(card.nextInviteMove)) return true;
  const conditionallyScopedGameFields = card.gameBreakdown
    ? [card.gameBreakdown.missedVariable, card.gameBreakdown.failureState]
    : [];
  if (
    conditionallyScopedGameFields.some((field) => {
      const compact = normalizedPracticeText(field);
      const needsScope = preservedHintCritiqueMatches(compact).length > 0 ||
        hasNegativeReplyEvaluation(field) ||
        /(?:照提示|照貼|提示那句|原本提示|hint|你的回覆|你這句|這句|剛才那句|剛剛那句|這個回應)/iu
          .test(compact);
      return needsScope && !isObjectiveGameOutcome(field) &&
        !hasClearScope(field);
    })
  ) {
    return true;
  }
  const critiqueFields: Array<{
    value: string;
    allowObjectiveGameOutcome?: boolean;
  }> = [
    { value: card.summary },
    ...card.strengths.map((value) => ({ value })),
    ...card.watchouts.map((value) => ({ value })),
    { value: card.dateChanceReason },
    { value: card.nextInviteMove },
    ...(card.gameBreakdown
      ? [
        { value: card.gameBreakdown.phaseReached },
        {
          value: card.gameBreakdown.missedVariable,
          allowObjectiveGameOutcome: true,
        },
        {
          value: card.gameBreakdown.failureState,
          allowObjectiveGameOutcome: true,
        },
      ]
      : []),
  ];
  for (const { value: field, allowObjectiveGameOutcome } of critiqueFields) {
    if (allowObjectiveGameOutcome && isObjectiveGameOutcome(field)) continue;
    for (const clause of field.split(/[。！？；;\n]+/u)) {
      const compact = normalizedPracticeText(clause);
      for (const critical of preservedHintCritiqueMatches(compact)) {
        if (critiqueIsNegatedPraise(compact, critical.index)) continue;
        const prefix = compact.slice(0, critical.index);
        const isForwardInstruction =
          /^(?:下一步|下次|接下來|之後)(?:你|你的回覆|可以|可|要|應該|改成|別|不要)*/u
            .test(prefix) &&
          !/(?:照提示|照貼|提示那句|原本提示|剛才那句|hint)/iu.test(
            prefix,
          );
        if (
          isForwardInstruction ||
          critiqueClearlyTargetsPartner(compact, critical.index) ||
          critiqueClearlyTargetsAnotherUserTurn(
            clause,
            turns,
            appliedHintTurns,
          )
        ) {
          continue;
        }
        return true;
      }
    }
  }
  return false;
}

function isPreservedHiddenHintAssessment(value: unknown): boolean {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return false;
  }
  const assessment = value as Record<string, unknown>;
  return assessment.verdict === "preserved" &&
    assessment.revisedEvidenceQuote === null;
}

function compactDebriefQuote(value: string, maxChars = 18): string {
  const normalized = value
    .normalize("NFKC")
    .replace(/\s+/gu, " ")
    .replace(/[「」"']/gu, "")
    .trim();
  const chars = [...normalized];
  if (chars.length <= maxChars) return normalized;
  return `${chars.slice(0, maxChars).join("")}…`;
}

function assistantTextNearHint(
  turns: PracticeTurn[] | undefined,
  hintTurnIndex: number,
  direction: "before" | "after",
): string {
  if (!turns || turns.length === 0) return "";
  if (direction === "after") {
    for (let index = hintTurnIndex + 1; index < turns.length; index++) {
      if (turns[index]?.role === "ai") return turns[index].text;
    }
    return "";
  }
  for (let index = hintTurnIndex - 1; index >= 0; index--) {
    if (turns[index]?.role === "ai") return turns[index].text;
  }
  return "";
}

function cardVisiblyReversesPreservedHint(card: DebriefCard): boolean {
  const visible = normalizedPracticeText(debriefVisibleFields(card).join("\n"));
  return /(?:提示|hint).{0,16}(?:錯|不對|不該|太急|偏保守|無效|不好|不合適|不適合|有問題|失準|誤判)/iu
    .test(visible);
}

function preservedHintRepairNextLine(anchor: string): string {
  const normalized = normalizedPracticeText(anchor);
  if (/(?:咖啡|口袋名單|裝潢|氣味|香味|單品|黑咖啡)/u.test(normalized)) {
    return `「${anchor}」這個標準很細，妳最在意哪一個？`;
  }
  if (/(?:追什麼劇|什麼劇|追劇|好看嗎|片單|懸疑)/u.test(normalized)) {
    return `我昨晚追到停不下來；你飛久都怎麼撐過時差？`;
  }
  if (/(?:作息|時差|長班|上班|飛久|飛回來)/u.test(normalized)) {
    return `「${anchor}」聽起來很硬，妳都怎麼拉回來？`;
  }
  if (/(?:賴床|開機|睡醒|醒了)/u.test(normalized)) {
    return `「${anchor}」那我先陪妳用低速模式聊。`;
  }
  return `「${anchor}」這個判斷很有畫面，妳通常怎麼選？`;
}

function repairPreservedHintCritiqueCard(
  card: DebriefCard,
  appliedHintTurns: AppliedHintTurn[],
  turns?: PracticeTurn[],
): DebriefCard {
  const latestHint = appliedHintTurns.reduce((latest, hint) =>
    hint.turnIndex >= latest.turnIndex ? hint : latest
  );
  const afterQuote = compactDebriefQuote(
    assistantTextNearHint(turns, latestHint.turnIndex, "after"),
  );
  if (!afterQuote) return card;
  const beforeQuote = compactDebriefQuote(
    assistantTextNearHint(turns, latestHint.turnIndex, "before"),
  );
  const anchor = afterQuote || beforeQuote || "這個話題";
  const setup = beforeQuote || anchor;

  const summary = guardVisibleText(
    afterQuote
      ? `你有照提示做，她也接住「${afterQuote}」。`
      : "你有照提示做，這輪先保留低壓節奏。",
  );
  const strengths = [
    guardVisibleText(`你先接她「${setup}」，沒有急著推進。`),
  ];
  const watchouts = [
    guardVisibleText(`下一步少一個追問，多留你對「${anchor}」的生活感。`),
  ];
  const suggestedLine = guardVisibleText(
    preservedHintRepairNextLine(anchor),
  );
  const dateChanceReason = guardVisibleText(
    afterQuote
      ? `她願意延續「${afterQuote}」和你來回。`
      : "她願意延續話題和你來回。",
  );
  const nextInviteMove = guardVisibleText(
    `先接「${anchor}」，再補一點你的生活畫面。`,
  );
  const gameBreakdown = card.gameBreakdown
    ? {
      ...card.gameBreakdown,
      phaseReached: guardVisibleText(`熟悉進度仍在延續「${anchor}」。`),
      missedVariable: guardVisibleText(
        `下一步缺的是你對「${anchor}」的生活畫面。`,
      ),
      failureState: guardVisibleText(
        `她仍停在低壓延續「${anchor}」的節奏。`,
      ),
      nextFirstLine: suggestedLine,
      inviteDirection: guardVisibleText(
        `先補你對「${anchor}」的生活畫面，保留低壓節奏。`,
      ),
    }
    : null;
  return {
    ...card,
    summary,
    strengths,
    watchouts,
    suggestedLine,
    dateChanceReason,
    nextInviteMove,
    gameBreakdown,
  };
}

/**
 * Hidden continuity contract. Debrief may revise a Hint only when it points to
 * an exact assistant reply that happened after that Hint was sent. The hidden
 * assessment is validated and then deliberately omitted from DebriefCard.
 */
function assertHintAssessment(opts: {
  value: unknown;
  card: DebriefCard;
  turns?: PracticeTurn[];
  appliedHintTurns: AppliedHintTurn[];
}): void {
  if (!opts.appliedHintTurns.every(hasCompleteHintDecision)) {
    throw new Error("debrief_hint_decision_missing");
  }
  if (
    typeof opts.value !== "object" || opts.value === null ||
    Array.isArray(opts.value)
  ) {
    throw new Error("debrief_hint_assessment_missing");
  }
  const assessment = opts.value as Record<string, unknown>;
  const keys = Object.keys(assessment).sort();
  if (
    keys.length !== 2 ||
    keys[0] !== "revisedEvidenceQuote" ||
    keys[1] !== "verdict"
  ) {
    throw new Error("debrief_hint_assessment_invalid");
  }
  const verdict = assessment.verdict;
  if (verdict !== "preserved" && verdict !== "revised") {
    throw new Error("debrief_hint_assessment_invalid");
  }
  const quote = assessment.revisedEvidenceQuote;
  const visibleText = debriefVisibleFields(opts.card).join("\n");
  const visiblyReversesHint =
    /(?:提示|建議)(?:(?:本身|內容|那句|其實|真的|確實|有點|太|很|偏|是)){0,3}(?:錯|不對|不該|太急|偏保守|無效|不好|不合適|不適合|有問題|失準|誤判)/u
      .test(normalizedPracticeText(visibleText));
  const strategyContradictsHint = cardContradictsHintStrategy(
    opts.card,
    opts.appliedHintTurns,
  );
  if (
    (visiblyReversesHint || strategyContradictsHint) && verdict !== "revised"
  ) {
    throw new Error("debrief_hint_assessment_revision_required");
  }
  if (verdict === "preserved") {
    if (quote !== null) throw new Error("debrief_hint_assessment_invalid");
    if (
      preservedCardCritiquesExactHint(
        opts.card,
        opts.appliedHintTurns,
        opts.turns,
      )
    ) {
      throw new Error("debrief_hint_assessment_revision_required");
    }
    return;
  }
  if (
    typeof quote !== "string" || quote.trim().length === 0 || quote.length > 120
  ) {
    throw new Error("debrief_hint_assessment_evidence_invalid");
  }
  const exactQuote = quote.trim();
  const latestHintTurnIndex = Math.max(
    ...opts.appliedHintTurns.map((hint) => hint.turnIndex),
  );
  const laterAssistantEvidence = (opts.turns ?? []).some((turn, index) =>
    index > latestHintTurnIndex && turn.role === "ai" &&
    turn.text.includes(exactQuote)
  );
  if (!laterAssistantEvidence) {
    throw new Error("debrief_hint_assessment_evidence_invalid");
  }
  if (
    !normalizedPracticeText(visibleText).includes(
      normalizedPracticeText(exactQuote),
    )
  ) {
    throw new Error("debrief_hint_assessment_evidence_not_visible");
  }
}

function assertGeneratedDebriefQuality(
  card: DebriefCard,
  opts: {
    turns?: PracticeTurn[];
    appliedHintTurns?: AppliedHintTurn[];
    sharedFactualEvidence?: string[];
    partnerFactualEvidence?: string[];
    trustedFactClaims?: HintFactClaim[];
  },
): void {
  const visibleFields = debriefVisibleFields(card);
  for (const field of visibleFields) {
    rejectKnownCannedPracticeText(field, "debrief_canned_visible_text");
  }
  assertGeneratedDebriefFieldSubstance(card);
  assertNoInventedPartnerInitiative(card, opts.turns);
  rejectGenericPasteablePracticeText(
    card.suggestedLine,
    "debrief_quality_invalid_suggested_line",
  );
  if (card.gameBreakdown) {
    rejectGenericPasteablePracticeText(
      card.gameBreakdown.nextFirstLine,
      "debrief_quality_invalid_next_first_line",
    );
  }
  const factContext = buildHintFactContext({
    turns: opts.turns,
    sharedFactualEvidence: opts.sharedFactualEvidence,
    partnerFactualEvidence: opts.partnerFactualEvidence,
    trustedFactClaims: opts.trustedFactClaims,
  });
  for (
    const pasteableText of [
      card.suggestedLine,
      ...(card.gameBreakdown ? [card.gameBreakdown.nextFirstLine] : []),
    ]
  ) {
    assertHintFactClaimsSupported({
      text: pasteableText,
      field: "reply",
      context: factContext,
      errorCode: "debrief_quality_invalid_unsupported_detail",
    });
  }
  for (const analyticalText of debriefAnalyticalFields(card)) {
    assertHintFactClaimsSupported({
      text: analyticalText,
      field: "coaching",
      context: factContext,
      errorCode: "debrief_quality_invalid_unsupported_detail",
    });
  }
  const metaPasteablePattern =
    /(?:先接住(?:她|對方)|補(?:上|一點)?感受|低壓邀約|邀約窗口|分享(?:你的|自己的)版本|再聽(?:她|對方)的)/u;
  if (
    metaPasteablePattern.test(card.suggestedLine) ||
    (card.gameBreakdown &&
      metaPasteablePattern.test(card.gameBreakdown.nextFirstLine))
  ) {
    throw new Error("debrief_quality_invalid_meta_line");
  }

  const appliedHints = opts.appliedHintTurns ?? [];
  const suggestion = normalizedPracticeText(card.suggestedLine);
  for (const hint of appliedHints) {
    if (
      suggestion === normalizedPracticeText(hint.originalHintText) ||
      suggestion === normalizedPracticeText(hint.sentText)
    ) {
      throw new Error("debrief_quality_invalid_repeated_hint");
    }
  }
  if (appliedHints.some((hint) => hint.exact)) {
    const accountability = `${card.summary}\n${card.strengths.join("\n")}`;
    if (
      !/(?:有|已)(?:照|採用|使用)提示|照著提示|提示那句/u.test(accountability)
    ) {
      throw new Error("debrief_quality_invalid_hint_accountability");
    }
  }

  assertGeneratedDebriefFieldRoles(card);

  assertPracticeTextGroundedInTurns({
    visibleText: card.suggestedLine,
    turns: opts.turns,
    latestOnly: true,
    errorCode: "debrief_quality_invalid_suggested_line_not_grounded",
  });
  for (const analyticalText of debriefAnalyticalFields(card)) {
    assertPracticeTextGroundedInTurns({
      visibleText: analyticalText,
      turns: opts.turns,
      errorCode: "debrief_quality_invalid_field_not_grounded",
    });
  }
  if (card.gameBreakdown) {
    for (const value of Object.values(card.gameBreakdown)) {
      assertPracticeTextGroundedInTurns({
        visibleText: value,
        turns: opts.turns,
        errorCode: "debrief_quality_invalid_game_breakdown_not_grounded",
      });
    }
  }
}

function extractJsonObject(raw: string): string {
  const fenced = raw
    .trim()
    .replace(/^```(?:json)?\s*/i, "")
    .replace(/\s*```$/i, "")
    .trim();

  const start = fenced.indexOf("{");
  const end = fenced.lastIndexOf("}");
  if (start >= 0 && end > start) {
    return fenced.slice(start, end + 1).trim();
  }
  return fenced;
}

export function parseDebriefCard(
  raw: string,
  opts: {
    allowGameBreakdown?: boolean;
    requireCompleteCard?: boolean;
    turns?: PracticeTurn[];
    appliedHintTurns?: AppliedHintTurn[];
    sharedFactualEvidence?: string[];
    partnerFactualEvidence?: string[];
    trustedFactClaims?: HintFactClaim[];
    enforceGeneratedQuality?: boolean;
    repairPreservedHintCritique?: boolean;
  } = {},
): DebriefCard {
  const cleaned = extractJsonObject(raw);
  const parsed = JSON.parse(cleaned);
  if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
    throw new Error("debrief_not_object");
  }
  const p = parsed as Record<string, unknown>;
  const enforceGeneratedQuality = opts.enforceGeneratedQuality === true;
  const summary = guardVisibleText(
    generatedVisibleString(
      p.summary,
      60,
      GENERATED_DEBRIEF_PROSE_MAX_LENGTH,
      enforceGeneratedQuality,
    ),
  );
  const suggestedLine = guardVisibleText(
    generatedVisibleString(
      p.suggestedLine,
      60,
      GENERATED_DEBRIEF_PROSE_MAX_LENGTH,
      enforceGeneratedQuality,
    ),
  );
  if (summary.length === 0 || suggestedLine.length === 0) {
    throw new Error("debrief_missing_fields");
  }
  const strengths = generatedVisibleList(
    p.strengths,
    2,
    40,
    GENERATED_DEBRIEF_LIST_ITEM_MAX_LENGTH,
    enforceGeneratedQuality,
  ).map(guardVisibleText);
  const watchouts = generatedVisibleList(
    p.watchouts,
    2,
    40,
    GENERATED_DEBRIEF_LIST_ITEM_MAX_LENGTH,
    enforceGeneratedQuality,
  ).map(guardVisibleText);
  const vibeRaw = clampStr(p.vibe, 4);
  const vibe = VIBES.includes(vibeRaw) ? vibeRaw : "中性";

  // 約出來機會：合法值直接採用；非法/缺值時，有理由文字才 fallback medium，否則 low
  // （沒理由還說 medium 會誤導，往保守方向）。向後相容：舊卡缺這些欄位 → low + 空字串。
  const dateChanceRaw = clampStr(p.dateChance, 8).toLowerCase();
  const dateChanceReason = guardVisibleText(
    generatedVisibleString(
      p.dateChanceReason,
      60,
      GENERATED_DEBRIEF_PROSE_MAX_LENGTH,
      enforceGeneratedQuality,
    ),
  );
  const nextInviteMove = guardVisibleText(
    generatedVisibleString(
      p.nextInviteMove,
      60,
      GENERATED_DEBRIEF_PROSE_MAX_LENGTH,
      enforceGeneratedQuality,
    ),
  );
  const dateChance = DATE_CHANCES.includes(dateChanceRaw)
    ? dateChanceRaw
    : (dateChanceReason.length > 0 ? "medium" : "low");

  // Handler 的正式生成路徑採完整契約；寬鬆模式只留給舊快照/純 parser 相容。
  // 缺欄位交給第二次修復型生成，避免 UI 把殘缺卡誤認為模型成功。
  if (opts.requireCompleteCard === true) {
    if (
      strengths.length === 0 || watchouts.length === 0 ||
      dateChanceReason.length === 0 || nextInviteMove.length === 0
    ) {
      throw new Error("debrief_missing_fields");
    }
    if (!VIBES.includes(vibeRaw)) {
      throw new Error("debrief_invalid_vibe");
    }
    if (!DATE_CHANCES.includes(dateChanceRaw)) {
      throw new Error("debrief_invalid_date_chance");
    }
  }

  let card: DebriefCard = {
    summary,
    strengths,
    watchouts,
    suggestedLine,
    vibe,
    dateChance,
    dateChanceReason,
    nextInviteMove,
    // handler 僅在 Game mode 傳 true；Game 卡少任何拆盤欄位都視為格式失敗，
    // 交由既有 retry/fallback 路徑處理，避免殘缺拆盤被當成成功。
    gameBreakdown: opts.allowGameBreakdown === true
      ? parseGameBreakdown(p.gameBreakdown, enforceGeneratedQuality)
      : null,
  };
  const appliedHintTurns = opts.appliedHintTurns ?? [];
  if (
    appliedHintTurns.length > 0 &&
    opts.repairPreservedHintCritique === true &&
    isPreservedHiddenHintAssessment(p.hintAssessment) &&
    (cardVisiblyReversesPreservedHint(card) ||
      preservedCardCritiquesExactHint(card, appliedHintTurns, opts.turns) ||
      (appliedHintTurns.every(hasCompleteHintDecision) &&
        cardContradictsHintStrategy(card, appliedHintTurns)))
  ) {
    card = repairPreservedHintCritiqueCard(
      card,
      appliedHintTurns,
      opts.turns,
    );
  }
  if (appliedHintTurns.length > 0) {
    assertHintAssessment({
      value: p.hintAssessment,
      card,
      turns: opts.turns,
      appliedHintTurns,
    });
  }
  if (opts.enforceGeneratedQuality === true) {
    assertGeneratedDebriefQuality(card, opts);
  }
  return card;
}
