// lib/core/config/environment.dart

/// 應用程式執行環境
enum Environment { dev, staging, prod }

/// 環境配置
///
/// 根據編譯時定義的 ENV 環境變數決定配置:
/// - dev: 本地開發 (localhost Supabase)
/// - staging: 測試環境 (staging Supabase)
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
        return 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZjbXdybXdkb3FpcWRuYmlzZHBnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzIyMDUzMjUsImV4cCI6MjA4Nzc4MTMyNX0.xqorAcT0NUTNxzktd-SgI3ePG8jJdeqCRU730Brzmlg';
      case Environment.prod:
        return const String.fromEnvironment(
          'SUPABASE_PROD_ANON_KEY',
          defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZjbXdybXdkb3FpcWRuYmlzZHBnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzIyMDUzMjUsImV4cCI6MjA4Nzc4MTMyNX0.xqorAcT0NUTNxzktd-SgI3ePG8jJdeqCRU730Brzmlg',
        );
    }
  }

  /// RevenueCat API Key (Sandbox vs Production)
  static String get revenueCatApiKey {
    return isProduction
        ? const String.fromEnvironment('REVENUECAT_PROD_KEY')
        : const String.fromEnvironment('REVENUECAT_SANDBOX_KEY');
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
