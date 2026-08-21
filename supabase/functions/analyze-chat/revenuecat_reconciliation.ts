// RevenueCat 訂閱層級對帳：client 期望層級高於 DB、或額度不足時，向
// RevenueCat 查詢實際訂閱並向上修正 DB tier（只升不降；essential 不再查）。
//
// Refresher 是工廠：一次請求內共用 candidates 與身分，呼叫端以 readState
// 提供當下的 sub/effectiveTier 視圖，applied 時經 applyRefreshedSub 回寫
// （持久化失敗仍回 applied，但 telemetry 標 persisted:false——歷史行為）。

import { isPlainObject } from "../_shared/quota.ts";
import {
  getErrorMessage,
  logError,
  logInfo,
  logWarn,
  summarizeUser,
} from "./logger.ts";
import {
  finalizeTierSyncRefreshStatus,
  normalizeSubscriptionTier,
  type SubscriptionTier,
  subscriptionTierRank,
  type TierSyncRefreshStatus,
} from "./tier_sync_contract.ts";

export function tierFromProductId(productId: unknown): SubscriptionTier {
  if (typeof productId !== "string") return "free";
  const normalized = productId.trim().toLowerCase();
  if (normalized.includes("essential")) return "essential";
  if (normalized.includes("starter")) return "starter";
  return "free";
}

export function highestTier(
  tiers: Iterable<SubscriptionTier>,
): SubscriptionTier {
  const all = Array.from(tiers);
  if (all.includes("essential")) return "essential";
  if (all.includes("starter")) return "starter";
  return "free";
}

