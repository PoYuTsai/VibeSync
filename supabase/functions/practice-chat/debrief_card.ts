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
  normalizedPracticeText,
  rejectGenericPasteablePracticeText,
  rejectKnownCannedPracticeText,
} from "./practice_visible_quality.ts";
import {
  type PracticeInviteLevel,
  practiceInviteLevelFor,
} from "./practice_invite.ts";

export const VIBES = ["暖", "中性", "冷"];
export const DATE_CHANCES = ["low", "medium", "high"];

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
    /(?:先|這輪|現在).{0,12}(?:不約|不急著約|別急著約|不硬約|鋪墊|累積|建立|延伸|補足|補感受|補投入|熟悉|安全)|等.{0,14}(?:再|才).{0,12}(?:約|邀|窗口)|(?:還沒|尚未|未到).{0,10}(?:窗口|時機)|先.{0,14}再.{0,12}(?:約|邀|窗口)/u
      .test(text)
  ) {
    return "build";
  }
  if (
    /(?:沒有|沒)(?:做|給|丟|推)?(?:出)?(?:直接|明確)?邀約.{0,10}(?:失誤|錯|問題|可惜)|(?:太被動|偏保守|早該).{0,12}(?:直接)?(?:約|邀約)|(?:現在|這輪|下一句|應該|可以|適合|立刻|趁現在).{0,12}(?:直接|明確)(?:約|邀約)|(?:直接|明確|立刻|趁現在)(?:約|邀約)|(?:約|邀約).{0,8}(?:時機|窗口)(?:已經)?成熟/u
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
    card.nextInviteMove,
    ...(card.gameBreakdown
      ? [
        card.gameBreakdown.failureState,
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
    /(?:提示|建議).{0,16}(?:錯|不對|不該|太急|偏保守|無效|不好|不合適|不適合|有問題|失準|誤判)/u
      .test(visibleText);
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
  },
): void {
  const visibleFields = debriefVisibleFields(card);
  for (const field of visibleFields) {
    rejectKnownCannedPracticeText(field, "debrief_canned_visible_text");
  }
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

  assertPracticeTextGroundedInTurns({
    visibleText: card.suggestedLine,
    turns: opts.turns,
    latestOnly: true,
    errorCode: "debrief_quality_invalid_suggested_line_not_grounded",
  });
  if (card.gameBreakdown) {
    for (const value of Object.values(card.gameBreakdown)) {
      assertPracticeTextGroundedInTurns({
        visibleText: value,
        turns: opts.turns,
        errorCode: "debrief_quality_invalid_game_breakdown_not_grounded",
      });
    }
  }

  assertPracticeTextGroundedInTurns({
    visibleText: visibleFields.join("\n"),
    turns: opts.turns,
    errorCode: "debrief_quality_invalid_not_grounded",
  });
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
    enforceGeneratedQuality?: boolean;
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

  const card: DebriefCard = {
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
