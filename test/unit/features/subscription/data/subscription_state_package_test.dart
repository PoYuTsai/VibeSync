import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';

void main() {
  Package package({
    required String packageId,
    required PackageType packageType,
    required String productId,
    required String title,
    String? subscriptionPeriod,
  }) {
    return Package(
      packageId,
      packageType,
      StoreProduct(
        productId,
        'description',
        title,
        590,
        r'$590',
        'TWD',
        subscriptionPeriod: subscriptionPeriod,
      ),
      const PresentedOfferingContext('default', null, null),
    );
  }

  StoreProduct storeProduct({
    required String productId,
    required String title,
    String? subscriptionPeriod,
  }) {
    return StoreProduct(
      productId,
      'description',
      title,
      590,
      r'$590',
      'TWD',
      subscriptionPeriod: subscriptionPeriod,
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

  test('maps monthly packages even when product id omits the period word', () {
    final state = stateWithPackages([
      package(
        packageId: r'$rc_monthly',
        packageType: PackageType.monthly,
        productId: 'starter',
        title: 'Starter',
        subscriptionPeriod: 'P1M',
      ),
    ]);

    expect(state.starterMonthlyPackage?.storeProduct.identifier, 'starter');
  });

  test('maps three-month packages as quarterly plans', () {
    final state = stateWithPackages([
      package(
        packageId: r'$rc_three_month',
        packageType: PackageType.threeMonth,
        productId: 'essential',
        title: 'Essential',
        subscriptionPeriod: 'P3M',
      ),
    ]);

    expect(
        state.essentialQuarterlyPackage?.storeProduct.identifier, 'essential');
  });

  test('does not map three-month packages as monthly plans', () {
    final state = stateWithPackages([
      package(
        packageId: r'$rc_three_month',
        packageType: PackageType.threeMonth,
        productId: 'starter',
        title: 'Starter',
        subscriptionPeriod: 'P3M',
      ),
      package(
        packageId: r'$rc_monthly',
        packageType: PackageType.monthly,
        productId: 'starter',
        title: 'Starter',
        subscriptionPeriod: 'P1M',
      ),
    ]);

    expect(state.starterMonthlyPackage?.packageType, PackageType.monthly);
    expect(state.starterMonthlyPackage?.storeProduct.subscriptionPeriod, 'P1M');
    expect(
      state.starterQuarterlyPackage?.packageType,
      PackageType.threeMonth,
    );
  });

  test('maps all exact package product ids to the selected paywall option', () {
    final state = stateWithPackages([
      package(
        packageId: 'starter_quarterly',
        packageType: PackageType.threeMonth,
        productId: 'vibesync_starter_quarterly_v2',
        title: 'Starter quarterly',
        subscriptionPeriod: 'P3M',
      ),
      package(
        packageId: 'starter_monthly',
        packageType: PackageType.monthly,
        productId: 'vibesync_starter_monthly_v2',
        title: 'Starter monthly',
        subscriptionPeriod: 'P1M',
      ),
      package(
        packageId: 'essential_quarterly',
        packageType: PackageType.threeMonth,
        productId: 'vibesync_essential_quarterly_v2',
        title: 'Essential quarterly',
        subscriptionPeriod: 'P3M',
      ),
      package(
        packageId: 'essential_monthly',
        packageType: PackageType.monthly,
        productId: 'vibesync_essential_monthly_v2',
        title: 'Essential monthly',
        subscriptionPeriod: 'P1M',
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

  test('uses package title and subscription period when product ids are terse',
      () {
    final state = stateWithPackages([
      package(
        packageId: 'pkg_001',
        packageType: PackageType.unknown,
        productId: 'ios_001',
        title: 'Starter 季繳',
        subscriptionPeriod: 'P3M',
      ),
    ]);

    expect(state.starterQuarterlyPackage?.storeProduct.identifier, 'ios_001');
  });

  test('maps direct store products when offerings are unavailable', () {
    final state = SubscriptionState(
      storeProducts: {
        'vibesync_essential_monthly_v2': storeProduct(
          productId: 'vibesync_essential_monthly_v2',
          title: 'Essential',
          subscriptionPeriod: 'P1M',
        ),
      },
    );

    expect(
      state.essentialMonthlyStoreProduct?.identifier,
      'vibesync_essential_monthly_v2',
    );
  });

  test('maps direct store products to the exact selected period', () {
    final state = SubscriptionState(
      storeProducts: {
        'vibesync_starter_quarterly_v2': storeProduct(
          productId: 'vibesync_starter_quarterly_v2',
          title: 'Starter quarterly',
          subscriptionPeriod: 'P3M',
        ),
        'vibesync_starter_monthly_v2': storeProduct(
          productId: 'vibesync_starter_monthly_v2',
          title: 'Starter monthly',
          subscriptionPeriod: 'P1M',
        ),
        'vibesync_essential_quarterly_v2': storeProduct(
          productId: 'vibesync_essential_quarterly_v2',
          title: 'Essential quarterly',
          subscriptionPeriod: 'P3M',
        ),
        'vibesync_essential_monthly_v2': storeProduct(
          productId: 'vibesync_essential_monthly_v2',
          title: 'Essential monthly',
          subscriptionPeriod: 'P1M',
        ),
      },
    );

    expect(
      state.starterMonthlyStoreProduct?.identifier,
      'vibesync_starter_monthly_v2',
    );
    expect(
      state.starterQuarterlyStoreProduct?.identifier,
      'vibesync_starter_quarterly_v2',
    );
    expect(
      state.essentialMonthlyStoreProduct?.identifier,
      'vibesync_essential_monthly_v2',
    );
    expect(
      state.essentialQuarterlyStoreProduct?.identifier,
      'vibesync_essential_quarterly_v2',
    );
  });

  test('prefers package product over direct store product for purchases', () {
    final packageProduct = package(
      packageId: r'$rc_monthly',
      packageType: PackageType.monthly,
      productId: 'starter_monthly',
      title: 'Starter',
      subscriptionPeriod: 'P1M',
    );
    final state = stateWithPackages([packageProduct]).copyWith(
      storeProducts: {
        'vibesync_starter_monthly_v2': storeProduct(
          productId: 'vibesync_starter_monthly_v2',
          title: 'Starter',
          subscriptionPeriod: 'P1M',
        ),
      },
    );

    expect(state.starterMonthlyPackage?.storeProduct.identifier,
        'starter_monthly');
    expect(state.starterMonthlyStoreProduct?.identifier,
        'vibesync_starter_monthly_v2');
  });
}
