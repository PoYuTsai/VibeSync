// lib/core/config/environment.dart

import 'package:flutter/foundation.dart';

/// 應用程式執行環境
enum Environment { dev, staging, prod }

/// The only Email callback provenance paths accepted by the native app.
///
/// This path chooses the retry copy/operation only; Supabase's accepted
/// auth event remains the authority for session and password-recovery state.
enum EmailAuthFlow { signup, recovery }

extension EmailAuthFlowValue on EmailAuthFlow {
  String get path {
    switch (this) {
      case EmailAuthFlow.signup:
        return 'signup';
      case EmailAuthFlow.recovery:
        return 'recovery';
    }
  }
}

/// 環境配置
///
/// 根據編譯時定義的 ENV 環境變數決定配置:
/// - dev: 本地開發 (localhost Supabase)
/// - staging: 測試 UI flags；目前仍連 production Supabase
/// - prod: 正式環境 (production Supabase)
///
/// 使用方式:
/// ```bash
/// # Development (default)
/// flutter run
///
/// # Staging
/// flutter run --dart-define=ENV=staging
///
/// # Production
/// flutter run --dart-define=ENV=prod
/// ```
class AppConfig {
  static const _envKey = 'ENV';
  static const gitSha = String.fromEnvironment(
    'GIT_SHA',
    defaultValue: 'unknown',
  );

  static String get gitShaShort {
    if (gitSha.length <= 7) return gitSha;
    return gitSha.substring(0, 7);
  }

  /// 當前環境
  static Environment get environment {
    const env = String.fromEnvironment(_envKey, defaultValue: 'dev');
    return Environment.values.firstWhere(
      (e) => e.name == env,
      orElse: () => Environment.dev,
    );
  }

  /// 是否為正式環境
  static bool get isProduction => environment == Environment.prod;

  /// 是否為開發環境
  static bool get isDevelopment => environment == Environment.dev;

  /// 是否為測試環境
  static bool get isStaging => environment == Environment.staging;

  /// Supabase URL
  static String get supabaseUrl {
    switch (environment) {
      case Environment.dev:
        // Dev 也使用遠端 Supabase (方便測試)
        return 'https://fcmwrmwdoqiqdnbisdpg.supabase.co';
      case Environment.staging:
        // There is no isolated staging Supabase project today.
        return 'https://fcmwrmwdoqiqdnbisdpg.supabase.co';
      case Environment.prod:
        return const String.fromEnvironment(
          'SUPABASE_PROD_URL',
          defaultValue: 'https://fcmwrmwdoqiqdnbisdpg.supabase.co',
        );
    }
  }

  /// Supabase Anonymous Key
  static String get supabaseAnonKey {
    switch (environment) {
      case Environment.dev:
        // Dev 也使用遠端 Supabase anon key
        return 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZjbXdybXdkb3FpcWRuYmlzZHBnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzIyMDUzMjUsImV4cCI6MjA4Nzc4MTMyNX0.xqorAcT0NUTNxzktd-SgI3ePG8jJdeqCRU730Brzmlg';
      case Environment.staging:
        // Matches the production project URL above.
        return 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZjbXdybXdkb3FpcWRuYmlzZHBnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzIyMDUzMjUsImV4cCI6MjA4Nzc4MTMyNX0.xqorAcT0NUTNxzktd-SgI3ePG8jJdeqCRU730Brzmlg';
      case Environment.prod:
        return const String.fromEnvironment(
          'SUPABASE_PROD_ANON_KEY',
          defaultValue:
              'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZjbXdybXdkb3FpcWRuYmlzZHBnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzIyMDUzMjUsImV4cCI6MjA4Nzc4MTMyNX0.xqorAcT0NUTNxzktd-SgI3ePG8jJdeqCRU730Brzmlg',
        );
    }
  }

  /// RevenueCat API Key (iOS).
  ///
  /// The build must explicitly inject this public SDK key.  There is no
  /// checked-in fallback: a missing or wrongly-prefixed value disables the
  /// RevenueCat client instead of silently selecting another environment.
  static const _revenueCatApiKey = String.fromEnvironment(
    'REVENUECAT_API_KEY',
  );
  static const _revenueCatSandboxKey = String.fromEnvironment(
    'REVENUECAT_SANDBOX_KEY',
  );
  static const _revenueCatProdKey = String.fromEnvironment(
    'REVENUECAT_PROD_KEY',
  );
  // Android has its own public SDK key namespace.  Do not fall back to any
  // generic or iOS key here: an absent Android key intentionally disables the
  // RevenueCat client until the Android Console setup is ready.
  static const _revenueCatAndroidPublicSdkKey = String.fromEnvironment(
    'REVENUECAT_ANDROID_API_KEY',
  );

  static bool _isRevenueCatPublicSdkKey(String key) {
    final trimmed = key.trim();
    return trimmed.startsWith('appl_') && trimmed.length > 'appl_'.length;
  }

