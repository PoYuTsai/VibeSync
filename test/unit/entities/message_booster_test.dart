import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/subscription/domain/entities/message_booster.dart';

void main() {
  group('BoosterPackage', () {
    test('small package has correct values', () {
      const pkg = BoosterPackage.small;

      expect(pkg.messageCount, 50);
      expect(pkg.priceNTD, 39);
      expect(pkg.label, '50 則');
      expect(pkg.priceLabel, 'NT\$39');
      expect(pkg.savingsLabel, '');
    });

    test('medium package has correct values', () {
      const pkg = BoosterPackage.medium;

      expect(pkg.messageCount, 150);
      expect(pkg.priceNTD, 99);
      expect(pkg.label, '150 則');
      expect(pkg.priceLabel, 'NT\$99');
      expect(pkg.savingsLabel, '省 15%');
    });

    test('large package has correct values', () {
      const pkg = BoosterPackage.large;

      expect(pkg.messageCount, 300);
      expect(pkg.priceNTD, 179);
      expect(pkg.label, '300 則');
      expect(pkg.priceLabel, 'NT\$179');
      expect(pkg.savingsLabel, '省 23%');
    });

    test('cost per message is calculated correctly', () {
      expect(BoosterPackage.small.costPerMessage, closeTo(0.78, 0.01));
      expect(BoosterPackage.medium.costPerMessage, closeTo(0.66, 0.01));
      expect(BoosterPackage.large.costPerMessage, closeTo(0.597, 0.01));
    });

    test('larger packages have lower cost per message', () {
      final smallCost = BoosterPackage.small.costPerMessage;
      final mediumCost = BoosterPackage.medium.costPerMessage;
      final largeCost = BoosterPackage.large.costPerMessage;

      expect(mediumCost, lessThan(smallCost));
      expect(largeCost, lessThan(mediumCost));
    });
  });
}
