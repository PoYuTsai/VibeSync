// test/widget/app/onboarding_gate_router_test.dart
//
// Integration of `resolveAppRedirect` with a real GoRouter: proves the redirect
// matrix is actually honored end-to-end (including GoRouter redirect chaining,
// e.g. '/' -> '/onboarding' -> null) and lands on the right screen.
//
// Uses sentinels for login/onboarding/main shell so the test stays a routing
// test and does not drag in Supabase / Hive / providers (same approach as
// router_test.dart). Auth + onboarding state are injected as plain bools.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vibesync/app/routes.dart';

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
  testWidgets('unauthenticated deep link lands on login', (t) async {
    await _pump(t,
        initialLocation: '/partner/abc',
        isLoggedIn: false,
        isOnboardingCompleted: false);
    expect(find.text('login-screen'), findsOneWidget);
  });

  testWidgets('logged-in first-run on / chains into onboarding', (t) async {
    await _pump(t,
        initialLocation: '/',
        isLoggedIn: true,
        isOnboardingCompleted: false);
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
}
