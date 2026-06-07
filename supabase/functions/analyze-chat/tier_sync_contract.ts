import { STREAM_STYLES, type StreamStyle } from "./stream_events.ts";

export type SubscriptionTier = "free" | "starter" | "essential";

export type TierSyncRefreshStatus =
  | "applied"
  | "not_paid"
  | "not_configured"
  | "unavailable";

export function normalizeSubscriptionTier(value: unknown): SubscriptionTier {
  if (typeof value !== "string") return "free";
  const normalized = value.trim().toLowerCase();
  if (normalized === "starter" || normalized === "essential") {
    return normalized;
  }
  return "free";
}

export function subscriptionTierRank(value: SubscriptionTier): number {
  switch (value) {
    case "essential":
      return 2;
    case "starter":
      return 1;
    case "free":
    default:
      return 0;
  }
}

export function shouldFailPaidTierSync(options: {
  expectedTier: unknown;
  currentTier: unknown;
  refreshStatus: TierSyncRefreshStatus;
}): boolean {
  const expectedTier = normalizeSubscriptionTier(options.expectedTier);
  const currentTier = normalizeSubscriptionTier(options.currentTier);
  if (subscriptionTierRank(expectedTier) <= subscriptionTierRank(currentTier)) {
    return false;
  }

  return options.refreshStatus === "not_configured" ||
    options.refreshStatus === "unavailable";
}

export function streamReplyStylesForTier(
  tier: unknown,
): readonly StreamStyle[] {
  const normalizedTier = normalizeSubscriptionTier(tier);
  if (normalizedTier === "free") return ["extend"];
  return STREAM_STYLES;
}
