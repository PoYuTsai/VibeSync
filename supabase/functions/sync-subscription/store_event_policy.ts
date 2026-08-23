export type SubscriptionTier = "free" | "starter" | "essential";
export type CutoverStatus = "pending" | "auto" | "complete";

export interface RevenueCatSnapshotPersistencePolicy {
  readonly previousTier: SubscriptionTier;
  readonly finalTier: SubscriptionTier;
  readonly revenueCatTier: SubscriptionTier;
  readonly tierPreservedReason: string | null;
  readonly cutoverStatus: CutoverStatus;
}

function tierRank(tier: SubscriptionTier): number {
  switch (tier) {
    case "essential":
      return 2;
    case "starter":
      return 1;
    case "free":
      return 0;
  }
}

/**
 * A scheduled paid downgrade is only a future renewal instruction. Until the
 * renewal webhook arrives, the lower RevenueCat snapshot must not overwrite
 * the currently granted source state, regardless of whether the user has an
 * automatic or completed cutover marker.
 */
export function selectRevenueCatSnapshotEventsForPersistence<T>(
  events: readonly T[],
  policy: RevenueCatSnapshotPersistencePolicy,
): readonly T[] {
  const scheduledPaidDowngrade =
    policy.tierPreservedReason === "scheduled_paid_downgrade" &&
    policy.finalTier === policy.previousTier &&
    tierRank(policy.previousTier) > tierRank(policy.revenueCatTier);

  return scheduledPaidDowngrade ? [] : events;
}
