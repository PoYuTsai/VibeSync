// test/widget/app/onboarding_gate_router_test.dart
//
// Integration of `resolveAppRedirect` with a real GoRouter: proves the redirect
// matrix is actually honored end-to-end (including GoRouter redirect chaining,
// e.g. '/' -> '/onboarding' -> null) and lands on the right screen.
//
// Uses sentinels for login/onboarding/main shell so the test stays a routing
// test and does not drag in Supabase / Hive / providers (same approach as
// router_test.dart). Auth + onboarding state are injected as plain bools.
//
// onboarding 轉換第 12 步另加一組：/onboarding 掛真的 4 頁版 OnboardingScreen，
// redirect 照 App 一樣即時讀 OnboardingService.isCompletedSync，驗「我有帳號」
// 「先逛逛」「繼續」三個出口都落在登入頁、不會被拉回 onboarding。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/app/routes.dart';
import 'package:vibesync/core/services/funnel_tracker.dart';
import 'package:vibesync/features/learning/data/providers/chat_quiz_providers.dart';
import 'package:vibesync/features/onboarding/data/onboarding_service.dart';
import 'package:vibesync/features/onboarding/domain/onboarding_intent.dart';
import 'package:vibesync/features/onboarding/presentation/screens/onboarding_screen.dart';
import 'package:vibesync/features/onboarding/presentation/widgets/onboarding_intent_page.dart';
import 'package:vibesync/features/user_profile/data/providers/user_profile_providers.dart';

import '../../helpers/chat_quiz_test_content.dart';
import '../../helpers/onboarding_test_harness.dart';

GoRouter _gatedRouter({
  required String initialLocation,
  required bool isLoggedIn,
  required bool isOnboardingCompleted,
  bool isPasswordRecovery = false,
}) =>
    GoRouter(
      initialLocation: initialLocation,
      redirect: (context, state) => resolveAppRedirect(
        isLoggedIn: isLoggedIn,
        isOnboardingCompleted: isOnboardingCompleted,
        isPasswordRecovery: isPasswordRecovery,
        // 這份測 onboarding 與登入的閘門；年齡確認在 redirect_matrix_test 與
        // age_gate_router_test。
        isAdultConfirmed: true,
        matchedLocation: state.matchedLocation,
      ),
      routes: [
        GoRoute(
          path: '/login',
          builder: (_, __) => const Scaffold(body: Text('login-screen')),
        ),
        GoRoute(
          path: '/onboarding',
          builder: (_, __) => const Scaffold(body: Text('onboarding-screen')),
        ),
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('main-shell')),
        ),
        GoRoute(
          path: '/partner/:id',
          builder: (_, s) =>
              Scaffold(body: Text('partner:${s.pathParameters['id']}')),
        ),
      ],
    );

