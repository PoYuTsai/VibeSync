// lib/core/services/revenuecat_service.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../config/environment.dart';
import '../../features/subscription/domain/services/subscription_tier_helper.dart';
import '../utils/platform_info.dart';

/// RevenueCat 服務封裝
class RevenueCatService {
  static bool _isInitialized = false;
  @visibleForTesting
  static bool? debugIsIOSPlatformOverride;

  static const MethodChannel _subscriptionManagementChannel = MethodChannel(
    'vibesync/subscription_management',
  );

  /// 初始化 RevenueCat SDK
  /// 應在 main.dart 中 Supabase 初始化後呼叫
  static Future<void> initialize({String? appUserId}) async {
    if (_isInitialized) return;

    // Web 不支援 RevenueCat
    if (kIsWeb) {
      debugPrint('RevenueCat: Web platform not supported');
      return;
    }

    final apiKey = AppConfig.revenueCatApiKey;
    if (apiKey.isEmpty) {
      debugPrint('RevenueCat: API key not configured');
      return;
    }

    await Purchases.setLogLevel(LogLevel.debug);

    final cleanedAppUserId = appUserId?.trim();
    PurchasesConfiguration configuration;
    final isIOS = debugIsIOSPlatformOverride ?? isIOSPlatform;
    if (isIOS) {
      configuration = PurchasesConfiguration(apiKey);
    } else if (isAndroidPlatform) {
      // Android 暫不支援，之後再加
      debugPrint('RevenueCat: Android not yet configured');
      return;
    } else {
      debugPrint('RevenueCat: Unsupported platform');
      return;
    }

    if (cleanedAppUserId != null && cleanedAppUserId.isNotEmpty) {
      configuration.appUserID = cleanedAppUserId;
    }

    await Purchases.configure(configuration);
    _isInitialized = true;
    debugPrint(
      cleanedAppUserId == null || cleanedAppUserId.isEmpty
          ? 'RevenueCat initialized'
          : 'RevenueCat initialized with custom app user id',
    );
  }

  /// 檢查是否已初始化
  static bool get isInitialized => _isInitialized;

  @visibleForTesting
  static void debugResetForTesting() {
    _isInitialized = false;
    debugIsIOSPlatformOverride = null;
  }

  /// 關聯用戶 ID（登入後呼叫）
  /// 這讓 RevenueCat 知道訂閱屬於哪個 Supabase 用戶
  static Future<CustomerInfo?> login(String userId) async {
    if (!_isInitialized) return null;

    try {
      final result = await Purchases.logIn(userId);
      debugPrint('RevenueCat: User logged in: $userId');
      return result.customerInfo;
    } catch (e) {
      debugPrint('RevenueCat login error: $e');
      return null;
    }
  }

  /// 登出（Supabase 登出時呼叫）
  static Future<void> logout() async {
    if (!_isInitialized) return;
    debugPrint(
        'RevenueCat: SDK logout skipped to preserve custom user identity');
  }

  /// 取得可購買的產品
  static Future<Offerings?> getOfferings() async {
    if (!_isInitialized) return null;

    try {
      final offerings = await Purchases.getOfferings();
      return offerings;
    } catch (e) {
      debugPrint('RevenueCat getOfferings error: $e');
      return null;
    }
  }

  /// Fetches App Store subscription products directly by product id.
  /// This is a safety net when RevenueCat Offerings are temporarily empty or
  /// misconfigured, so the paywall can still show prices and start purchase.
  static Future<List<StoreProduct>> getSubscriptionProducts(
    List<String> productIds,
  ) async {
    if (!_isInitialized) return const [];

    try {
      return Purchases.getProducts(
        productIds,
        productCategory: ProductCategory.subscription,
      );
    } catch (e) {
      debugPrint('RevenueCat getProducts error: $e');
      return const [];
    }
  }

  /// 購買訂閱
  /// 回傳 CustomerInfo，購買失敗會拋出例外
  static Future<CustomerInfo> purchase(Package package) async {
    if (!_isInitialized) {
      throw Exception('RevenueCat not initialized');
    }

    try {
      final result = await Purchases.purchase(PurchaseParams.package(package));
      debugPrint('RevenueCat: Purchase successful');
      return result.customerInfo;
    } catch (e) {
      debugPrint('RevenueCat purchase error: $e');
      rethrow;
    }
  }

