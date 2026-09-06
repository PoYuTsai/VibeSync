// Local visual/media inspection harness. Production uses app/routes.dart.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vibesync/features/night_market/presentation/screens/night_market_screen.dart';

void main() {
  // Keep semantics enabled for browser accessibility and automated inspection.
  WidgetsFlutterBinding.ensureInitialized().ensureSemantics();
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => const NightMarketScreen()),
    GoRoute(
      path: '/practice-collection',
      builder: (_, __) => const Scaffold(
        body: Center(child: Text('預覽模式：正式 App 會開啟角色圖鑑。')),
      ),
    ),
  ]);
  runApp(MaterialApp.router(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true),
    routerConfig: router,
  ));
}
