// Strict, single-source-of-truth normalizer for opener profileInfo input.
//
// Why this exists:
// The opener quota path makes a billing decision (hasProfileSubstance) and
// then builds the user prompt from the same profileInfo. If those two
// consumers disagree on what counts as "valid input", a non-string value
// like `interests: ["咖啡"]` can simultaneously (a) be string-coerced into
// the prompt by JS template literals and (b) be ignored by the substance
// check, yielding a free opener with real content. Normalizing once and
// having both consumers read the normalized object closes that gap.

const OPENER_PROFILE_KEYS = [
  "name",
  "bio",
  "interests",
  "meetingContext",
] as const;

export type OpenerProfileKey = typeof OPENER_PROFILE_KEYS[number];

export type NormalizedOpenerProfile = Partial<Record<OpenerProfileKey, string>>;

// Per-field caps: profileInfo is user-controlled text that gets string-
// interpolated into the prompt under a flat 3-quota price, so uncapped
// input is platform-absorbed token cost. Caps mirror the client-side
// LengthLimitingTextInputFormatter values; server is the authority since
// the API can be called directly.
export const OPENER_PROFILE_FIELD_LIMITS: Record<OpenerProfileKey, number> = {
  name: 200,
  bio: 2000,
  interests: 2000,
  meetingContext: 200,
};

export function normalizeOpenerProfileInfo(
  raw: unknown,
): NormalizedOpenerProfile {
  if (!raw || typeof raw !== "object") return {};
  const record = raw as Record<string, unknown>;
  const out: NormalizedOpenerProfile = {};
  for (const key of OPENER_PROFILE_KEYS) {
    const value = record[key];
    if (typeof value !== "string") continue;
    const trimmed = value.trim();
    if (trimmed.length === 0) continue;
    out[key] = trimmed.slice(0, OPENER_PROFILE_FIELD_LIMITS[key]);
  }
  return out;
}

// "Substance" here means content that would meaningfully inform the model.
// `name` alone is intentionally excluded — a bare name is too thin to bill
// for and matches the prior server-side eligibility behavior.
export function hasOpenerProfileSubstance(
  profile: NormalizedOpenerProfile,
): boolean {
  return Boolean(profile.bio || profile.interests || profile.meetingContext);
}