  /// Purchases a store product directly when no RevenueCat Package is present.
  static Future<CustomerInfo> purchaseStoreProduct(StoreProduct product) async {
    if (!_isInitialized) {
      throw Exception('RevenueCat not initialized');
    }

    try {
      final result =
          await Purchases.purchase(PurchaseParams.storeProduct(product));
      debugPrint('RevenueCat: Store product purchase successful');
      return result.customerInfo;
    } catch (e) {
      debugPrint('RevenueCat store product purchase error: $e');
      rethrow;
    }
  }

  /// 恢復購買
  static Future<CustomerInfo> restorePurchases() async {
    if (!_isInitialized) {
      throw Exception('RevenueCat not initialized');
    }

    try {
      final customerInfo = await Purchases.restorePurchases();
      debugPrint('RevenueCat: Purchases restored');
      return customerInfo;
    } catch (e) {
      debugPrint('RevenueCat restore error: $e');
      rethrow;
    }
  }

  /// 取得目前訂閱狀態
  static Future<CustomerInfo?> getCustomerInfo() async {
    if (!_isInitialized) return null;

    try {
      final customerInfo = await Purchases.getCustomerInfo();
      return customerInfo;
    } catch (e) {
      debugPrint('RevenueCat getCustomerInfo error: $e');
      return null;
    }
  }

  /// 檢查用戶是否有 premium entitlement
  /// Refreshes RevenueCat from the local App Store receipt without presenting
  /// the user-facing restore flow. This rescues updates where VibeSync's local
  /// cache was already overwritten as Free but the device still has an active
  /// subscription receipt.
  static Future<String?> getCurrentAppUserId() async {
    if (!_isInitialized) return null;

    try {
      return Purchases.appUserID;
    } catch (e) {
      debugPrint('RevenueCat getAppUserID error: $e');
      return null;
    }
  }

  static Future<bool> _matchesExpectedAppUserId(
    String? expectedAppUserId,
  ) async {
    final cleanedExpectedAppUserId = expectedAppUserId?.trim();
    if (cleanedExpectedAppUserId == null || cleanedExpectedAppUserId.isEmpty) {
      return true;
    }

    final currentAppUserId = (await getCurrentAppUserId())?.trim();
    if (currentAppUserId == cleanedExpectedAppUserId) {
      return true;
    }

    debugPrint(
      'RevenueCat identity mismatch: expected=$cleanedExpectedAppUserId current=${currentAppUserId ?? 'null'}',
    );
    return false;
  }

  static Future<CustomerInfo?> getCustomerInfoForAppUserId(
    String expectedAppUserId,
  ) async {
    if (!_isInitialized) return null;
    if (!await _matchesExpectedAppUserId(expectedAppUserId)) {
      return null;
    }
    return getCustomerInfo();
  }

  static Future<bool?> getIsAnonymous() async {
    if (!_isInitialized) return null;

    try {
      return Purchases.isAnonymous;
    } catch (e) {
      debugPrint('RevenueCat isAnonymous error: $e');
      return null;
    }
  }

  static Map<String, Object?> customerInfoDebugSummary(
    CustomerInfo? customerInfo,
  ) {
    if (customerInfo == null) {
      return const {'available': false};
    }

    final activeEntitlements = customerInfo.entitlements.active;
    return {
      'available': true,
      'tier': getTierFromCustomerInfo(customerInfo),
      'originalAppUserId': customerInfo.originalAppUserId,
      'activeSubscriptions': customerInfo.activeSubscriptions,
      'allPurchasedProductIdentifiers':
          customerInfo.allPurchasedProductIdentifiers,
      'activeEntitlements': activeEntitlements.keys.toList(growable: false),
      'activeEntitlementProducts': {
        for (final entry in activeEntitlements.entries)
          entry.key: entry.value.productIdentifier,
      },
      'latestExpirationDate': customerInfo.latestExpirationDate,
      'allExpirationDates': customerInfo.allExpirationDates,
      'managementUrlPresent': customerInfo.managementURL != null,
    };
  }

  static Future<Map<String, Object?>> buildDebugSnapshot() async {
    final currentAppUserId = await getCurrentAppUserId();
    final isAnonymous = await getIsAnonymous();
    final customerInfo = await getCustomerInfo();

    return {
      'initialized': _isInitialized,
      'currentAppUserId': currentAppUserId,
      'isAnonymous': isAnonymous,
      'customerInfo': customerInfoDebugSummary(customerInfo),
    };
  }

