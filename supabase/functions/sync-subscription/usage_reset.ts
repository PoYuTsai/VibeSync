export type SubscriptionTier = "free" | "starter" | "essential";

export function shouldResetUsageOnTierSync({
  resetUsageRequested,
  previousTier,
  finalTier,
  revenueCatTier,
  tierPreservedReason,
}: {
  resetUsageRequested: boolean;
  previousTier: SubscriptionTier;
  finalTier: SubscriptionTier;
  revenueCatTier: SubscriptionTier;
  tierPreservedReason: string | null;
}): boolean {
  if (!resetUsageRequested) return false;
  if (finalTier === "free") return false;
  if (previousTier === finalTier) return false;
  if (tierPreservedReason !== null) return false;
  return revenueCatTier === finalTier;
}