Future<void> _pump(
  WidgetTester t, {
  required String initialLocation,
  required bool isLoggedIn,
  required bool isOnboardingCompleted,
  bool isPasswordRecovery = false,
}) async {
  await t.pumpWidget(MaterialApp.router(
    routerConfig: _gatedRouter(
      initialLocation: initialLocation,
      isLoggedIn: isLoggedIn,
      isOnboardingCompleted: isOnboardingCompleted,
      isPasswordRecovery: isPasswordRecovery,
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('unauthenticated first-run deep link lands on onboarding',
      (t) async {
    await _pump(t,
        initialLocation: '/partner/abc',
        isLoggedIn: false,
        isOnboardingCompleted: false);
    expect(find.text('onboarding-screen'), findsOneWidget);
  });

  testWidgets('unauthenticated + onboarding done deep link lands on login',
      (t) async {
    await _pump(t,
        initialLocation: '/partner/abc',
        isLoggedIn: false,
        isOnboardingCompleted: true);
    expect(find.text('login-screen'), findsOneWidget);
  });

  testWidgets('logged-in first-run on / chains into onboarding', (t) async {
    await _pump(t,
        initialLocation: '/', isLoggedIn: true, isOnboardingCompleted: false);
    expect(find.text('onboarding-screen'), findsOneWidget);
    expect(find.text('main-shell'), findsNothing);
  });

  testWidgets('logged-in first-run landing on /login reaches onboarding',
      (t) async {
    await _pump(t,
        initialLocation: '/login',
        isLoggedIn: true,
        isOnboardingCompleted: false);
    expect(find.text('onboarding-screen'), findsOneWidget);
  });

  testWidgets('completed user never sees onboarding (lands on main shell)',
      (t) async {
    await _pump(t,
        initialLocation: '/onboarding',
        isLoggedIn: true,
        isOnboardingCompleted: true);
    expect(find.text('main-shell'), findsOneWidget);
    expect(find.text('onboarding-screen'), findsNothing);
  });

  testWidgets('completed user on a deep route stays on it', (t) async {
    await _pump(t,
        initialLocation: '/partner/xyz',
        isLoggedIn: true,
        isOnboardingCompleted: true);
    expect(find.text('partner:xyz'), findsOneWidget);
  });

  testWidgets('password recovery keeps the user on login', (t) async {
    await _pump(t,
        initialLocation: '/login',
        isLoggedIn: true,
        isOnboardingCompleted: false,
        isPasswordRecovery: true);
    expect(find.text('login-screen'), findsOneWidget);
    expect(find.text('onboarding-screen'), findsNothing);
  });

  // ---------------------------------------------------------------------------
  // onboarding 轉換第 12 步：真的 OnboardingScreen＋即時讀完成旗標的 redirect。
  // ---------------------------------------------------------------------------
  group('4 頁版 onboarding 的出口（未登入）', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await OnboardingService.reset();
    });

    GoRouter liveGateRouter() => GoRouter(
          initialLocation: '/',
          redirect: (context, state) => resolveAppRedirect(
            isLoggedIn: false,
            // 跟 App 的 router 一樣，每次導航都讀記憶體裡的完成旗標。
            isOnboardingCompleted: OnboardingService.isCompletedSync,
            isPasswordRecovery: false,
            isAdultConfirmed: false,
            matchedLocation: state.matchedLocation,
          ),
          routes: [
            GoRoute(
              path: '/login',
              builder: (_, __) => const Scaffold(body: Text('login-screen')),
            ),
            GoRoute(
              path: '/onboarding',
              builder: (_, __) => const OnboardingScreen(),
            ),
            GoRoute(
              path: '/',
              builder: (_, __) => const Scaffold(body: Text('main-shell')),
            ),
          ],
        );

    Future<void> pumpLive(WidgetTester t) async {
      final router = liveGateRouter();
      addTearDown(router.dispose);
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            funnelTrackerProvider.overrideWithValue(RecordingFunnelTracker()),
            authUserProfileScopeProvider
                .overrideWith((ref) => Stream<String?>.value(null)),
            chatQuizCatalogProvider
                .overrideWith((ref) async => buildTestChatQuizCatalog()),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await t.pumpAndSettle();
    }

    testWidgets('第一次開被帶進 onboarding；「我有帳號」落在登入頁，不會被拉回來', (t) async {
      await pumpLive(t);
      expect(find.text(OnboardingIntentPage.title), findsOneWidget);

      await t.tap(find.text(OnboardingScreen.haveAccountLabel));
      await t.pumpAndSettle();

      expect(find.text('login-screen'), findsOneWidget);
      expect(find.text(OnboardingIntentPage.title), findsNothing);
      expect(OnboardingService.isCompletedSync, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(OnboardingService.pendingHandoffKey), isFalse);
    });

    testWidgets('「先逛逛」：回到 / 再被轉去登入頁', (t) async {
      await pumpLive(t);

      await t.tap(find.text(OnboardingIntentPage.browseLabel));
      await t.pumpAndSettle();

      expect(find.text('login-screen'), findsOneWidget);
      expect(find.text('main-shell'), findsNothing);
    });

    testWidgets('走到最後一頁按「繼續」：轉去登入頁，暫存留給登入後', (t) async {
      await pumpLive(t);

      await t.tap(find.byKey(const ValueKey('onboarding-intent-opener')));
      await t.pumpAndSettle();
      await t.tap(find.text(OnboardingScreen.skipQuizLabel));
      await t.pumpAndSettle();
      await t.tap(find.text(OnboardingScreen.finishLabel));
      await t.pumpAndSettle();

      expect(find.text('login-screen'), findsOneWidget);
      final handoff = await OnboardingService.readPendingHandoff();
      expect(handoff?.intent, OnboardingIntent.opener);
      expect(handoff?.route, '/opener');
    });
  });
}