  static Future<CustomerInfo?> syncPurchasesAndRefreshCustomerInfo({
    String? expectedAppUserId,
  }) async {
    if (!_isInitialized) return null;
    if (!await _matchesExpectedAppUserId(expectedAppUserId)) {
      return null;
    }

    try {
      await Purchases.invalidateCustomerInfoCache();
      var customerInfo = await Purchases.getCustomerInfo();
      if (getTierFromCustomerInfo(customerInfo) !=
          SubscriptionTierHelper.free) {
        return customerInfo;
      }

      await Purchases.syncPurchases();
      await Purchases.invalidateCustomerInfoCache();
      if (!await _matchesExpectedAppUserId(expectedAppUserId)) {
        return null;
      }
      customerInfo = await Purchases.getCustomerInfo();
      debugPrint('RevenueCat: Purchases synced for startup entitlement rescue');
      return customerInfo;
    } catch (e) {
      debugPrint('RevenueCat startup entitlement rescue error: $e');
      return null;
    }
  }

  static Future<bool> hasPremiumEntitlement() async {
    final customerInfo = await getCustomerInfo();
    if (customerInfo == null) return false;

    return customerInfo.entitlements.active.containsKey('premium');
  }

  /// 從 CustomerInfo 取得 tier
  /// 檢查所有 active entitlements，不限定名稱
  static String getTierFromCustomerInfo(CustomerInfo? customerInfo) {
    if (customerInfo == null) {
      debugPrint('RevenueCat: customerInfo is null');
      return SubscriptionTierHelper.free;
    }

    // 印出所有 entitlements（包括 inactive）
    debugPrint(
        'RevenueCat: All entitlements: ${customerInfo.entitlements.all.keys.toList()}');

    final activeEntitlements = customerInfo.entitlements.active;
    debugPrint(
        'RevenueCat: Active entitlements count: ${activeEntitlements.length}');
    debugPrint(
        'RevenueCat: Active entitlements keys: ${activeEntitlements.keys.toList()}');

    final activeProductIds = <String>{
      for (final entitlement in activeEntitlements.values)
        if (entitlement.productIdentifier.isNotEmpty)
          entitlement.productIdentifier,
      ...customerInfo.activeSubscriptions.where((id) => id.isNotEmpty),
    }.toList(growable: false);

    // 如果沒有 active entitlements，印出更多資訊
    if (activeEntitlements.isEmpty) {
      debugPrint('RevenueCat: No active entitlements!');
      debugPrint(
          'RevenueCat: Active subscriptions: ${customerInfo.activeSubscriptions}');
      debugPrint(
          'RevenueCat: All purchased product IDs: ${customerInfo.allPurchasedProductIdentifiers}');

      // 直接從 activeSubscriptions 判斷
      for (final productId in customerInfo.activeSubscriptions) {
        debugPrint('RevenueCat: Checking activeSubscription: $productId');
      }
      final activeSubscriptionTier =
          SubscriptionTierHelper.tierFromProductIds(activeProductIds);
      if (activeSubscriptionTier != SubscriptionTierHelper.free) {
        debugPrint(
          'RevenueCat: Detected tier from activeSubscriptions: $activeSubscriptionTier',
        );
        return activeSubscriptionTier;
      }

      return SubscriptionTierHelper.free;
    }

    // 檢查所有 active entitlements
    for (final entry in activeEntitlements.entries) {
      final entitlementId = entry.key;
      final entitlement = entry.value;
      final productId = entitlement.productIdentifier;

      debugPrint(
          'RevenueCat: Entitlement "$entitlementId" -> Product "$productId"');
    }

    final tier = SubscriptionTierHelper.tierFromProductIds(activeProductIds);
    if (tier != SubscriptionTierHelper.free) {
      debugPrint('RevenueCat: Detected highest active tier: $tier');
      return tier;
    }

    debugPrint('RevenueCat: No matching tier found, returning free');
    return SubscriptionTierHelper.free;
  }

