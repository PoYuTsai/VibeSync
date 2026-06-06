import {
  getTierFromProductId,
  resolveBillingIssueTier,
  tierRank,
} from "./tiers.ts";

export type SubscriptionUpdateDecision =
  | {
    kind: "update";
    newTier: string;
    subscriptionUpdate: Record<string, unknown>;
  }
  | {
    kind: "ignore";
    newTier: string;
    subscriptionUpdate?: Record<string, unknown>;
  }
  | {
    kind: "unsupported_product";
    productId: string;
  };

export function inferBillingPeriod(productId: string): string | null {
  const normalized = productId.trim().toLowerCase();
  if (!normalized) return null;
  if (normalized.includes("quarter") || normalized.includes("p3m")) {
    return "quarterly";
  }
  if (normalized.includes("monthly") || normalized.includes("p1m")) {
    return "monthly";
  }
  return "unknown";
}

export function buildSubscriptionProductMetadata(
  productId: string,
  event: Record<string, unknown>,
): Record<string, unknown> {
  const normalizedProductId = productId.trim();
  return {
    active_product_id: normalizedProductId || null,
    billing_period: inferBillingPeriod(normalizedProductId),
    store: typeof event.store === "string" ? event.store.trim() : null,
    revenuecat_environment: typeof event.environment === "string"
      ? event.environment.trim()
      : null,
  };
}

export function resolveSubscriptionUpdateForWebhookEvent({
  type,
  effectiveProductId,
  currentTier,
  expiresAt,
  nowIso,
  event,
}: {
  type: string;
  effectiveProductId: string;
  currentTier: string;
  expiresAt: string | null;
  nowIso: string;
  event: Record<string, unknown>;
}): SubscriptionUpdateDecision {
  switch (type) {
    case "INITIAL_PURCHASE":
    case "RENEWAL":
    case "UNCANCELLATION":
    case "SUBSCRIPTION_EXTENDED": {
      const derivedTier = getTierFromProductId(effectiveProductId);
      if (derivedTier == null) {
        return {
          kind: "unsupported_product",
          productId: effectiveProductId,
        };
      }

      return {
        kind: "update",
        newTier: derivedTier,
        subscriptionUpdate: {
          tier: derivedTier,
          status: "active",
          expires_at: expiresAt,
          ...buildSubscriptionProductMetadata(effectiveProductId, event),
        },
      };
    }

    case "PRODUCT_CHANGE": {
      const derivedTier = getTierFromProductId(effectiveProductId);
      if (derivedTier == null) {
        return {
          kind: "unsupported_product",
          productId: effectiveProductId,
        };
      }

      const isUpgrade = tierRank(derivedTier) > tierRank(currentTier);
      if (isUpgrade) {
        return {
          kind: "update",
          newTier: derivedTier,
          subscriptionUpdate: {
            tier: derivedTier,
            status: "active",
            expires_at: expiresAt,
            ...buildSubscriptionProductMetadata(effectiveProductId, event),
          },
        };
      }

      return {
        kind: "ignore",
        newTier: derivedTier,
        subscriptionUpdate: {
          tier: currentTier,
          status: "active",
          expires_at: expiresAt,
          ...buildSubscriptionProductMetadata(effectiveProductId, event),
        },
      };
    }

    case "EXPIRATION":
      return {
        kind: "update",
        newTier: "free",
        subscriptionUpdate: {
          tier: "free",
          status: "expired",
          expires_at: expiresAt,
          ...buildSubscriptionProductMetadata(effectiveProductId, event),
          monthly_messages_used: 0,
          daily_messages_used: 0,
          monthly_reset_at: nowIso,
          daily_reset_at: nowIso,
        },
      };

    case "BILLING_ISSUE": {
      const preservedTier = resolveBillingIssueTier({
        currentTier,
        productId: effectiveProductId,
      });

      if (preservedTier == null) {
        return {
          kind: "ignore",
          newTier: "free",
        };
      }

      return {
        kind: "update",
        newTier: preservedTier,
        subscriptionUpdate: {
          tier: preservedTier,
          status: "active",
          expires_at: expiresAt,
          ...buildSubscriptionProductMetadata(effectiveProductId, event),
        },
      };
    }

    case "CANCELLATION": {
      const newTier = getTierFromProductId(effectiveProductId) ?? currentTier;
      return {
        kind: "update",
        newTier,
        subscriptionUpdate: {
          tier: newTier,
          status: "cancelled",
          expires_at: expiresAt,
          ...buildSubscriptionProductMetadata(effectiveProductId, event),
        },
      };
    }

    default:
      return {
        kind: "ignore",
        newTier: "free",
      };
  }
}
