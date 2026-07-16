// lib/app/app.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_theme.dart';
import '../core/services/keyboard_token_bridge.dart';
import '../features/follow_up_notification/data/providers/follow_up_notification_service.dart';
import '../features/splash/presentation/screens/splash_screen.dart';
import 'routes.dart';

class App extends ConsumerStatefulWidget {
  const App({super.key});

  @override
  ConsumerState<App> createState() => _AppState();
}

class _AppState extends ConsumerState<App> with WidgetsBindingObserver {
  bool _splashComplete = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _handleColdStartNotification();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      KeyboardTokenBridge.syncOnForeground();
    }
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
        home: SplashScreen(
          onComplete: () {
            if (!mounted) return;
            setState(() {
              _splashComplete = true;
            });
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
