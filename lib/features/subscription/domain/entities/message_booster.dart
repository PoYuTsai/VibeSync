/// Available message booster packages for one-time purchase.
enum BoosterPackage {
  small,
  medium,
  large,
}

extension BoosterPackageExtension on BoosterPackage {
  int get messageCount {
    switch (this) {
      case BoosterPackage.small:
        return 50;
      case BoosterPackage.medium:
        return 150;
      case BoosterPackage.large:
        return 300;
    }
  }

  int get priceNTD {
    switch (this) {
      case BoosterPackage.small:
        return 39;
      case BoosterPackage.medium:
        return 99;
      case BoosterPackage.large:
        return 179;
    }
  }

  double get costPerMessage => priceNTD / messageCount;

  String get label => '$messageCount 則';

  String get priceLabel => 'NT\$$priceNTD';

  String get savingsLabel {
    switch (this) {
      case BoosterPackage.small:
        return '';
      case BoosterPackage.medium:
        return '省 15%';
      case BoosterPackage.large:
        return '省 23%';
    }
  }
}
