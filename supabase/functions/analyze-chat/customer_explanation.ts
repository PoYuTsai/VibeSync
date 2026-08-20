// Customer-facing explanation guard shared by Opener and New Topic.
//
// This is deliberately a narrow rejection gate, not a style scorer and not a
// rewriting engine.  Replacing one jargon token inside an otherwise internal
// sentence tends to produce even stranger copy, so callers either omit the
// optional explanation (Opener) or use the existing same-model repair path
// (New Topic).  Sendable messages never pass through this helper.

import { toTraditionalChinese } from "../_shared/traditional_chinese.ts";

const INTERNAL_EXPLANATION_PHRASES = [
  "怪選項切角",
  "怪選項",
  "切入角度",
  "怪得剛剛好",
  "想題兩段式",
  "先發散再個人化",
  "深度階梯",
  "人格二選一",
  "共同想像",
  "共同身分",
  "輕資格審查",
  "資格審查",
  "位階守則",
  "位階訊號",
  "旁路冷讀",
  "吐槽冷讀",
  "冷讀",
  "好奇心鉤子",
  "鉤子",
  "雙球",
  "顆球",
  "微拉",
  "重拉",
  "推拉",
  "失格",
  "不自證",
  "框架維持",
  "男人框架",
  "平等框架",
  "反駁空間",
  "分配角色",
  "破冰腦力",
  "反打",
  "高手觀察",
  "高手手法",
] as const;

const INTERNAL_EXPLANATION_LABELS = [
  "wentcold",
  "afterdate",
  "warmup",
  "newtopic",
  "stuck",
  "direction",
  "openingline",
  "whyitworks",
  "nextmove",
  "profileanalysis",
  "openingstrategy",
  "pioneerplan",
  "twoballplan",
  "mastermove",
  "masterobservation",
  "curiosityhook",
  "talkingpoints",
  "frameread",
  "positivehooks",
  "avoidtopics",
  "stretchlevels",
  "recommendationreason",
  "recommendedpick",
  "recommendedreason",
  "insufficientinfo",
  "wrongsurface",
  "coldread",
  "extend",
  "resonate",
  "tease",
  "humor",
] as const;

function compactForLeakCheck(value: string): string {
  return value
    .normalize("NFKC")
    .toLowerCase()
    .replace(/[\s\p{P}\p{S}\p{C}\p{M}]/gu, "");
}

export function hasCustomerExplanationLeak(value: string): boolean {
  const compact = compactForLeakCheck(value);
  if (
    INTERNAL_EXPLANATION_LABELS.some((label) => compact.includes(label))
  ) {
    return true;
  }
  return INTERNAL_EXPLANATION_PHRASES.some((phrase) =>
    compact.includes(compactForLeakCheck(phrase))
  );
}

/**
 * Normalize a customer explanation to Traditional Chinese and reject only
 * enumerable contract leaks.  The function never rewrites a sendable line.
 */
export function sanitizeCustomerExplanationText(
  value: unknown,
  maxLen: number,
): string | null {
  if (typeof value !== "string") return null;
  const normalized = toTraditionalChinese(value)
    .replace(/\r\n?/g, "\n")
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.length > 0)
    .join(" ")
    .replace(/[\t \u3000]+/g, " ")
    .trim();
  if (normalized.length === 0 || normalized.length > maxLen) return null;
  if (normalized.includes("```")) return null;
  if (/^[{[]/u.test(normalized)) return null;
  if (hasCustomerExplanationLeak(normalized)) return null;
  return normalized;
}