  static String? selectRevenueCatPublicSdkKey({
    required bool isProduction,
    required String revenueCatApiKey,
    required String revenueCatSandboxKey,
    required String revenueCatProdKey,
  }) {
    final candidates = [
      if (isProduction) revenueCatProdKey,
      if (!isProduction) revenueCatSandboxKey,
      revenueCatApiKey,
    ];

    for (final candidate in candidates) {
      final trimmed = candidate.trim();
      if (_isRevenueCatPublicSdkKey(trimmed)) {
        return trimmed;
      }
    }

    return null;
  }

  static String? get revenueCatApiKey {
    return selectRevenueCatPublicSdkKey(
      isProduction: isProduction,
      revenueCatApiKey: _revenueCatApiKey,
      revenueCatSandboxKey: _revenueCatSandboxKey,
      revenueCatProdKey: _revenueCatProdKey,
    );
  }

  /// Android RevenueCat public SDK key.
  ///
  /// This getter is nullable by design.  Android must not inherit the iOS
  /// `appl_` key, the generic `REVENUECAT_PROD_KEY`, or a server secret while
  /// the Play/RevenueCat setup is incomplete.
  static String? get revenueCatAndroidPublicSdkKey {
    return selectRevenueCatPublicSdkKeyForPlatform(
      isAndroid: true,
      androidPublicSdkKey: _revenueCatAndroidPublicSdkKey,
      isProduction: isProduction,
      revenueCatApiKey: _revenueCatApiKey,
      revenueCatSandboxKey: _revenueCatSandboxKey,
      revenueCatProdKey: _revenueCatProdKey,
    );
  }

  static String? selectRevenueCatPublicSdkKeyForPlatform({
    required bool isAndroid,
    String androidPublicSdkKey = '',
    required bool isProduction,
    required String revenueCatApiKey,
    required String revenueCatSandboxKey,
    required String revenueCatProdKey,
  }) {
    if (isAndroid) {
      final trimmed = androidPublicSdkKey.trim();
      return trimmed.startsWith('goog_') && trimmed.length > 'goog_'.length
          ? trimmed
          : null;
    }

    return selectRevenueCatPublicSdkKey(
      isProduction: isProduction,
      revenueCatApiKey: revenueCatApiKey,
      revenueCatSandboxKey: revenueCatSandboxKey,
      revenueCatProdKey: revenueCatProdKey,
    );
  }

  static const String _nativeAuthRedirectUri =
      'com.poyutsai.vibesync://login-callback';
  static const String _nativeEmailAuthRedirectUri =
      'com.poyutsai.vibesync://email-callback';

  static String get authRedirectUri {
    if (kIsWeb) {
      return _bareWebLoginRedirectUri(Uri.base);
    }

    return _nativeAuthRedirectUri;
  }

  /// Independent native callback shared by signup confirmation, resend, and
  /// password recovery. Keeping Email off the OAuth host prevents
  /// flutter_web_auth_2's CallbackActivity from consuming an Email link on
  /// Android. iOS still receives the same scheme through app_links; its
  /// Google and native Apple flows continue to use [authRedirectUri].
  static String get authEmailRedirectUri {
    if (kIsWeb) {
      return _bareWebLoginRedirectUri(Uri.base);
    }

    return _nativeEmailAuthRedirectUri;
  }

  /// Signup confirmation and resend callbacks use one fixed provenance path.
  static String get authEmailSignupRedirectUri =>
      emailAuthRedirectUriFor(flow: EmailAuthFlow.signup, isWeb: kIsWeb);

  /// Password recovery callbacks use a distinct fixed provenance path.
  static String get authEmailRecoveryRedirectUri =>
      emailAuthRedirectUriFor(flow: EmailAuthFlow.recovery, isWeb: kIsWeb);

  /// Builds the callback for one runtime platform.
  ///
  /// Web intentionally keeps the existing bare `/login` callback for all
  /// Email operations. Native callbacks use exact paths so Supabase's glob
  /// redirect matching cannot reinterpret a query marker as a wildcard.
  @visibleForTesting
  static String emailAuthRedirectUriFor({
    required EmailAuthFlow flow,
    required bool isWeb,
    Uri? webBaseUri,
  }) {
    if (isWeb) {
      final base = webBaseUri ?? Uri.base;
      return _bareWebLoginRedirectUri(base);
    }

    return Uri.parse(_nativeEmailAuthRedirectUri)
        .replace(path: '/${flow.path}')
        .toString();
  }

  static String _bareWebLoginRedirectUri(Uri base) {
    return Uri(
      scheme: base.scheme,
      userInfo: base.userInfo,
      host: base.host,
      port: base.port,
      path: '/login',
    ).toString();
  }

  /// 顯示環境名稱
  static String get environmentName {
    switch (environment) {
      case Environment.dev:
        return 'Development';
      case Environment.staging:
        return 'Staging';
      case Environment.prod:
        return 'Production';
    }
  }

  /// 是否啟用 debug 功能
  static bool get debugEnabled => !isProduction;

  /// 是否顯示環境標籤 (dev/staging 時顯示)
  static bool get showEnvironmentBadge => !isProduction;
}
