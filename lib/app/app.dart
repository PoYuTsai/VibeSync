// lib/app/app.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_theme.dart';
import '../features/splash/presentation/screens/splash_screen.dart';
import 'routes.dart';

class App extends ConsumerStatefulWidget {
  const App({super.key});

  @override
  ConsumerState<App> createState() => _AppState();
}

class _AppState extends ConsumerState<App> {
  bool _splashComplete = false;

  @override
  Widget build(BuildContext context) {
    if (!_splashComplete) {
      return MaterialApp(
        title: 'VibeSync',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: SplashScreen(
          onComplete: () {
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
