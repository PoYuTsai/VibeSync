// lib/main.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';
import 'app/routes.dart';
import 'core/config/environment.dart';
import 'core/services/storage_service.dart';
import 'core/services/revenuecat_service.dart';
import 'core/services/supabase_service.dart';
import 'features/follow_up_notification/data/local_notification_gateway.dart';
import 'features/follow_up_notification/data/providers/follow_up_notification_service.dart';
import 'features/onboarding/data/onboarding_service.dart';

void main() async {
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

  // Initialize RevenueCat (iOS/Android only)
  await RevenueCatService.initialize(
    appUserId: SupabaseService.currentUser?.id,
  );

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
