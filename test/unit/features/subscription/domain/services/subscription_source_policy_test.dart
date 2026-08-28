import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_product_contract.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_source_policy.dart';

void main() {
  final now = DateTime.utc(2026, 8, 28, 12);

  SubscriptionSourceState source({
    required String store,
    String tier = 'starter',
    String status = 'active',
    DateTime? expiresAt,
    String? productId,
    String? basePlanId,
    String verificationStatus = 'verified',
  }) {
    return SubscriptionSourceState(
      store: store,
      productId: productId ?? 'vibesync_$tier',
      basePlanId: basePlanId ?? 'monthly',
      tier: tier,
      status: status,
      expiresAt: expiresAt ?? now.add(const Duration(days: 30)),
      eventAt: now.subtract(const Duration(days: 30)),
      eventId: '$store-$tier-$status',
      verificationSource: 'revenuecat_webhook',
      verificationStatus: verificationStatus,
      revenueCatEnvironment: 'production',
    );
  }

  test('projection rejects malformed rows instead of guessing their source',
      () {
    expect(
      SubscriptionSourceState.fromRow({
        'store': 'ios',
        'tier': 'essential',
        'status': 'active',
        'verification_status': 'verified',
        'verification_source': 'revenuecat_webhook',
        'event_id': 'bad-source',
        'event_at': now.toIso8601String(),
      }),
      isNull,
    );
    expect(
      SubscriptionSourceState.fromRow({
        'store': 'play_store',
        'tier': 'essential',
        'status': 'active',
        'verification_status': 'verified',
        'product_id': 'vibesync_essential:monthly',
        'verification_source': 'revenuecat_webhook',
        'event_id': 'good-source',
        'event_at': now.toIso8601String(),
      })?.store,
      'play_store',
    );
    expect(
      SubscriptionSourceState.fromRow({
        'store': 'play_store',
        'tier': 'starter',
        'status': 'active',
        'verification_status': 'verified',
        'verification_source': 'revenuecat_webhook',
        'event_id': 'missing-product',
        'event_at': now.toIso8601String(),
      }),
      isNull,
    );
    expect(
      SubscriptionSourceState.fromRow({
        'store': 'play_store',
        'tier': 'starter',
        'status': 'active',
        'verification_status': 'verified',
        'verification_source': 'legacy_backfill',
        'product_id': 'vibesync_starter:monthly',
        'event_id': 'invalid-provenance',
        'event_at': now.toIso8601String(),
      }),
      isNull,
    );
  });

  test('active App Store source blocks a Google Play purchase', () {
    final eligibility = resolveSourceAwarePurchaseEligibility(
      targetStore: 'play_store',
      targetPlan: SubscriptionPlanDefinition.starterMonthly,
      sources: [source(store: 'app_store', tier: 'essential')],
      sourceStateAuthoritative: true,
      hasActivePaidState: true,
      now: now,
    );

    expect(eligibility.canPurchase, isFalse);
    expect(
        eligibility.blockReason, SourceAwarePurchaseBlockReason.originalStore);
    expect(eligibility.originalStore, 'app_store');
    expect(eligibility.message, contains('App Store'));
    expect(eligibility.message, isNot(contains('Google Play 訂閱')));
  });

  test('two active stores block a second purchase and name both stores', () {
    final eligibility = resolveSourceAwarePurchaseEligibility(
      targetStore: 'play_store',
      targetPlan: SubscriptionPlanDefinition.essentialMonthly,
      sources: [
        source(store: 'app_store', tier: 'starter'),
        source(store: 'play_store', tier: 'essential'),
      ],
      sourceStateAuthoritative: true,
      hasActivePaidState: true,
      now: now,
    );

    expect(eligibility.canPurchase, isFalse);
    expect(
        eligibility.blockReason, SourceAwarePurchaseBlockReason.multipleStores);
    expect(eligibility.message, contains('App Store'));
    expect(eligibility.message, contains('Google Play'));
  });

  test('an expired original source no longer blocks a new purchase', () {
    final eligibility = resolveSourceAwarePurchaseEligibility(
      targetStore: 'play_store',
      targetPlan: SubscriptionPlanDefinition.starterMonthly,
      sources: [
        source(
          store: 'app_store',
          tier: 'starter',
          status: 'expired',
          expiresAt: now.subtract(const Duration(minutes: 1)),
        ),
      ],
      sourceStateAuthoritative: true,
      hasActivePaidState: false,
      now: now,
    );

    expect(eligibility.canPurchase, isTrue);
    expect(eligibility.activeSources, isEmpty);
  });

  test('authoritative Play source uses the existing exact replacement contract',
      () {
    final eligibility = resolveSourceAwarePurchaseEligibility(
      targetStore: 'play_store',
      targetPlan: SubscriptionPlanDefinition.essentialMonthly,
      sources: [source(store: 'play_store', tier: 'starter')],
      sourceStateAuthoritative: true,
      hasActivePaidState: true,
      now: now,
    );

    expect(eligibility.canPurchase, isTrue);
    expect(
      eligibility.replacement?.mode,
      AndroidSubscriptionReplacementMode.immediateAndChargeProratedPrice,
    );
    expect(eligibility.replacement?.oldProductIdentifier, 'vibesync_starter');
  });

  test('same Play plan is not purchased again', () {
    final eligibility = resolveSourceAwarePurchaseEligibility(
      targetStore: 'play_store',
      targetPlan: SubscriptionPlanDefinition.starterMonthly,
      sources: [source(store: 'play_store', tier: 'starter')],
      sourceStateAuthoritative: true,
      hasActivePaidState: true,
      now: now,
    );

    expect(eligibility.canPurchase, isFalse);
    expect(eligibility.blockReason, SourceAwarePurchaseBlockReason.samePlan);
  });

  test('same App Store plan is not purchased again', () {
    final eligibility = resolveSourceAwarePurchaseEligibility(
      targetStore: 'app_store',
      targetPlan: SubscriptionPlanDefinition.starterMonthly,
      sources: [
        source(
          store: 'app_store',
          tier: 'starter',
          productId: 'starter_monthly',
          basePlanId: null,
        ),
      ],
      sourceStateAuthoritative: true,
      hasActivePaidState: true,
      now: now,
    );

    expect(eligibility.canPurchase, isFalse);
    expect(eligibility.blockReason, SourceAwarePurchaseBlockReason.samePlan);
  });

  test('unknown App Store product blocks instead of allowing a second purchase',
      () {
    final eligibility = resolveSourceAwarePurchaseEligibility(
      targetStore: 'app_store',
      targetPlan: SubscriptionPlanDefinition.starterMonthly,
      sources: [source(store: 'app_store', productId: 'unknown-product')],
      sourceStateAuthoritative: true,
      hasActivePaidState: true,
      now: now,
    );

    expect(eligibility.canPurchase, isFalse);
    expect(
      eligibility.blockReason,
      SourceAwarePurchaseBlockReason.unknownSource,
    );
  });

  test('missing source proof blocks a paid local tuple', () {
    final eligibility = resolveSourceAwarePurchaseEligibility(
      targetStore: 'play_store',
      targetPlan: SubscriptionPlanDefinition.starterMonthly,
      sources: const [],
      sourceStateAuthoritative: false,
      hasActivePaidState: true,
      now: now,
    );

    expect(eligibility.canPurchase, isFalse);
    expect(
        eligibility.blockReason, SourceAwarePurchaseBlockReason.unknownSource);
    expect(eligibility.message, contains('尚未完成驗證'));
  });

  test('source-aware copy names only verified stores and handles both stores',
      () {
    final play = source(store: 'play_store', tier: 'starter');
    final app = source(store: 'app_store', tier: 'essential');

    expect(
      sourceAwareEntitlementHeadline(
        tier: 'starter',
        sources: [play],
        now: now,
      ),
      '權益已啟用：Starter',
    );
    expect(sourceAwareSourceDetails([play], now: now), ['Google Play：Starter']);
    expect(sourceAwareSourceDetails([app], now: now), ['App Store：Essential']);
    expect(
      sourceAwareManagementStoreLabel(sources: [play], now: now),
      'Google Play',
    );
    expect(
      sourceAwareManagementStoreLabel(sources: [app, play], now: now),
      'App Store 與 Google Play',
    );
    expect(
      sourceAwareSourceDetails([play, app], now: now),
      ['App Store：Essential', 'Google Play：Starter'],
    );
    expect(
      sourceAwareEntitlementHeadline(
        tier: 'free',
        sources: [
          source(
            store: 'play_store',
            tier: 'free',
            status: 'expired',
            expiresAt: now.subtract(const Duration(minutes: 1)),
          ),
        ],
        now: now,
      ),
      '目前沒有啟用中的訂閱權益',
    );
  });

  test('account deletion copy follows active source stores', () {
    expect(
      sourceAwareAccountDeletionCopy([source(store: 'play_store')], now: now),
      contains('Google Play'),
    );
    expect(
      sourceAwareAccountDeletionCopy(
        [source(store: 'play_store'), source(store: 'app_store')],
        now: now,
      ),
      allOf(contains('App Store'), contains('Google Play')),
    );
    expect(
      sourceAwareAccountDeletionCopy(const [], now: now),
      isNot(contains('App Store')),
    );
  });
}