function parseRevenueCatDate(value: unknown): Date | null {
  if (typeof value !== "string" || !value.trim()) return null;
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function isActiveAt(expiresDate: unknown): boolean {
  const parsed = parseRevenueCatDate(expiresDate);
  if (parsed == null) return true;
  return parsed.getTime() > Date.now();
}

export function collectTiersFromRevenueCatPayload(
  subscriber: Record<string, unknown>,
): SubscriptionTier {
  const activeTiers: SubscriptionTier[] = [];

  const entitlements = isPlainObject(subscriber.entitlements)
    ? subscriber.entitlements
    : {};
  for (const value of Object.values(entitlements)) {
    if (!isPlainObject(value)) continue;
    if (!isActiveAt(value.expires_date)) continue;
    activeTiers.push(tierFromProductId(value.product_identifier));
  }

  const subscriptions = isPlainObject(subscriber.subscriptions)
    ? subscriber.subscriptions
    : {};
  for (const [productId, value] of Object.entries(subscriptions)) {
    if (!isPlainObject(value)) continue;
    if (!isActiveAt(value.expires_date)) continue;
    activeTiers.push(tierFromProductId(productId));
  }

  return highestTier(activeTiers);
}

export function collectLatestExpirationFromRevenueCatPayload(
  subscriber: Record<string, unknown>,
): string | null {
  let latestTimestamp: number | null = null;
  let latestIso: string | null = null;

  const considerExpiration = (rawValue: unknown) => {
    const parsed = parseRevenueCatDate(rawValue);
    if (parsed == null) return;
    const timestamp = parsed.getTime();
    if (latestTimestamp == null || timestamp > latestTimestamp) {
      latestTimestamp = timestamp;
      latestIso = parsed.toISOString();
    }
  };

  const entitlements = isPlainObject(subscriber.entitlements)
    ? subscriber.entitlements
    : {};
  for (const value of Object.values(entitlements)) {
    if (!isPlainObject(value)) continue;
    if (!isActiveAt(value.expires_date)) continue;
    considerExpiration(value.expires_date);
  }

  const subscriptions = isPlainObject(subscriber.subscriptions)
    ? subscriber.subscriptions
    : {};
  for (const value of Object.values(subscriptions)) {
    if (!isPlainObject(value)) continue;
    if (!isActiveAt(value.expires_date)) continue;
    considerExpiration(value.expires_date);
  }

  return latestIso;
}

export function buildRevenueCatUserIdCandidates(input: {
  revenueCatAppUserId: string;
  userId: string;
}): string[] {
  return Array.from(
    new Set(
      [input.revenueCatAppUserId, input.userId]
        .map((value) => (typeof value === "string" ? value.trim() : ""))
        .filter((value) => value.length > 0),
    ),
  );
}

export interface RevenueCatRefresherDeps {
  // deno-lint-ignore no-explicit-any
  supabase: any;
  apiKey: string | undefined;
  userId: string;
  revenueCatAppUserId: string;
  expectedTier: SubscriptionTier;
  candidates: string[];
  /// 呼叫當下的訂閱視圖（一次請求內 sub 會被多次改寫）。
  // deno-lint-ignore no-explicit-any
  readState: () => { sub: any; effectiveTier: string };
  /// applied 時回寫新 sub；呼叫端負責重算 effectiveTier 與日/月上限。
  // deno-lint-ignore no-explicit-any
  applyRefreshedSub: (nextSub: any) => void;
}

export function createRevenueCatTierRefresher(
  deps: RevenueCatRefresherDeps,
): (reason: string) => Promise<TierSyncRefreshStatus> {
  const {
    supabase,
    apiKey,
    userId,
    revenueCatAppUserId,
    expectedTier,
    candidates,
  } = deps;
  return async (reason: string): Promise<TierSyncRefreshStatus> => {
    const state = deps.readState();
    if (!apiKey) {
      logError("subscription_revenuecat_refresh_unconfigured", {
        user: summarizeUser(userId),
        reason,
        expectedTier,
        effectiveTier: state.effectiveTier,
        currentTier: normalizeSubscriptionTier(state.sub?.tier),
        revenueCatHintPresent: revenueCatAppUserId.length > 0,
        revenueCatUserIdCandidateCount: candidates.length,
      });
      return "not_configured";
    }

    const previousTier = normalizeSubscriptionTier(state.sub?.tier);
    if (previousTier === "essential") {
      return "not_paid";
    }

    try {
      let unavailable = false;
      let sawValidSubscriber = false;
      for (const revenueCatUserId of candidates) {
        const revenueCatResponse = await fetch(
          `https://api.revenuecat.com/v1/subscribers/${
            encodeURIComponent(revenueCatUserId)
          }`,
          {
            headers: {
              Authorization: `Bearer ${apiKey}`,
              "Content-Type": "application/json",
            },
          },
        );

        if (!revenueCatResponse.ok) {
          const detail = await revenueCatResponse.text().catch(() => "");
          logWarn("subscription_revenuecat_refresh_failed", {
            user: summarizeUser(userId),
            revenueCatUser: summarizeUser(revenueCatUserId),
            reason,
            previousTier,
            status: revenueCatResponse.status,
            detail,
          });
          unavailable = true;
          continue;
        }

        const revenueCatPayload = await revenueCatResponse.json().catch(() =>
          null
        );
        if (
          !isPlainObject(revenueCatPayload) ||
          !isPlainObject(revenueCatPayload.subscriber)
        ) {
          logWarn("subscription_revenuecat_refresh_invalid_payload", {
            user: summarizeUser(userId),
            revenueCatUser: summarizeUser(revenueCatUserId),
            reason,
            previousTier,
          });
          unavailable = true;
          continue;
        }

        const subscriber = revenueCatPayload.subscriber;
        sawValidSubscriber = true;
        const refreshedTier = collectTiersFromRevenueCatPayload(subscriber);
        if (
          subscriptionTierRank(refreshedTier) <=
            subscriptionTierRank(previousTier)
        ) {
          continue;
        }

        const refreshedExpiresAt = collectLatestExpirationFromRevenueCatPayload(
          subscriber,
        );
        const updatePayload: Record<string, unknown> = {
          tier: refreshedTier,
          status: "active",
        };
        if (refreshedExpiresAt) {
          updatePayload.expires_at = refreshedExpiresAt;
        }

        const { data: refreshedSub, error: refreshedError } = await supabase
          .from("subscriptions")
          .update(updatePayload)
          .eq("user_id", userId)
          .select(
            "tier, monthly_messages_used, daily_messages_used, daily_reset_at, monthly_reset_at",
          )
          .maybeSingle();

        deps.applyRefreshedSub(
          refreshedSub ?? { ...state.sub, tier: refreshedTier },
        );

        if (refreshedError) {
          logError("subscription_revenuecat_refresh_persist_failed", {
            user: summarizeUser(userId),
            revenueCatUser: summarizeUser(revenueCatUserId),
            reason,
            previousTier,
            refreshedTier,
            error: refreshedError.message,
          });
        }

        logInfo("subscription_revenuecat_refresh_applied", {
          user: summarizeUser(userId),
          revenueCatUser: summarizeUser(revenueCatUserId),
          reason,
          previousTier,
          refreshedTier,
          persisted: !refreshedError,
        });
        return "applied";
      }

      return finalizeTierSyncRefreshStatus({
        sawValidSubscriber,
        sawUnavailableCandidate: unavailable,
      });
    } catch (error) {
      logWarn("subscription_revenuecat_refresh_exception", {
        user: summarizeUser(userId),
        reason,
        previousTier,
        error: getErrorMessage(error),
      });
      return "unavailable";
    }
  };
}
