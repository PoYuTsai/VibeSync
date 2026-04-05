import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../features/subscription/domain/services/subscription_tier_helper.dart';
import '../config/environment.dart';
import '../utils/platform_info.dart';

/// Thin wrapper around RevenueCat to keep platform checks and tier mapping in
/// one place.
class RevenueCatService {
  static bool _isInitialized = false;

  static void _log(String message) {
    if (kDebugMode) {
      debugPrint(message);
    }
  }

  static Future<void> initialize() async {
    if (_isInitialized) return;

    if (kIsWeb) {
      _log('RevenueCat: Web platform not supported');
      return;
    }

    final apiKey = AppConfig.revenueCatApiKey;
    if (apiKey.isEmpty) {
      _log('RevenueCat: API key not configured');
      return;
    }

    await Purchases.setLogLevel(LogLevel.debug);

    late final PurchasesConfiguration configuration;
    if (isIOSPlatform) {
      configuration = PurchasesConfiguration(apiKey);
    } else if (isAndroidPlatform) {
      _log('RevenueCat: Android not yet configured');
      return;
    } else {
      _log('RevenueCat: Unsupported platform');
      return;
    }

    await Purchases.configure(configuration);
    _isInitialized = true;
    _log('RevenueCat initialized');
  }

  static bool get isInitialized => _isInitialized;

  static Future<void> login(String userId) async {
    if (!_isInitialized) return;

    try {
      await Purchases.logIn(userId);
      _log('RevenueCat: User logged in');
    } catch (error) {
      _log('RevenueCat login error: $error');
    }
  }

  static Future<void> logout() async {
    if (!_isInitialized) return;

    try {
      await Purchases.logOut();
      _log('RevenueCat: User logged out');
    } catch (error) {
      _log('RevenueCat logout error: $error');
    }
  }

  static Future<Offerings?> getOfferings() async {
    if (!_isInitialized) return null;

    try {
      return await Purchases.getOfferings();
    } catch (error) {
      _log('RevenueCat getOfferings error: $error');
      return null;
    }
  }

  static Future<CustomerInfo> purchase(Package package) async {
    if (!_isInitialized) {
      throw Exception('RevenueCat not initialized');
    }

    try {
      final result = await Purchases.purchase(PurchaseParams.package(package));
      _log('RevenueCat: Purchase successful');
      return result.customerInfo;
    } catch (error) {
      _log('RevenueCat purchase error: $error');
      rethrow;
    }
  }

  static Future<CustomerInfo> restorePurchases() async {
    if (!_isInitialized) {
      throw Exception('RevenueCat not initialized');
    }

    try {
      final customerInfo = await Purchases.restorePurchases();
      _log('RevenueCat: Purchases restored');
      return customerInfo;
    } catch (error) {
      _log('RevenueCat restore error: $error');
      rethrow;
    }
  }

  static Future<CustomerInfo?> getCustomerInfo() async {
    if (!_isInitialized) return null;

    try {
      return await Purchases.getCustomerInfo();
    } catch (error) {
      _log('RevenueCat getCustomerInfo error: $error');
      return null;
    }
  }

  static Future<bool> hasPremiumEntitlement() async {
    final customerInfo = await getCustomerInfo();
    if (customerInfo == null) return false;

    return customerInfo.entitlements.active.containsKey('premium');
  }

  static String getTierFromCustomerInfo(CustomerInfo? customerInfo) {
    if (customerInfo == null) {
      _log('RevenueCat: customerInfo is null');
      return SubscriptionTierHelper.free;
    }

    final activeEntitlements = customerInfo.entitlements.active;
    _log('RevenueCat: Active entitlements count: ${activeEntitlements.length}');

    if (activeEntitlements.isEmpty) {
      _log('RevenueCat: No active entitlements');
      final activeSubscriptionTier = SubscriptionTierHelper.tierFromProductIds(
        customerInfo.activeSubscriptions,
      );
      if (activeSubscriptionTier != SubscriptionTierHelper.free) {
        _log(
          'RevenueCat: Detected tier from activeSubscriptions: $activeSubscriptionTier',
        );
        return activeSubscriptionTier;
      }

      return SubscriptionTierHelper.free;
    }

    for (final entitlement in activeEntitlements.values) {
      final tier = SubscriptionTierHelper.tierFromProductId(
        entitlement.productIdentifier,
      );
      if (tier != SubscriptionTierHelper.free) {
        _log('RevenueCat: Detected tier: $tier');
        return tier;
      }
    }

    _log('RevenueCat: No matching tier found, returning free');
    return SubscriptionTierHelper.free;
  }
}
