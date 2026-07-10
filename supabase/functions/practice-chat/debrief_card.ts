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

export const VIBES = ["暖", "中性", "冷"];
export const DATE_CHANCES = ["low", "medium", "high"];

export interface GameBreakdown {
  phaseReached: string;
  missedVariable: string;
  failureState: string;
  nextFirstLine: string;
  inviteDirection: string;
}

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

function parseGameBreakdown(value: unknown): GameBreakdown {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new Error("debrief_game_breakdown_missing_fields");
  }
  const p = value as Record<string, unknown>;
  const gameBreakdown = {
    phaseReached: guardVisibleText(clampStr(p.phaseReached, 60)),
    missedVariable: guardVisibleText(clampStr(p.missedVariable, 60)),
    failureState: guardVisibleText(clampStr(p.failureState, 60)),
    nextFirstLine: guardVisibleText(clampStr(p.nextFirstLine, 70)),
    inviteDirection: guardVisibleText(clampStr(p.inviteDirection, 60)),
  };
  if (Object.values(gameBreakdown).some((field) => field.length === 0)) {
    throw new Error("debrief_game_breakdown_missing_fields");
  }
  return gameBreakdown;
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
  } = {},
): DebriefCard {
  const cleaned = extractJsonObject(raw);
  const parsed = JSON.parse(cleaned);
  if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
    throw new Error("debrief_not_object");
  }
  const p = parsed as Record<string, unknown>;
  const summary = guardVisibleText(clampStr(p.summary, 60));
  const suggestedLine = guardVisibleText(clampStr(p.suggestedLine, 60));
  if (summary.length === 0 || suggestedLine.length === 0) {
    throw new Error("debrief_missing_fields");
  }
  const strengths = clampList(p.strengths, 2, 40).map(guardVisibleText);
  const watchouts = clampList(p.watchouts, 2, 40).map(guardVisibleText);
  const vibeRaw = clampStr(p.vibe, 4);
  const vibe = VIBES.includes(vibeRaw) ? vibeRaw : "中性";

  // 約出來機會：合法值直接採用；非法/缺值時，有理由文字才 fallback medium，否則 low
  // （沒理由還說 medium 會誤導，往保守方向）。向後相容：舊卡缺這些欄位 → low + 空字串。
  const dateChanceRaw = clampStr(p.dateChance, 8).toLowerCase();
  const dateChanceReason = guardVisibleText(clampStr(p.dateChanceReason, 60));
  const nextInviteMove = guardVisibleText(clampStr(p.nextInviteMove, 60));
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

  return {
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
      ? parseGameBreakdown(p.gameBreakdown)
      : null,
  };
}
