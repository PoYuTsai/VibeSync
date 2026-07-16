import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vibesync/features/keyboard/presentation/screens/keyboard_setup_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/features/onboarding/data/onboarding_service.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await OnboardingService.load();
  });

  testWidgets('teaches settings permission before globe and quick reply',
      (tester) async {
    var settingsOpened = 0;
    final router = GoRouter(
      initialLocation: '/keyboard',
      routes: [
        GoRoute(
          path: '/keyboard',
          builder: (_, __) => KeyboardSetupScreen(
            openSettings: () async {
              settingsOpened++;
              return true;
            },
          ),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    expect(find.text('聊天不用再跳出 App'), findsOneWidget);
    expect(find.text('🔄 延展'), findsOneWidget);

    await tester.tap(find.text('下一步'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('先啟用 VibeSync 鍵盤'), findsOneWidget);
    expect(find.textContaining('只會將你主動點擊「載入」的文字'), findsOneWidget);

    await tester.tap(find.text('前往 iPhone 設定'));
    await tester.pump();
    expect(settingsOpened, 1);

    await tester.tap(find.text('我已完成設定'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('長按地球，切換鍵盤'), findsOneWidget);

    await tester.tap(find.text('下一步'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('三步就有好回覆'), findsOneWidget);
    expect(find.text('選風格，確認後送出'), findsOneWidget);
  });

  testWidgets('first-run setup can be postponed and is persisted',
      (tester) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, __) => const SizedBox.shrink()),
        GoRoute(
          path: '/keyboard',
          builder: (_, __) => const KeyboardSetupScreen(firstRun: true),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    router.push('/keyboard');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('稍後設定'), findsOneWidget);
    await tester.tap(find.text('稍後設定'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(OnboardingService.isKeyboardCompletedSync, isTrue);
  });
}
