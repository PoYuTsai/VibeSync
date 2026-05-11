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
}
