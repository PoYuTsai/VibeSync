// lib/app/app.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_theme.dart';
import '../core/services/funnel_tracker.dart';
import '../core/services/keyboard_token_bridge.dart';
import '../core/services/supabase_service.dart';
import '../features/analysis_history/data/providers/analysis_history_providers.dart';
import '../features/analysis_history/domain/entities/analysis_history_event.dart';
import '../features/follow_up_notification/data/providers/follow_up_notification_service.dart';
import '../features/splash/presentation/screens/splash_screen.dart';
import 'keyboard_onboarding_scheduler.dart';
import 'routes.dart';

class App extends ConsumerStatefulWidget {
  const App({super.key});

  /// 測試替身：鍵盤轉來的額度訊號（null＝照常讀 KeyboardTokenBridge）。
  @visibleForTesting
  static Future<bool> Function()? debugKeyboardQuotaSignalOverride;

  @override
  ConsumerState<App> createState() => _AppState();
}

class _AppState extends ConsumerState<App> with WidgetsBindingObserver {
  bool _splashComplete = false;
  bool _openPaywallAfterSplash = false;
  late final KeyboardOnboardingScheduler _keyboardOnboardingScheduler;
  StreamSubscription<dynamic>? _authSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _keyboardOnboardingScheduler = KeyboardOnboardingScheduler(
      router: router,
      isAuthenticated: () => SupabaseService.isAuthenticated,
      isSplashComplete: () => _splashComplete,
      trackShown: () => unawaited(
        ref.read(funnelTrackerProvider).track('keyboard_setup_shown'),
      ),
      // 鍵盤教學等成功分析滿 2 次才跳（onboarding 轉換第 13 步）。本機分析
      // 紀錄以裝置為單位、上限 500 筆，判斷 ≥2 足夠。
      successfulAnalysisCount: () => ref
          .read(analysisHistoryRepositoryProvider)
          .listByKind(AnalysisHistoryKind.analyze)
          .length,
    )..attach();
    unawaited(_keyboardOnboardingScheduler.primeFullAccessResume());
    _authSubscription = SupabaseService.authStateChanges.listen((_) {
      _keyboardOnboardingScheduler.maybeSchedule();
    });
    _handleColdStartNotification();
    _handleKeyboardQuotaSignal();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _keyboardOnboardingScheduler.detach();
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _handleKeyboardQuotaSignal();
    }
  }

  Future<void> _handleKeyboardQuotaSignal() async {
    await KeyboardTokenBridge.syncOnForeground();
    final shouldOpenPaywall =
        await (App.debugKeyboardQuotaSignalOverride?.call() ??
            KeyboardTokenBridge.consumeQuotaExceededSignal());
    if (!mounted || !shouldOpenPaywall) return;
    // 額度不足事件（onboarding 轉換第 6 步）：鍵盤已經跟他說額度用完了；訊號只說
    // 伺服器確認過額度不夠，分不出每日或每月。只記錄，付費頁照舊。
    unawaited(ref.read(funnelTrackerProvider).trackQuotaBlockShown(
          feature: QuotaBlockFeature.keyboard,
          scope: QuotaBlockScope.unknown,
          source: QuotaBlockSource.server,
        ));
    if (!_splashComplete) {
      _openPaywallAfterSplash = true;
      return;
    }
    _openKeyboardPaywall();
  }

  void _openKeyboardPaywall() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) router.push('/paywall');
    });
  }

  /// 冷啟動：若 app 由點擊 48h 跟進通知從終止態啟動，導到該對象跟進頁。
  /// 延到首幀後再導，確保 router 已掛載（冷啟動會先過 splash）。
  Future<void> _handleColdStartNotification() async {
    final payload = await ref.read(notificationGatewayProvider).launchPayload();
    if (payload == null || payload.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      router.go(followUpDeepLink(payload));
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_splashComplete) {
      return MaterialApp(
        title: 'VibeSync',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        builder: clampAppTextScale,
        home: SplashScreen(
          onComplete: () {
            if (!mounted) return;
            setState(() {
              _splashComplete = true;
            });
            if (_openPaywallAfterSplash) {
              _openPaywallAfterSplash = false;
              _openKeyboardPaywall();
            }
            _keyboardOnboardingScheduler.maybeSchedule();
          },
        ),
      );
    }

    return MaterialApp.router(
      title: 'VibeSync',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      builder: clampAppTextScale,
      routerConfig: router,
    );
  }
}

/// 全域字級上限 1.4（Eric 2026-08-18 拍板）：iOS 輔助字級最高約 3.1x，
/// 固定高的圖表空態／chip 在 2x 以上會溢出疊字；縮小方向不動。
/// 局部另有更嚴 clamp 的元件（ebook 卡）維持自己的上限。
Widget clampAppTextScale(BuildContext context, Widget? child) {
  final media = MediaQuery.of(context);
  return MediaQuery(
    data: media.copyWith(
      textScaler: media.textScaler.clamp(maxScaleFactor: 1.4),
    ),
    child: child!,
  );
}
