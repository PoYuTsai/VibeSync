export function normalizeRevenueCatAppUserId(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

export function buildRevenueCatUserIdCandidates(
  supabaseUserId: string,
  revenueCatAppUserId: unknown,
): string[] {
  const candidates = [supabaseUserId];
  const normalized = normalizeRevenueCatAppUserId(revenueCatAppUserId);
  if (normalized != null) {
    candidates.push(normalized);
  }
  return Array.from(new Set(candidates)).slice(0, 2);
}
