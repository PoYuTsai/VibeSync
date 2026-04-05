import 'package:flutter/foundation.dart';

/// Runtime environment for the app.
enum Environment { dev, staging, prod }

/// Centralized runtime configuration.
///
/// Notes:
/// - `dev` and `staging` currently point at the same Supabase project.
/// - production-only values can be overridden via `--dart-define`.
/// - RevenueCat keys must come from build-time environment variables.
class AppConfig {
  static const _envKey = 'ENV';

  static Environment get environment {
    const env = String.fromEnvironment(_envKey, defaultValue: 'dev');
    return Environment.values.firstWhere(
      (value) => value.name == env,
      orElse: () => Environment.dev,
    );
  }

  static bool get isProduction => environment == Environment.prod;
  static bool get isDevelopment => environment == Environment.dev;
  static bool get isStaging => environment == Environment.staging;

  static String get supabaseUrl {
    switch (environment) {
      case Environment.dev:
      case Environment.staging:
        return 'https://fcmwrmwdoqiqdnbisdpg.supabase.co';
      case Environment.prod:
        return const String.fromEnvironment(
          'SUPABASE_PROD_URL',
          defaultValue: 'https://fcmwrmwdoqiqdnbisdpg.supabase.co',
        );
    }
  }

  static String get supabaseAnonKey {
    const defaultAnonKey =
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZjbXdybXdkb3FpcWRuYmlzZHBnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzIyMDUzMjUsImV4cCI6MjA4Nzc4MTMyNX0.xqorAcT0NUTNxzktd-SgI3ePG8jJdeqCRU730Brzmlg';

    switch (environment) {
      case Environment.dev:
      case Environment.staging:
        return defaultAnonKey;
      case Environment.prod:
        return const String.fromEnvironment(
          'SUPABASE_PROD_ANON_KEY',
          defaultValue: defaultAnonKey,
        );
    }
  }

  /// RevenueCat key selection:
  /// - dev / staging: sandbox key
  /// - prod: production key
  ///
  /// No repo-side fallback is allowed.
  static String get revenueCatApiKey {
    switch (environment) {
      case Environment.dev:
      case Environment.staging:
        return const String.fromEnvironment(
          'REVENUECAT_SANDBOX_KEY',
          defaultValue: '',
        );
      case Environment.prod:
        return const String.fromEnvironment(
          'REVENUECAT_PROD_KEY',
          defaultValue: '',
        );
    }
  }

  static const String _nativeAuthRedirectUri =
      'com.poyutsai.vibesync://login-callback';

  static String get authRedirectUri {
    if (kIsWeb) {
      return Uri.base
          .replace(
            path: '/login',
            queryParameters: null,
            fragment: null,
          )
          .toString();
    }

    return _nativeAuthRedirectUri;
  }

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

  static bool get debugEnabled => !isProduction;
  static bool get showEnvironmentBadge => !isProduction;
}
