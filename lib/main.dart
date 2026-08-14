// lib/main.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';
import 'app/routes.dart';
import 'core/config/environment.dart';
import 'core/observability/crash_reporting.dart';
import 'core/services/account_deletion_cleanup.dart';
import 'core/services/storage_service.dart';
import 'core/services/revenuecat_service.dart';
import 'core/services/keyboard_token_bridge.dart';
import 'core/services/supabase_service.dart';
import 'features/follow_up_notification/data/local_notification_gateway.dart';
import 'features/follow_up_notification/data/providers/follow_up_notification_service.dart';
import 'features/onboarding/data/onboarding_service.dart';

Future<void> main() => CrashReporting.run(_bootstrapApp);

Future<void> _bootstrapApp() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Log environment info
  if (kDebugMode) {
    debugPrint('🚀 Running in ${AppConfig.environmentName} mode');
    debugPrint('📡 Supabase URL: ${AppConfig.supabaseUrl}');
  }

  // Initialize local storage
  await StorageService.initialize();

  // Initialize Supabase using environment config
  await SupabaseService.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );

  // iOS keyboard extension receives access-token metadata through the shared
  // App Group keychain. No refresh token is ever exposed to the extension.
  await KeyboardTokenBridge.initializeDefault();

  // Initialize RevenueCat (iOS/Android only)
  await RevenueCatService.initialize(
    appUserId: SupabaseService.currentUser?.id,
  );

  // 刪帳號的本機清理若被強殺（稽核 #7）：在任何人進入 App 前補完，
  // 前用戶資料不得躺在裝置上等下一個帳號。失敗保留 marker 下次啟動
  // 再試，不擋啟動——遠端 session 已失效，資料要另一個帳號登入才可能
  // 觸及，風險窗有限。
  try {
    await AccountDeletionCleanup.replayIfNeeded();
  } catch (error) {
    debugPrint('Account deletion cleanup replay failed: $error');
  }

  // Prime onboarding completion into memory before the router evaluates
  // redirects, so a returning user is never misrouted back to onboarding.
  await OnboardingService.load();

  // 48h 跟進提醒本地通知：init plugin，前景/背景點擊時 push 到跟進頁。
  // 冷啟動（app 被通知從終止態喚醒）由 App initState 讀 launchPayload 處理。
  final followUpGateway = LocalNotificationGateway(
    onDidTap: (payload) => router.push(followUpDeepLink(payload)),
  );
  await followUpGateway.init();

  runApp(
    ProviderScope(
      overrides: [
        notificationGatewayProvider.overrideWithValue(followUpGateway),
      ],
      child: const App(),
    ),
  );
}
