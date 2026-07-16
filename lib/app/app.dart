// lib/app/app.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_theme.dart';
import '../core/services/keyboard_token_bridge.dart';
import '../core/services/supabase_service.dart';
import '../features/follow_up_notification/data/providers/follow_up_notification_service.dart';
import '../features/onboarding/data/onboarding_service.dart';
import '../features/splash/presentation/screens/splash_screen.dart';
import 'routes.dart';

class App extends ConsumerStatefulWidget {
  const App({super.key});

  @override
  ConsumerState<App> createState() => _AppState();
}

class _AppState extends ConsumerState<App> with WidgetsBindingObserver {
  bool _splashComplete = false;
  bool _openPaywallAfterSplash = false;
  bool _keyboardOnboardingPending = false;
  StreamSubscription<dynamic>? _authSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    router.routeInformationProvider.addListener(_handleRouteChanged);
    _authSubscription = SupabaseService.authStateChanges.listen((_) {
      _scheduleKeyboardOnboarding();
    });
    _handleColdStartNotification();
    _handleKeyboardQuotaSignal();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    router.routeInformationProvider.removeListener(_handleRouteChanged);
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
        await KeyboardTokenBridge.consumeQuotaExceededSignal();
    if (!mounted || !shouldOpenPaywall) return;
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

  /// Shows the keyboard setup once after the normal app onboarding and login.
  /// It is intentionally outside the router redirect so dismissing it never
  /// blocks the core app or deep links.
  void _scheduleKeyboardOnboarding() {
    if (!_splashComplete ||
        !SupabaseService.isAuthenticated ||
        !OnboardingService.isCompletedSync ||
        OnboardingService.isKeyboardCompletedSync ||
        _keyboardOnboardingPending) {
      return;
    }

    _keyboardOnboardingPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final currentPath = router.routeInformationProvider.value.uri.path;
      if (currentPath != '/') {
        _keyboardOnboardingPending = false;
        return;
      }
      router.push('/settings/keyboard?firstRun=1').whenComplete(() {
        _keyboardOnboardingPending = false;
      });
    });
  }

  void _handleRouteChanged() => _scheduleKeyboardOnboarding();

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
            _scheduleKeyboardOnboarding();
          },
        ),
      );
    }

    return MaterialApp.router(
      title: 'VibeSync',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      routerConfig: router,
    );
  }
}
