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

  // Onboarding 第 9 步：購買版季繳卡的灰色月均價小字。
  group('quarterlyMonthlyAverageLabel', () {
    StoreProduct quarterly(double price, String priceString) => StoreProduct(
          'starter_quarterly',
          'description',
          'Starter',
          price,
          priceString,
          'TWD',
          subscriptionPeriod: 'P3M',
        );

    test('整除：平均每月，幣別符號照 StoreKit 的字串', () {
      expect(
        quarterlyMonthlyAverageLabel(quarterly(1590, r'NT$1,590')),
        r'平均每月 NT$530',
      );
    });

    test('除不盡：無條件進位，千分位照原本的寫法，加「約」', () {
      // 3490 ÷ 3 = 1163.33…
      expect(
        quarterlyMonthlyAverageLabel(quarterly(3490, r'NT$3,490')),
        r'平均每月約 NT$1,164',
      );
      // 2000 ÷ 3 = 666.67… → 667，不是四捨五入也不是捨去成 666。
      expect(
        quarterlyMonthlyAverageLabel(quarterly(2000, '¥2,000')),
        '平均每月約 ¥667',
      );
    });

    test('有小數的幣別：進位到最小單位，小數點與幣別位置照原字串', () {
      // 19.99 ÷ 3 = 6.6633… → 6.67
      expect(
        quarterlyMonthlyAverageLabel(quarterly(19.99, r'$19.99')),
        r'平均每月約 $6.67',
      );
      expect(
        quarterlyMonthlyAverageLabel(quarterly(1590, '1.590,00 €')),
        '平均每月 530,00 €',
      );
      expect(
        quarterlyMonthlyAverageLabel(quarterly(1590, r'NT$1,590.00')),
        r'平均每月 NT$530.00',
      );
    });

    test('永遠比扣款金額小、而且乘回 3 不會少於扣款金額（不少報每月成本）', () {
      for (var price = 3; price <= 6000; price += 7) {
        final label = quarterlyMonthlyAverageLabel(
          quarterly(price.toDouble(), 'NT\$$price'),
        );
        final average = int.parse(label!.replaceAll(RegExp(r'\D'), ''));
        expect(average, lessThan(price), reason: '$price');
        expect(average * 3, greaterThanOrEqualTo(price), reason: '$price');
        expect(average * 3 - price, lessThan(3), reason: '$price');
      }
    });

    test('看不懂或對不上就不顯示', () {
      expect(quarterlyMonthlyAverageLabel(null), isNull);
      // 字串跟 price 對不上（解析錯就不寫）。
      expect(quarterlyMonthlyAverageLabel(quarterly(1590, r'NT$590')), isNull);
      expect(quarterlyMonthlyAverageLabel(quarterly(1590, '價格')), isNull);
      expect(quarterlyMonthlyAverageLabel(quarterly(0, r'NT$0')), isNull);
      // 小到除不出比扣款金額小的數字。
      expect(quarterlyMonthlyAverageLabel(quarterly(1, r'NT$1')), isNull);
    });
  });
}
