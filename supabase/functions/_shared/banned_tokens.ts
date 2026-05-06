// Shared product red-line vocabulary for coach surfaces.
//
// These are not generic profanity filters. They are framing words that would
// pull VibeSync back toward manipulative / demeaning dating advice. User input
// may contain messy language; generated visible output must not.

export const BANNED_TOKENS = [
  "PUA",
  "收割",
  "控住",
  "攻略",
  "壞女人",
  "高分妹",
  "玩咖",
] as const;

export function containsBannedToken(value: string): string | null {
  for (const token of BANNED_TOKENS) {
    if (value.includes(token)) return token;
  }
  return null;
}
