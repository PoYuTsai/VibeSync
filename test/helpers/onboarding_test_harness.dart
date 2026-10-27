// test/helpers/onboarding_test_harness.dart
//
// 4 頁版 onboarding（onboarding 轉換第 12 步）的 widget test 鷹架：
//   - [RecordingFunnelTracker]：記下每一筆漏斗事件，不送網路、不排佇列。
//   - [onboardingStubRouter]：沒有 redirect 的 stub GoRouter，帶出各目的地的
//     query（next、guide），測試看得到真的導到哪。
//   - [pumpOnboardingApp]：登入狀態、題庫、關於我倉庫都可以換。
//
// 題庫一律注入：真內容用 [loadProductionChatQuizCatalog] 在 setUpAll（真 async）
// 先讀好——大 JSON 經 rootBundle 會走 isolate 解碼，testWidgets 的 fake async
// 等不到。
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vibesync/core/services/funnel_tracker.dart';
import 'package:vibesync/features/learning/data/providers/chat_quiz_providers.dart';
import 'package:vibesync/features/learning/domain/models/chat_quiz.dart';
import 'package:vibesync/features/onboarding/domain/onboarding_intent.dart';
import 'package:vibesync/features/onboarding/presentation/screens/onboarding_screen.dart';
import 'package:vibesync/features/user_profile/data/providers/user_profile_providers.dart';
import 'package:vibesync/features/user_profile/data/repositories/user_profile_repository.dart';

/// 記下每一筆 track；不送、不排隊。
class RecordingFunnelTracker extends FunnelTracker {
  RecordingFunnelTracker()
      : super(
          invoker: (fn, {required body}) async => 200,
          currentUserId: () => null,
        );

  final events = <({String event, Map<String, Object?> properties})>[];

  @override
  Future<bool> track(
    String event, {
    Map<String, Object?> properties = const {},
  }) async {
    events.add((event: event, properties: Map.of(properties)));
    return true;
  }

  List<String> get names => [for (final e in events) e.event];

  /// 某個事件每一筆的 properties（照發生順序）。
  List<Map<String, Object?>> propsOf(String event) => [
        for (final e in events)
          if (e.event == event) e.properties,
      ];
}

const mainShellStubText = 'main-shell';
const loginStubText = 'login-screen';
const openerStubText = 'opener-screen';

GoRouter onboardingStubRouter() => GoRouter(
      initialLocation: '/onboarding',
      routes: [
        GoRoute(
          path: '/onboarding',
          builder: (_, __) => const OnboardingScreen(),
        ),
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text(mainShellStubText)),
        ),
        GoRoute(
          path: '/login',
          builder: (_, __) => const Scaffold(body: Text(loginStubText)),
        ),
        GoRoute(
          path: '/partner/new',
          builder: (_, state) => Scaffold(
            body: Text(
              'partner-new-screen next=${state.uri.queryParameters['next']}',
            ),
          ),
        ),
        GoRoute(
          path: '/opener',
          builder: (_, __) => const Scaffold(body: Text(openerStubText)),
        ),
        GoRoute(
          path: '/practice-collection',
          builder: (_, state) => Scaffold(
            body: Text(
              'practice-collection-screen '
              'guide=${state.uri.queryParameters['guide']}',
            ),
          ),
        ),
      ],
    );

class OnboardingHarness {
  OnboardingHarness({required this.funnel, required this.router});

  final RecordingFunnelTracker funnel;
  final GoRouter router;

  String get location =>
      router.routerDelegate.currentConfiguration.uri.toString();
}

/// [signedInUid] 是 null＝還沒登入（onboarding 走在登入前的一般情況）。
Future<OnboardingHarness> pumpOnboardingApp(
  WidgetTester tester, {
  ChatQuizCatalog? catalog,
  Object? catalogError,
  String? signedInUid,
  UserProfileRepository? profileRepository,
  Size size = const Size(390, 900),
}) async {
  assert(catalog != null || catalogError != null, '題庫或錯誤要給一個');
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final funnel = RecordingFunnelTracker();
  final router = onboardingStubRouter();
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        funnelTrackerProvider.overrideWithValue(funnel),
        authUserProfileScopeProvider
            .overrideWith((ref) => Stream<String?>.value(signedInUid)),
        if (catalogError != null)
          chatQuizCatalogProvider
              .overrideWith((ref) async => throw catalogError)
        else
          chatQuizCatalogProvider.overrideWith((ref) async => catalog!),
        if (profileRepository != null)
          userProfileRepositoryProvider.overrideWithValue(profileRepository),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return OnboardingHarness(funnel: funnel, router: router);
}

Future<void> chooseIntent(WidgetTester tester, OnboardingIntent intent) async {
  await tester.tap(find.byKey(ValueKey('onboarding-intent-${intent.wire}')));
  await tester.pumpAndSettle();
}

/// 用讀屏點（VoiceOver 點兩下）：送 [SemanticsAction.tap] 給 [finder] 所在的語意節點，
/// 不是點座標。呼叫前要先 `tester.ensureSemantics()`。節點沒有點擊動作就直接失敗。
Future<void> semanticsTap(WidgetTester tester, Finder finder) async {
  final node = tester.getSemantics(finder);
  expect(
    node.getSemanticsData().hasAction(SemanticsAction.tap),
    isTrue,
    reason: '讀屏要點得到',
  );
  node.owner!.performAction(node.id, SemanticsAction.tap);
  await tester.pumpAndSettle();
}

/// 點頂列或底部的按鈕（用字找；同一頁不會有兩顆同字的按鈕）。
Future<void> tapLabel(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

/// 選路徑 → 第 2 頁「直接開始」→ 第 4 頁。
Future<void> goToFinishPage(
  WidgetTester tester,
  OnboardingIntent intent,
) async {
  await chooseIntent(tester, intent);
  await tapLabel(tester, OnboardingScreen.skipQuizLabel);
}