  /// Returns the best active product identifier for the current subscriber.
  /// When multiple products are present during App Store transitions, prefer
  /// the highest tier so the UI can distinguish monthly vs quarterly plans.
  static String? getActiveProductIdFromCustomerInfo(
      CustomerInfo? customerInfo) {
    if (customerInfo == null) return null;

    final productIds = <String>{
      for (final entitlement in customerInfo.entitlements.active.values)
        if (entitlement.productIdentifier.isNotEmpty)
          entitlement.productIdentifier,
      ...customerInfo.activeSubscriptions.where((id) => id.isNotEmpty),
    }.toList();

    if (productIds.isEmpty) return null;

    productIds.sort((a, b) {
      final aRank = SubscriptionTierHelper.rankOf(
          SubscriptionTierHelper.tierFromProductId(a));
      final bRank = SubscriptionTierHelper.rankOf(
          SubscriptionTierHelper.tierFromProductId(b));
      return bRank.compareTo(aRank);
    });

    return productIds.first;
  }

  /// RevenueCat may keep the original subscriber under an anonymous appUserId
  /// after reinstall / restore. Send it to the server so sync can verify both
  /// identities instead of accidentally treating a paid user as free.
  static String? getRevenueCatAppUserId(CustomerInfo? customerInfo) {
    final trimmed = customerInfo?.originalAppUserId.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  /// Returns the best-known premium expiration date from RevenueCat.
  /// Useful for scheduled downgrades that should only take effect on renewal.
  static DateTime? getPremiumExpirationDate(CustomerInfo? customerInfo) {
    if (customerInfo == null) {
      return null;
    }

    DateTime? parseDate(String? value) {
      if (value == null || value.isEmpty) {
        return null;
      }
      return DateTime.tryParse(value);
    }

    final latest = parseDate(customerInfo.latestExpirationDate);
    if (latest != null) {
      return latest;
    }

    DateTime? best;

    for (final entitlement in customerInfo.entitlements.active.values) {
      final expiration = parseDate(entitlement.expirationDate);
      if (expiration == null) {
        continue;
      }
      if (best == null || expiration.isAfter(best)) {
        best = expiration;
      }
    }

    if (best != null) {
      return best;
    }

    for (final raw in customerInfo.allExpirationDates.values) {
      final expiration = parseDate(raw);
      if (expiration == null) {
        continue;
      }
      if (best == null || expiration.isAfter(best)) {
        best = expiration;
      }
    }

    return best;
  }

  /// Returns the store-native subscription management URL when available.
  static Future<String?> getManagementUrl() async {
    final customerInfo = await getCustomerInfo();
    return customerInfo?.managementURL;
  }

  /// Opens the platform-native subscription management UI when supported.
  static Future<bool> showNativeManageSubscriptions() async {
    if (kIsWeb || !isIOSPlatform) {
      return false;
    }

    try {
      final didOpen = await _subscriptionManagementChannel.invokeMethod<bool>(
        'showManageSubscriptions',
      );
      return didOpen ?? false;
    } on PlatformException catch (error) {
      debugPrint('RevenueCat showManageSubscriptions error: $error');
      return false;
    } catch (error) {
      debugPrint('RevenueCat showManageSubscriptions unexpected error: $error');
      return false;
    }
  }

  /// Estimates the next renewal date from an ISO 8601 subscription period.
  /// Example values include P1W, P1M, P3M and P1Y.
  static DateTime? estimateRenewalDateFromPeriod(
    String? subscriptionPeriod, {
    DateTime? from,
  }) {
    if (subscriptionPeriod == null || subscriptionPeriod.isEmpty) {
      return null;
    }

    final match = RegExp(r'^P(?:(\d+)W|(\d+)M|(\d+)Y|(\d+)D)$').firstMatch(
      subscriptionPeriod,
    );
    if (match == null) {
      return null;
    }

    final base = (from ?? DateTime.now()).toUtc();

    int? parseGroup(int index) {
      final raw = match.group(index);
      if (raw == null || raw.isEmpty) {
        return null;
      }
      return int.tryParse(raw);
    }

    final weeks = parseGroup(1);
    if (weeks != null) {
      return base.add(Duration(days: weeks * 7));
    }

    final months = parseGroup(2);
    if (months != null) {
      return DateTime.utc(
        base.year,
        base.month + months,
        base.day,
        base.hour,
        base.minute,
        base.second,
        base.millisecond,
        base.microsecond,
      );
    }

    final years = parseGroup(3);
    if (years != null) {
      return DateTime.utc(
        base.year + years,
        base.month,
        base.day,
        base.hour,
        base.minute,
        base.second,
        base.millisecond,
        base.microsecond,
      );
    }

    final days = parseGroup(4);
    if (days != null) {
      return base.add(Duration(days: days));
    }

    return null;
  }
}
