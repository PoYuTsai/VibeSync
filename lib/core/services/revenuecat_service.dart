// lib/core/services/revenuecat_service.dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../config/environment.dart';

/// RevenueCat 服務封裝
class RevenueCatService {
  static bool _isInitialized = false;

  /// 初始化 RevenueCat SDK
  /// 應在 main.dart 中 Supabase 初始化後呼叫
  static Future<void> initialize() async {
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

    PurchasesConfiguration configuration;
    if (Platform.isIOS) {
      configuration = PurchasesConfiguration(apiKey);
    } else if (Platform.isAndroid) {
      // Android 暫不支援，之後再加
      debugPrint('RevenueCat: Android not yet configured');
      return;
    } else {
      debugPrint('RevenueCat: Unsupported platform');
      return;
    }

    await Purchases.configure(configuration);
    _isInitialized = true;
    debugPrint('RevenueCat initialized');
  }

  /// 檢查是否已初始化
  static bool get isInitialized => _isInitialized;

  /// 關聯用戶 ID（登入後呼叫）
  /// 這讓 RevenueCat 知道訂閱屬於哪個 Supabase 用戶
  static Future<void> login(String userId) async {
    if (!_isInitialized) return;

    try {
      await Purchases.logIn(userId);
      debugPrint('RevenueCat: User logged in: $userId');
    } catch (e) {
      debugPrint('RevenueCat login error: $e');
    }
  }

  /// 登出（Supabase 登出時呼叫）
  static Future<void> logout() async {
    if (!_isInitialized) return;

    try {
      await Purchases.logOut();
      debugPrint('RevenueCat: User logged out');
    } catch (e) {
      debugPrint('RevenueCat logout error: $e');
    }
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
  static Future<bool> hasPremiumEntitlement() async {
    final customerInfo = await getCustomerInfo();
    if (customerInfo == null) return false;

    return customerInfo.entitlements.active.containsKey('premium');
  }

  /// 從 CustomerInfo 取得 tier
  static String getTierFromCustomerInfo(CustomerInfo? customerInfo) {
    if (customerInfo == null) return 'free';

    final premiumEntitlement = customerInfo.entitlements.active['premium'];
    if (premiumEntitlement == null) return 'free';

    final productId = premiumEntitlement.productIdentifier;
    if (productId.contains('essential')) return 'essential';
    if (productId.contains('starter')) return 'starter';

    return 'free';
  }
}
