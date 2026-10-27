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
//
// onboarding 轉換第 13 步（2026-10-27）：成功分析滿 2 次才自動推，次數一個
// session 只讀一次（這次打開才滿 2 次的，下次打開才推）；網頁版不推。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/app/keyboard_onboarding_scheduler.dart';
import 'package:vibesync/features/keyboard/data/keyboard_setup_resume_marker.dart';
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
          // query 一併渲染：讓測試分得出 firstRun 引導 vs 中斷復原。
          builder: (_, state) => Scaffold(
            body: Text('keyboard-setup q:${state.uri.query}'),
          ),
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

  /// [analysisCount] 預設 2（已滿門檻），既有的時序測試不受第 13 步影響。
  KeyboardOnboardingScheduler scheduler({
    required GoRouter router,
    void Function()? onShown,
    int Function()? analysisCount,
    bool isWeb = false,
  }) =>
      KeyboardOnboardingScheduler(
        router: router,
        isAuthenticated: () => true,
        isSplashComplete: () => true,
        trackShown: onShown ?? () {},
        successfulAnalysisCount: analysisCount ?? () => 2,
        isWeb: isWeb,
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

    expect(find.textContaining('keyboard-setup'), findsOneWidget,
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
    expect(find.textContaining('keyboard-setup'), findsOneWidget);

    // 使用者按 X 關閉（非完成，不寫 completed 旗標）→ 回首頁。
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    expect(find.textContaining('keyboard-setup'), findsNothing,
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
    expect(find.textContaining('keyboard-setup'), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('mid-setup 被 iOS 殺掉（中斷旗標在）：鍵盤引導已完成也要推回設定頁',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'onboarding_completed': true,
      'keyboard_onboarding_completed': true,
      KeyboardSetupResumeMarker.key: true,
    });
    await OnboardingService.load();
    final router = _coldStartRouter();
    addTearDown(router.dispose);
    var shown = 0;
    final s = scheduler(router: router, onShown: () => shown++);
    s.attach();
    addTearDown(s.detach);

    await s.primeFullAccessResume();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.textContaining('keyboard-setup'), findsOneWidget,
        reason: '中斷旗標在＝上次在設定流程中被 iOS 殺掉，無視 gate 條件也要接回去');
    expect(find.textContaining('firstRun=1'), findsNothing,
        reason: '中斷復原不是首次引導，不掛 firstRun');
    expect(shown, 0, reason: '復原不打 keyboard_setup_shown，避免污染採用漏斗');
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('成功分析未滿 2 次：冷啟動不自動推', (tester) async {
    final router = _coldStartRouter();
    addTearDown(router.dispose);
    var shown = 0;
    final s = scheduler(
      router: router,
      onShown: () => shown++,
      analysisCount: () => 1,
    );
    s.attach();
    addTearDown(s.detach);

    s.maybeSchedule();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('home'), findsOneWidget);
    expect(find.textContaining('keyboard-setup'), findsNothing,
        reason: '還沒分析滿 2 次，不在他趕著分析時擋路');
    expect(shown, 0);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('分析次數一個 session 只讀一次：這次打開才滿 2 次，下次打開才推', (tester) async {
    var count = 1;
    var reads = 0;
    int readCount() {
      reads++;
      return count;
    }

    final router = _coldStartRouter();
    addTearDown(router.dispose);
    final s = scheduler(router: router, analysisCount: readCount);
    s.attach();
    addTearDown(s.detach);
    s.maybeSchedule();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);

    // 同一個 session 裡完成第 2 次分析、回到首頁（delegate 每次導航都會叫
    // maybeSchedule）：仍用開 App 時的次數，不在他剛分析完時跳出來。
    count = 2;
    s.maybeSchedule();
    // 排程掛在 post-frame callback，測試環境沒排幀就不會跑：主動排一幀，
    // 否則這條斷言會白過。
    tester.binding.scheduleFrame();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.textContaining('keyboard-setup'), findsNothing);
    expect(reads, 1, reason: '一個 session 只讀一次分析次數');

    // 下一次打開＝新的 scheduler：讀到 2 次，推鍵盤設定。
    s.detach();
    final next = scheduler(router: router, analysisCount: readCount);
    next.attach();
    addTearDown(next.detach);
    next.maybeSchedule();
    tester.binding.scheduleFrame();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.textContaining('keyboard-setup q:firstRun=1'), findsOneWidget);
    expect(reads, 2);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('讀分析次數出錯：當 0 次不推，啟動流程不受影響', (tester) async {
    final router = _coldStartRouter();
    addTearDown(router.dispose);
    final s = scheduler(
      router: router,
      analysisCount: () => throw StateError('本機分析紀錄沒開'),
    );
    s.attach();
    addTearDown(s.detach);

    s.maybeSchedule();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('home'), findsOneWidget);
    expect(find.textContaining('keyboard-setup'), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('網頁版（iPhone Safari 開的也算）：不自動推', (tester) async {
    final router = _coldStartRouter();
    addTearDown(router.dispose);
    var shown = 0;
    final s = scheduler(router: router, onShown: () => shown++, isWeb: true);
    s.attach();
    addTearDown(s.detach);

    s.maybeSchedule();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('home'), findsOneWidget);
    expect(find.textContaining('keyboard-setup'), findsNothing,
        reason: '網頁版沒有鍵盤可裝，平台是 iOS 也不能推');
    expect(shown, 0);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
