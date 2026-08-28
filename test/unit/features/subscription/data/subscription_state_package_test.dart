import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:vibesync/core/services/usage_service.dart';
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_product_contract.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_tier_helper.dart';

void main() {
  Package iosPackage({
    required String packageId,
    required String productId,
  }) {
    return Package(
      packageId,
      PackageType.custom,
      StoreProduct(
        productId,
        '不應參與辨識的描述',
        'localized title',
        590,
        r'$590',
        'TWD',
      ),
      const PresentedOfferingContext('default', null, null),
    );
  }

  SubscriptionState stateWithPackages(List<Package> packages) {
    final offering = Offering(
      'default',
      'Default offering',
      const {},
      packages,
    );

    return SubscriptionState(
      offerings: Offerings({'default': offering}, current: offering),
    );
  }

  test('iOS getters use exact known product IDs without fuzzy text matching',
      () {
    final state = stateWithPackages([
      iosPackage(
        packageId: r'$rc_monthly',
        productId: 'vibesync_starter_monthly_v2',
      ),
      iosPackage(
        packageId: r'$rc_three_month',
        productId: 'vibesync_starter_quarterly_v2',
      ),
      iosPackage(
        packageId: r'$rc_monthly_essential',
        productId: 'vibesync_essential_monthly_v2',
      ),
      iosPackage(
        packageId: r'$rc_three_month_essential',
        productId: 'vibesync_essential_quarterly_v2',
      ),
    ]);

    expect(
      state.starterMonthlyPackage?.storeProduct.identifier,
      'vibesync_starter_monthly_v2',
    );
    expect(
      state.starterQuarterlyPackage?.storeProduct.identifier,
      'vibesync_starter_quarterly_v2',
    );
    expect(
      state.essentialMonthlyPackage?.storeProduct.identifier,
      'vibesync_essential_monthly_v2',
    );
    expect(
      state.essentialQuarterlyPackage?.storeProduct.identifier,
      'vibesync_essential_quarterly_v2',
    );
  });

  test('iOS missing or fuzzy-only products remain unavailable', () {
    final state = stateWithPackages([
      iosPackage(
        packageId: r'$rc_monthly',
        productId: 'ios_001',
      ),
    ]);

    expect(state.starterMonthlyPackage, isNull);
    expect(state.essentialMonthlyPackage, isNull);
  });

  test('Android state contract is atomic when any package is absent', () {
    final packages = SubscriptionPlanDefinition.androidPlans
        .map(
          (plan) => Package(
            plan.packageId,
            PackageType.custom,
            StoreProduct(
              plan.playProductWithBasePlan,
              'description',
              'title',
              590,
              r'$590',
              'TWD',
              subscriptionOptions: [
                SubscriptionOption(
                  plan.basePlanId,
                  plan.playProductWithBasePlan,
                  plan.playProductId,
                  const [],
                  const [],
                  true,
                  null,
                  false,
                  null,
                  null,
                  null,
                  null,
                  null,
                ),
              ],
            ),
            const PresentedOfferingContext('default', null, null),
          ),
        )
        .toList();
    packages.removeAt(0);
    final offering = Offering('default', 'Default', const {}, packages);
    final state = SubscriptionState(
      offerings: Offerings({'default': offering}, current: offering),
    );

    expect(state.androidOfferingContract, isNull);
  });
  test('hydrates paid startup state from cached usage snapshot', () {
    final state = buildInitialSubscriptionStateFromUsage(
      UsageData(
        monthlyUsed: 42,
        monthlyLimit: 800,
        dailyUsed: 7,
        dailyLimit: 120,
        dailyResetAt: DateTime.utc(2026, 6, 5),
        tier: SubscriptionTierHelper.essential,
      ),
    );

    expect(state.tier, SubscriptionTierHelper.essential);
    expect(state.isLoading, isTrue);
    expect(state.monthlyMessagesUsed, 42);
    expect(state.dailyMessagesUsed, 7);
    expect(state.monthlyLimit, 800);
    expect(state.dailyLimit, 120);
  });

  test('startup tier preserves cached paid snapshot during transient free sync',
      () {
    final tier = resolveStartupSubscriptionTier(
      databaseTier: SubscriptionTierHelper.free,
      revenueCatTier: SubscriptionTierHelper.free,
      cachedTier: SubscriptionTierHelper.essential,
      serverExpiresAt: DateTime.utc(2026, 7, 5),
      now: DateTime.utc(2026, 6, 5),
    );

    expect(tier, SubscriptionTierHelper.essential);
  });

  test('startup tier allows trusted expired server downgrade to free', () {
    final tier = resolveStartupSubscriptionTier(
      databaseTier: SubscriptionTierHelper.free,
      revenueCatTier: SubscriptionTierHelper.free,
      cachedTier: SubscriptionTierHelper.essential,
      serverExpiresAt: DateTime.utc(2026, 6, 1),
      now: DateTime.utc(2026, 6, 5),
    );

    expect(tier, SubscriptionTierHelper.free);
  });

  test('startup paid rescue upgrades free only after server sync confirms paid',
      () {
    final tier = resolveStartupPaidRescueTier(
      currentTier: SubscriptionTierHelper.free,
      revenueCatTier: SubscriptionTierHelper.essential,
      syncedTier: SubscriptionTierHelper.essential,
    );

    expect(tier, SubscriptionTierHelper.essential);
  });

  test('startup paid rescue keeps free when server sync cannot confirm paid',
      () {
    final tier = resolveStartupPaidRescueTier(
      currentTier: SubscriptionTierHelper.free,
      revenueCatTier: SubscriptionTierHelper.essential,
    );

    expect(tier, SubscriptionTierHelper.free);
  });

  test('startup paid rescue preserves free when RevenueCat is still free', () {
    final tier = resolveStartupPaidRescueTier(
      currentTier: SubscriptionTierHelper.free,
      revenueCatTier: SubscriptionTierHelper.free,
    );

    expect(tier, SubscriptionTierHelper.free);
  });

  test('startup paid rescue never downgrades an existing paid state', () {
    final tier = resolveStartupPaidRescueTier(
      currentTier: SubscriptionTierHelper.starter,
      revenueCatTier: SubscriptionTierHelper.free,
    );

    expect(tier, SubscriptionTierHelper.starter);
  });

  test('source-aware resolver selects one complete effective store row', () {
    final now = DateTime.utc(2026, 8, 23, 12);
    final rows = [
      {
        'user_id': 'user-1',
        'store': 'app_store',
        'product_id': 'ios_starter_monthly',
        'base_plan_id': null,
        'tier': 'starter',
        'status': 'active',
        'expires_at': '2026-08-24T00:00:00Z',
        'event_at': '2026-08-20T00:00:00Z',
        'event_id': 'ios-starter-1',
        'verification_status': 'verified',
      },
      {
        'user_id': 'user-1',
        'store': 'play_store',
        'product_id': 'android_essential:monthly',
        'base_plan_id': 'monthly',
        'tier': 'essential',
        'status': 'active',
        'expires_at': '2026-08-25T00:00:00Z',
        'event_at': '2026-08-21T00:00:00Z',
        'event_id': 'play-essential-1',
        'verification_status': 'verified',
      },
      {
        'user_id': 'user-1',
        'store': 'play_store',
        'product_id': 'android_essential:old',
        'base_plan_id': 'old',
        'tier': 'essential',
        'status': 'active',
        'expires_at': '2026-08-25T00:00:00Z',
        'event_at': '2026-08-22T00:00:00Z',
        'event_id': 'play-essential-unverified',
        'verification_status': 'unverified',
      },
      {
        'user_id': 'user-1',
        'store': 'app_store',
        'product_id': 'ios_essential_expired',
        'base_plan_id': null,
        'tier': 'essential',
        'status': 'active',
        'expires_at': '2026-08-22T00:00:00Z',
        'event_at': '2026-08-22T00:00:00Z',
        'event_id': 'ios-essential-expired',
        'verification_status': 'verified',
      },
      {
        'user_id': 'user-1',
        'store': 'app_store',
        'product_id': 'ios_essential_cancelled',
        'base_plan_id': null,
        'tier': 'essential',
        'status': 'cancelled',
        'expires_at': null,
        'event_at': '2026-08-22T00:00:00Z',
        'event_id': 'ios-essential-cancelled',
        'verification_status': 'verified',
      },
    ];

    final selected = resolveEffectiveSubscriptionStoreState(
      rows,
      userId: 'user-1',
      now: now,
    );

    expect(selected, same(rows[1]));
  });

  test('source-aware merge overrides entitlement but preserves legacy counters',
      () {
    final legacy = <String, dynamic>{
      'user_id': 'user-1',
      'tier': 'free',
      'status': 'active',
      'monthly_messages_used': 7,
      'daily_messages_used': 2,
      'monthly_reset_at': '2026-08-01T00:00:00Z',
      'daily_reset_at': '2026-08-23T00:00:00Z',
    };

    final merged = mergeSourceAwareSubscriptionState(
      legacy: legacy,
      source: {
        'store': 'play_store',
        'product_id': 'android_essential:monthly',
        'base_plan_id': 'monthly',
        'tier': 'essential',
        'status': 'active',
        'expires_at': '2026-08-25T00:00:00Z',
        'revenuecat_environment': 'production',
        'verification_source': 'revenuecat_api',
      },
    );

    expect(merged['tier'], 'essential');
    expect(merged['store'], 'play_store');
    expect(merged['active_product_id'], 'android_essential:monthly');
    expect(merged['base_plan_id'], 'monthly');
    expect(merged['monthly_messages_used'], 7);
    expect(merged['daily_messages_used'], 2);
  });

  test('paid source rows without expiry are rejected instead of perpetual', () {
    final row = <String, dynamic>{
      'user_id': 'user-1',
      'store': 'play_store',
      'product_id': 'vibesync_starter',
      'base_plan_id': 'monthly',
      'tier': 'starter',
      'status': 'active',
      'expires_at': null,
      'event_at': '2026-08-23T11:00:00Z',
      'event_id': 'missing-expiry-client-row',
      'verification_source': 'revenuecat_webhook',
      'verification_status': 'verified',
      'revenuecat_environment': 'production',
    };

    expect(
      resolveEffectiveSubscriptionStoreState(
        [row],
        userId: 'user-1',
        now: DateTime.utc(2026, 8, 23, 12),
      ),
      isNull,
    );
    expect(
      filterVerifiedSubscriptionStoreStateRows(
        [row],
        userId: 'user-1',
        now: DateTime.utc(2026, 8, 23, 12),
      ),
      isEmpty,
    );
  });

  test(
      'source-aware merge falls back to the legacy row when read is unavailable',
      () {
    final legacy = <String, dynamic>{
      'user_id': 'user-1',
      'tier': 'starter',
      'monthly_messages_used': 3,
    };

    expect(
      mergeSourceAwareSubscriptionState(legacy: legacy),
      same(legacy),
    );
  });

  test('verified but expired source state cuts over legacy paid row to free',
      () {
    final merged = applySourceAwareSubscriptionStateRead(
      legacy: {
        'user_id': 'user-1',
        'tier': 'essential',
        'status': 'active',
        'active_product_id': 'old-paid-product',
        'expires_at': '2026-12-23T00:00:00Z',
        'store': 'app_store',
        'base_plan_id': 'old-plan',
        'verification_source': 'revenuecat_api',
        'revenuecat_environment': 'production',
      },
      read: const SourceAwareSubscriptionStateRead(
        effective: null,
        hasVerifiedSource: true,
        cutoverStatus: 'complete',
      ),
    );

    expect(merged['tier'], 'free');
    expect(merged['status'], 'expired');
    expect(merged['active_product_id'], isNull);
    expect(merged['expires_at'], isNull);
    expect(merged['store'], isNull);
    expect(merged['base_plan_id'], isNull);
    expect(merged['verification_source'], isNull);
    expect(merged['revenuecat_environment'], isNull);
  });

  test('source-aware query error falls back to the legacy paid row', () {
    final legacy = <String, dynamic>{
      'user_id': 'user-1',
      'tier': 'essential',
      'active_product_id': 'old-paid-product',
    };

    final merged = applySourceAwareSubscriptionStateRead(
      legacy: legacy,
      read: const SourceAwareSubscriptionStateRead(
        effective: {
          'tier': 'free',
          'status': 'expired',
        },
        hasVerifiedSource: true,
        error: 'query failed',
      ),
    );

    expect(merged, same(legacy));
  });

  test('only unverified source rows fall back to the legacy paid row', () {
    final legacy = <String, dynamic>{
      'user_id': 'user-1',
      'tier': 'essential',
      'active_product_id': 'old-paid-product',
    };

    final merged = applySourceAwareSubscriptionStateRead(
      legacy: legacy,
      read: const SourceAwareSubscriptionStateRead(
        effective: null,
        hasVerifiedSource: false,
      ),
    );

    expect(merged, same(legacy));
  });

  test('future verified source rows do not cut over the legacy paid row', () {
    final legacy = <String, dynamic>{
      'user_id': 'user-1',
      'tier': 'essential',
      'active_product_id': 'old-paid-product',
    };

    final merged = applySourceAwareSubscriptionStateRead(
      legacy: legacy,
      read: const SourceAwareSubscriptionStateRead(
        effective: null,
        hasVerifiedSource: false,
      ),
    );

    expect(merged, same(legacy));
  });

  test(
      'pending cutover preserves an ambiguous paid legacy tier below a verified store',
      () {
    final legacy = <String, dynamic>{
      'user_id': 'user-1',
      'tier': 'essential',
      'status': 'active',
      'active_product_id': 'legacy-essential',
      'store': null,
      'base_plan_id': null,
    };
    final merged = applySourceAwareSubscriptionStateRead(
      legacy: legacy,
      read: const SourceAwareSubscriptionStateRead(
        effective: {
          'store': 'play_store',
          'product_id': 'play-starter',
          'base_plan_id': 'starter',
          'tier': 'starter',
          'status': 'active',
          'expires_at': '2026-09-23T00:00:00Z',
        },
        hasVerifiedSource: true,
        cutoverStatus: 'pending',
      ),
    );

    expect(merged['tier'], 'essential');
    expect(merged['active_product_id'], 'legacy-essential');
    expect(merged['store'], isNull);
  });

  test('source metadata is applied only for an authoritative winner', () {
    final legacy = <String, dynamic>{
      'tier': 'essential',
      'active_product_id': 'legacy-essential',
    };
    const pendingRead = SourceAwareSubscriptionStateRead(
      effective: {
        'store': 'play_store',
        'product_id': 'play-starter',
        'tier': 'starter',
      },
      hasVerifiedSource: true,
      cutoverStatus: 'pending',
    );
    const completeRead = SourceAwareSubscriptionStateRead(
      effective: {
        'store': 'play_store',
        'product_id': 'play-essential',
        'tier': 'essential',
      },
      hasVerifiedSource: true,
      cutoverStatus: 'complete',
    );

    expect(
      shouldApplySourceAwareSubscriptionMetadata(
        legacy: legacy,
        read: pendingRead,
      ),
      isFalse,
    );
    expect(
      shouldApplySourceAwareSubscriptionMetadata(
        legacy: legacy,
        read: completeRead,
      ),
      isTrue,
    );

    expect(
      shouldApplySourceAwareSubscriptionMetadata(
        legacy: legacy,
        read: const SourceAwareSubscriptionStateRead(
          effective: null,
          hasVerifiedSource: true,
          cutoverStatus: 'complete',
        ),
      ),
      isTrue,
    );
    expect(
      resolveSourceStateAuthorityAfterRead(
        current: true,
        legacy: legacy,
        read: const SourceAwareSubscriptionStateRead(
          effective: null,
          hasVerifiedSource: false,
          error: 'query failed',
        ),
      ),
      isTrue,
    );
  });

  test(
      'authoritative free state stays exact when stale paid CustomerInfo sync fails',
      () {
    const current = SubscriptionState(
      tier: SubscriptionTierHelper.free,
      renewsAt: null,
      activeProductId: null,
      activeStore: null,
      activeBasePlanId: null,
      activeVerificationSource: null,
      activeRevenueCatEnvironment: null,
      sourceStateAuthoritative: true,
    );

    final tier = resolveSubscriptionTierAfterSourceAwareSync(
      currentTier: current.tier,
      revenueCatTier: SubscriptionTierHelper.essential,
      syncedTier: null,
      sourceAuthoritative: current.sourceStateAuthoritative,
    );

    expect(tier, SubscriptionTierHelper.free);
    expect(current.sourceStateAuthoritative, isTrue);
    expect(current.renewsAt, isNull);
    expect(current.activeProductId, isNull);
    expect(current.activeStore, isNull);
    expect(current.activeBasePlanId, isNull);
    expect(current.activeVerificationSource, isNull);
    expect(current.activeRevenueCatEnvironment, isNull);
  });

  test('source-authoritative tier is not replaced by an unsynced CustomerInfo',
      () {
    expect(
      resolveSubscriptionTierAfterSourceAwareSync(
        currentTier: 'essential',
        revenueCatTier: 'starter',
        sourceAuthoritative: true,
      ),
      'essential',
    );
    expect(
      resolveSubscriptionTierAfterSourceAwareSync(
        currentTier: 'free',
        revenueCatTier: 'starter',
        sourceAuthoritative: false,
      ),
      'starter',
    );
  });

  test('pending cutover still permits a free legacy row to upgrade', () {
    final merged = applySourceAwareSubscriptionStateRead(
      legacy: {
        'user_id': 'user-1',
        'tier': 'free',
        'status': 'active',
      },
      read: const SourceAwareSubscriptionStateRead(
        effective: {
          'store': 'play_store',
          'product_id': 'play-starter',
          'base_plan_id': 'starter',
          'tier': 'starter',
          'status': 'active',
          'expires_at': '2026-09-23T00:00:00Z',
        },
        hasVerifiedSource: true,
        cutoverStatus: 'pending',
      ),
    );

    expect(merged['tier'], 'starter');
    expect(merged['store'], 'play_store');
  });

  test(
      'source provenance excludes unverified, future, and malformed backfill rows',
      () {
    final now = DateTime.utc(2026, 8, 23, 12);
    final rows = <Map<String, dynamic>>[
      {
        'user_id': 'user-1',
        'store': 'app_store',
        'tier': 'starter',
        'status': 'active',
        'product_id': 'ios-starter',
        'event_id': 'verified-current',
        'event_at': '2026-08-23T11:00:00Z',
        'expires_at': '2026-09-23T11:00:00Z',
        'verification_source': 'revenuecat_api',
        'verification_status': 'verified',
      },
      {
        'user_id': 'user-1',
        'store': 'play_store',
        'tier': 'essential',
        'status': 'active',
        'product_id': 'play-essential:monthly',
        'event_id': 'future-verified',
        'event_at': '2026-08-24T11:00:00Z',
        'expires_at': '2026-09-24T11:00:00Z',
        'verification_source': 'revenuecat_api',
        'verification_status': 'verified',
      },
      {
        'user_id': 'user-1',
        'store': 'play_store',
        'tier': 'essential',
        'status': 'active',
        'product_id': 'play-essential:monthly',
        'event_id': 'unverified-current',
        'event_at': '2026-08-23T11:30:00Z',
        'expires_at': '2026-09-23T11:30:00Z',
        'verification_source': 'legacy_backfill',
        'verification_status': 'unverified',
      },
      {
        'user_id': 'user-1',
        'store': 'play_store',
        'tier': 'essential',
        'status': 'active',
        'product_id': 'play-essential:monthly',
        'event_id': 'malformed-verified-backfill',
        'event_at': '2026-08-23T11:40:00Z',
        'expires_at': '2026-09-23T11:40:00Z',
        'verification_source': 'legacy_backfill',
        'verification_status': 'verified',
      },
    ];

    final sources = filterVerifiedSubscriptionStoreStateRows(
      rows,
      userId: 'user-1',
      now: now,
    );

    expect(sources, hasLength(1));
    expect(sources.single['event_id'], 'verified-current');
  });
}
