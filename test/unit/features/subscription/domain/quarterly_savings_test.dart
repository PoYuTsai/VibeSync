import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:vibesync/features/subscription/domain/services/quarterly_savings.dart';

void main() {
  StoreProduct product({
    required double price,
    String currencyCode = 'TWD',
  }) {
    return StoreProduct(
      'product_id',
      'description',
      'title',
      price,
      'NT\$$price',
      currencyCode,
    );
  }

  group('quarterlySavingsLabel', () {
    test('computes savings vs three months of monthly price', () {
      final label = quarterlySavingsLabel(
        monthly: product(price: 590),
        quarterly: product(price: 1290),
      );
      // 1 - 1290 / (590 * 3) = 27.11% → floor 27
      expect(label, '省 27%');
    });

    test('floors instead of rounding so savings are never overstated', () {
      final label = quarterlySavingsLabel(
        monthly: product(price: 100),
        quarterly: product(price: 205),
      );
      // 1 - 205 / 300 = 31.67% → floor 31, not 32
      expect(label, '省 31%');
    });

    test('returns null when monthly product is missing', () {
      expect(
        quarterlySavingsLabel(monthly: null, quarterly: product(price: 1290)),
        isNull,
      );
    });

    test('returns null when quarterly product is missing', () {
      expect(
        quarterlySavingsLabel(monthly: product(price: 590), quarterly: null),
        isNull,
      );
    });

    test('returns null when currencies differ', () {
      expect(
        quarterlySavingsLabel(
          monthly: product(price: 590, currencyCode: 'TWD'),
          quarterly: product(price: 39, currencyCode: 'USD'),
        ),
        isNull,
      );
    });

    test('returns null when quarterly price offers no savings', () {
      expect(
        quarterlySavingsLabel(
          monthly: product(price: 590),
          quarterly: product(price: 1770),
        ),
        isNull,
      );
    });

    test('returns null when savings floor below 1%', () {
      expect(
        quarterlySavingsLabel(
          monthly: product(price: 590),
          quarterly: product(price: 1765),
        ),
        isNull,
      );
    });

    test('returns null when monthly price is zero or negative', () {
      expect(
        quarterlySavingsLabel(
          monthly: product(price: 0),
          quarterly: product(price: 1290),
        ),
        isNull,
      );
    });

    test('returns null when quarterly price is zero or negative', () {
      expect(
        quarterlySavingsLabel(
          monthly: product(price: 590),
          quarterly: product(price: 0),
        ),
        isNull,
      );
    });
  });
}
