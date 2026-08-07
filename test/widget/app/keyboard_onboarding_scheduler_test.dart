// test/widget/app/keyboard_onboarding_scheduler_test.dart
//
// 冷啟動自動 push 的時序回歸鎖（2026-08-07 真機影片重現）：
// router 初始在 /login、redirect 落到 /——splash onComplete 的觸發點
// 發生在 router 第一次 build 之前。舊接線兩處一起壞：
//   1. postFrame 讀 routeInformationProvider.value 時還停在 /login → 放棄；
//   2. redirect／程式內導航不會通知 routeInformationProvider listener
//      （go_router routerReportsNewRouteInformation 不 notifyListeners），
//      所以永遠沒有第二次機會。
// 結果＝鍵盤設定在冷啟動從不自動出現，使用者被丟回首頁要自己再點。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/app/keyboard_onboarding_scheduler.dart';
import 'package:vibesync/features/onboarding/data/onboarding_service.dart';

GoRouter _coldStartRouter() => GoRouter(
      initialLocation: '/login',
      redirect: (context, state) => state.uri.path == '/login' ? '/' : null,
      routes: [
        GoRoute(
          path: '/login',
          builder: (_, __) => const Scaffold(body: Text('login')),
        ),
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('home')),
        ),
        GoRoute(
          path: '/settings/keyboard',
          builder: (_, __) => const Scaffold(body: Text('keyboard-setup')),
        ),
      ],
    );

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'onboarding_completed': true});
    await OnboardingService.load();
  });

  tearDown(() async {
    await OnboardingService.reset();
    await OnboardingService.resetKeyboard();
  });

  KeyboardOnboardingScheduler scheduler({
    required GoRouter router,
    void Function()? onShown,
  }) =>
      KeyboardOnboardingScheduler(
        router: router,
        isAuthenticated: () => true,
        isSplashComplete: () => true,
        trackShown: onShown ?? () {},
      );

  testWidgets('冷啟動：觸發早於 router 首次 build（redirect 未落定）也要推得出設定頁',
      (tester) async {
    final router = _coldStartRouter();
    addTearDown(router.dispose);
    var shown = 0;
    final s = scheduler(router: router, onShown: () => shown++);
    s.attach();
    addTearDown(s.detach);

    // 模擬 splash onComplete：setState 換入 MaterialApp.router 前先觸發。
    s.maybeSchedule();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('keyboard-setup'), findsOneWidget,
        reason: '冷啟動條件齊備時必須自動回到鍵盤設定，不能把使用者丟在首頁');
    expect(shown, 1);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('自動 push 一個 session 只發生一次：關閉後在首頁間導航不得再推',
      (tester) async {
    final router = _coldStartRouter();
    addTearDown(router.dispose);
    final s = scheduler(router: router);
    s.attach();
    addTearDown(s.detach);

    s.maybeSchedule();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('keyboard-setup'), findsOneWidget);

    // 使用者按 X 關閉（非完成，不寫 completed 旗標）→ 回首頁。
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    expect(find.text('keyboard-setup'), findsNothing,
        reason: '同一個 session 關掉後不得立刻再自動彈出（會變成騷擾迴圈）');
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('鍵盤設定已完成 → 冷啟動不自動推', (tester) async {
    await OnboardingService.markKeyboardCompleted();
    final router = _coldStartRouter();
    addTearDown(router.dispose);
    final s = scheduler(router: router);
    s.attach();
    addTearDown(s.detach);

    s.maybeSchedule();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('home'), findsOneWidget);
    expect(find.text('keyboard-setup'), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
