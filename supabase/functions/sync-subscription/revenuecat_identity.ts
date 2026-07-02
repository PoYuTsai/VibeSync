export function normalizeRevenueCatAppUserId(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

// RevenueCat mints anonymous ids as "$RCAnonymousID:<uuid>" on-device before a
// user logs in. They are unguessable and never leave the device that owns them.
function isAnonymousRevenueCatAppUserId(value: string): boolean {
  return value.startsWith("$RCAnonymousID");
}

export function buildRevenueCatUserIdCandidates(
  supabaseUserId: string,
  revenueCatAppUserId: unknown,
): string[] {
  const candidates = [supabaseUserId];
  const normalized = normalizeRevenueCatAppUserId(revenueCatAppUserId);
  // Only trust a client-supplied id as a second entitlement lookup when it is an
  // anonymous RevenueCat id. Accepting an arbitrary id (e.g. a victim's Supabase
  // user id) would let a caller merge someone else's paid entitlements into
  // their own subscription row — a privilege escalation. Purchases made under a
  // real user id already surface through RevenueCat aliasing on the primary
  // supabaseUserId lookup.
  if (normalized != null && isAnonymousRevenueCatAppUserId(normalized)) {
    candidates.push(normalized);
  }
  return Array.from(new Set(candidates)).slice(0, 2);
}
