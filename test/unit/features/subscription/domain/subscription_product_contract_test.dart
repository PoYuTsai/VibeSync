import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_product_contract.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_tier_helper.dart';

void main() {
  Package androidPackage(
    SubscriptionPlanDefinition plan, {
    String? packageId,
    String? storeProductId,
    String? optionStoreProductId,
    String? optionProductId,
    String? optionId,
    bool isBasePlan = true,
    String title = '無關的多語系標題',
  }) {
    final combined = plan.playProductWithBasePlan;
    final option = SubscriptionOption(
      optionId ?? plan.basePlanId,
      optionStoreProductId ?? combined,
      optionProductId ?? plan.playProductId,
      const [],
      const [],
      isBasePlan,
      null,
      false,
      null,
      null,
      null,
      null,
      null,
    );
    return Package(
      packageId ?? plan.packageId,
      PackageType.custom,
      StoreProduct(
        storeProductId ?? combined,
        '任意描述不應參與辨識',
        title,
        590,
        r'$590',
        'TWD',
        subscriptionOptions: [option],
      ),
      const PresentedOfferingContext('default', null, null),
    );
  }

  List<Package> completeOffering() => [
        for (final plan in SubscriptionPlanDefinition.androidPlans)
          androidPackage(plan),
      ];

  test('contains the four frozen exact mappings', () {
    expect(
      SubscriptionPlanDefinition.androidPlans
          .map((plan) =>
              '${plan.playProductWithBasePlan} -> ${plan.packageId} -> ${plan.tier}')
          .toList(),
      [
        'vibesync_starter:monthly -> starter_monthly -> starter',
        'vibesync_starter:quarterly -> starter_quarterly -> starter',
        'vibesync_essential:monthly -> essential_monthly -> essential',
        'vibesync_essential:quarterly -> essential_quarterly -> essential',
      ],
    );
  });

  test('validates package, combined StoreProduct and base-plan option exactly',
      () {
    final contract = AndroidSubscriptionOfferingContract.fromPackages(
      completeOffering(),
    );

    expect(contract, isNotNull);
    expect(
      contract!.packageFor('starter_monthly')!.storeProduct.identifier,
      'vibesync_starter:monthly',
    );
  });

  test('fails closed when any one product is missing', () {
    final packages = completeOffering()..removeAt(0);
    expect(AndroidSubscriptionOfferingContract.fromPackages(packages), isNull);
  });

  test('fails closed when a package identifier is duplicated', () {
    final packages = completeOffering()
      ..add(androidPackage(SubscriptionPlanDefinition.starterMonthly));
    expect(AndroidSubscriptionOfferingContract.fromPackages(packages), isNull);
  });

  test('fails closed when product or base-plan is mismatched', () {
    final packages = completeOffering();
    packages[0] = androidPackage(
      SubscriptionPlanDefinition.starterMonthly,
      storeProductId: 'vibesync_essential:monthly',
    );
    expect(AndroidSubscriptionOfferingContract.fromPackages(packages), isNull);

    final wrongOption = completeOffering();
    wrongOption[0] = androidPackage(
      SubscriptionPlanDefinition.starterMonthly,
      optionStoreProductId: 'vibesync_starter:quarterly',
    );
    expect(
        AndroidSubscriptionOfferingContract.fromPackages(wrongOption), isNull);

    final wrongOptionId = completeOffering();
    wrongOptionId[0] = androidPackage(
      SubscriptionPlanDefinition.starterMonthly,
      optionId: 'quarterly',
    );
    expect(AndroidSubscriptionOfferingContract.fromPackages(wrongOptionId),
        isNull);
  });

  test('never uses title, description, or period fuzzy matching', () {
    final packages = completeOffering();
    packages[0] = androidPackage(
      SubscriptionPlanDefinition.starterMonthly,
      packageId: r'$rc_monthly',
      storeProductId: 'some_unknown_product',
      title: 'Starter 月繳',
    );
    expect(AndroidSubscriptionOfferingContract.fromPackages(packages), isNull);
  });

  test('normalizes only exact bare or combined Play product IDs', () {
    final monthly = SubscriptionPlanDefinition.fromAuthoritativePlayIdentifiers(
      productId: 'vibesync_starter',
      basePlanId: 'monthly',
    );
    final combined =
        SubscriptionPlanDefinition.fromAuthoritativePlayIdentifiers(
      productId: 'vibesync_starter:monthly',
      basePlanId: 'monthly',
    );

    expect(monthly, SubscriptionPlanDefinition.starterMonthly);
    expect(combined, SubscriptionPlanDefinition.starterMonthly);
    expect(
      SubscriptionPlanDefinition.fromAuthoritativePlayIdentifiers(
        productId: 'vibesync_starter:monthly',
        basePlanId: 'quarterly',
      ),
      isNull,
    );
    expect(
      SubscriptionPlanDefinition.fromAuthoritativePlayIdentifiers(
        productId: 'vibesync_starter',
        basePlanId: null,
      ),
      isNull,
    );
  });

  test('replacement modes use bare old product identifier', () {
    final upgrade = resolveAndroidReplacement(
      target: SubscriptionPlanDefinition.essentialMonthly,
      activeStore: 'play_store',
      activeProductId: 'vibesync_starter:monthly',
      activeBasePlanId: 'monthly',
      activeStateAuthoritative: true,
      hasActivePaidState: true,
    );
    expect(upgrade.mode,
        AndroidSubscriptionReplacementMode.immediateAndChargeProratedPrice);
    expect(upgrade.oldProductIdentifier, 'vibesync_starter');
    expect(
      googleProrationModeFor(upgrade.mode),
      GoogleProrationMode.immediateAndChargeProratedPrice,
    );

    final downgrade = resolveAndroidReplacement(
      target: SubscriptionPlanDefinition.starterMonthly,
      activeStore: 'play_store',
      activeProductId: 'vibesync_essential',
      activeBasePlanId: 'monthly',
      activeStateAuthoritative: true,
      hasActivePaidState: true,
    );
    expect(downgrade.mode, AndroidSubscriptionReplacementMode.deferred);
    expect(downgrade.oldProductIdentifier, 'vibesync_essential');

    final periodChange = resolveAndroidReplacement(
      target: SubscriptionPlanDefinition.starterQuarterly,
      activeStore: 'play_store',
      activeProductId: 'vibesync_starter',
      activeBasePlanId: 'monthly',
      activeStateAuthoritative: true,
      hasActivePaidState: true,
    );
    expect(periodChange.mode,
        AndroidSubscriptionReplacementMode.immediateWithoutProration);
    expect(googleProrationModeFor(periodChange.mode),
        GoogleProrationMode.immediateWithoutProration);
  });

  test('missing authoritative original subscription fails closed', () {
    final decision = resolveAndroidReplacement(
      target: SubscriptionPlanDefinition.essentialMonthly,
      activeStore: 'play_store',
      activeProductId: null,
      activeBasePlanId: null,
      activeStateAuthoritative: false,
      hasActivePaidState: true,
    );

    expect(decision.isAllowed, isFalse);
    expect(decision.mode, isNull);
    expect(decision.oldProductIdentifier, isNull);
  });

  test('free user starts a package purchase without replacement info', () {
    final decision = resolveAndroidReplacement(
      target: SubscriptionPlanDefinition.starterMonthly,
      activeStore: null,
      activeProductId: null,
      activeBasePlanId: null,
      activeStateAuthoritative: false,
      hasActivePaidState: false,
    );

    expect(decision.isAllowed, isTrue);
    expect(decision.isReplacement, isFalse);
    expect(decision.oldProductIdentifier, isNull);
  });

  test(
      'same-tier period copy says switch is immediate and new price is next renewal',
      () {
    final message = replacementConfirmationMessage(
      AndroidSubscriptionReplacementMode.immediateWithoutProration,
    );

    expect(message, contains('立即切換'));
    expect(message, contains('下次續訂'));
    expect(message, contains('新價格'));
  });

  test('iOS mapping remains an exact known product allowlist', () {
    final product = SubscriptionPlanDefinition.essentialMonthly;
    expect(
        product.matchesIosProductId('vibesync_essential_monthly_v2'), isTrue);
    expect(product.matchesIosProductId('Essential 月繳'), isFalse);
    expect(product.tier, SubscriptionTierHelper.essential);
  });
}
