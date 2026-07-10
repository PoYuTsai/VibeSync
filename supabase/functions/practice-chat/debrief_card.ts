// 教練拆解卡 JSON 解析（純函式、可 deno test）。
// 防御性：去 markdown 圍欄、缺核心欄位丟出、vibe 非法則回退「中性」、長度 clamp。

import {
  rejectL4UnsafeVisibleText,
  rejectVisibleInternalLabelLeak,
  rejectVisibleTemperatureMechanismLeak,
} from "./visible_text_guard.ts";
import { temperatureBandFor } from "./temperature.ts";
import type { AppliedHintTurn } from "./validate.ts";

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
  } = {},
): DebriefCard {
  const tone = fallbackChanceToneFor(opts.temperatureScore);
  const hasAppliedHint = (opts.appliedHintTurns?.length ?? 0) > 0;
  if (hasAppliedHint) {
    const hasExactHint = opts.appliedHintTurns?.some((hint) => hint.exact) ??
      false;
    const suggestedLine =
      "我有照著接妳剛剛那個點，但我也有點好奇，妳自己最喜歡那種放鬆感是哪一種？";
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
  const suggestedLine = "我對妳剛說的那個點有點好奇，哪個部分最吸引妳？";
  return {
    summary: "這輪有接到她的回覆，但連續提問偏多，自己的感受還不夠。",
    strengths: ["有順著她的回覆接話"],
    watchouts: ["問題偏多，容易像盤問"],
    suggestedLine,
    vibe: tone?.vibe ?? "中性",
    dateChance: tone?.dateChance ?? "low",
    dateChanceReason: tone?.dateChanceReason ??
      "熟悉度還在建立中，先把話題聊開比較穩。",
    nextInviteMove: tone?.nextInviteMove ??
      "先接她的答案，再分享一點自己的感受。",
    gameBreakdown: opts.practiceMode === "game"
      ? {
        phaseReached: "開場到測試",
        missedVariable: "投入感",
        failureState: "問題偏多",
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

function parseGameBreakdown(value: unknown): GameBreakdown | null {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return null;
  }
  const p = value as Record<string, unknown>;
  const gameBreakdown = {
    phaseReached: guardVisibleText(clampStr(p.phaseReached, 60)),
    missedVariable: guardVisibleText(clampStr(p.missedVariable, 60)),
    failureState: guardVisibleText(clampStr(p.failureState, 60)),
    nextFirstLine: guardVisibleText(clampStr(p.nextFirstLine, 70)),
    inviteDirection: guardVisibleText(clampStr(p.inviteDirection, 60)),
  };
  return Object.values(gameBreakdown).some((field) => field.length > 0)
    ? gameBreakdown
    : null;
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
  opts: { allowGameBreakdown?: boolean } = {},
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

  return {
    summary,
    strengths: clampList(p.strengths, 2, 40).map(guardVisibleText),
    watchouts: clampList(p.watchouts, 2, 40).map(guardVisibleText),
    suggestedLine,
    vibe,
    dateChance,
    dateChanceReason,
    nextInviteMove,
    gameBreakdown: opts.allowGameBreakdown === true
      ? parseGameBreakdown(p.gameBreakdown)
      : null,
  };
}
