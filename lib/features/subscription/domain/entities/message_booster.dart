// lib/features/subscription/domain/entities/message_booster.dart

/// Available message booster packages for one-time purchase
enum BoosterPackage {
  small,  // 50 messages
  medium, // 150 messages
  large,  // 300 messages
}

extension BoosterPackageExtension on BoosterPackage {
  /// Number of messages in this package
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

  /// Price in NTD
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

  /// Cost per message
  double get costPerMessage {
    return priceNTD / messageCount;
  }

  /// Display label for message count
  String get label {
    return '$messageCount 則';
  }

  /// Display label for price
  String get priceLabel {
    return 'NT\$$priceNTD';
  }

  /// Savings label for discounted packages
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
