// 教練拆解卡 JSON 解析（純函式、可 deno test）。
// 防御性：去 markdown 圍欄、缺核心欄位丟出、vibe 非法則回退「中性」、長度 clamp。

import { rejectVisibleInternalLabelLeak } from "./visible_text_guard.ts";

export const VIBES = ["暖", "中性", "冷"];
export const DATE_CHANCES = ["low", "medium", "high"];

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
  return value;
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

export function parseDebriefCard(raw: string): DebriefCard {
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
  };
}
