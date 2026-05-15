export type RevenueCatTier = "free" | "starter" | "essential";

export function getTierFromProductId(productId: string): RevenueCatTier | null {
  const normalized = productId.toLowerCase();
  if (normalized.includes("essential")) return "essential";
  if (normalized.includes("starter")) return "starter";
  return null;
}

export function tierRank(tier: string | null | undefined): number {
  switch ((tier ?? "free").trim().toLowerCase()) {
    case "essential":
      return 2;
    case "starter":
      return 1;
    case "free":
    default:
      return 0;
  }
}

function normalizeTier(tier: string | null | undefined): RevenueCatTier {
  switch ((tier ?? "free").trim().toLowerCase()) {
    case "essential":
      return "essential";
    case "starter":
      return "starter";
    case "free":
    default:
      return "free";
  }
}

export function resolveBillingIssueTier({
  currentTier,
  productId,
}: {
  currentTier: string | null | undefined;
  productId: string;
}): RevenueCatTier | null {
  const derivedTier = getTierFromProductId(productId);
  const normalizedCurrentTier = normalizeTier(currentTier);
  const preservedTier = derivedTier != null &&
      tierRank(derivedTier) > tierRank(normalizedCurrentTier)
    ? derivedTier
    : normalizedCurrentTier;

  return preservedTier === "free" ? null : preservedTier;
}
