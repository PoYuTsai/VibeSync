// test/unit/app/redirect_matrix_test.dart
//
// Pure redirect-matrix test for the app router's auth + onboarding gate.
// `resolveAppRedirect` is the single decision function the live GoRouter
// redirect delegates to, so the full matrix can be asserted without mounting
// widgets, Supabase, or SharedPreferences.
//
// Matrix (matchedLocation x isLoggedIn x isOnboardingCompleted x recovery):
//   - Unauthenticated -> only /login is reachable (auth gate, unchanged).
//   - Authenticated + onboarding incomplete -> forced to /onboarding.
//   - Authenticated + onboarding complete   -> never sees /login or /onboarding.
//   - Password recovery keeps the user on /login to set a new password.
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/app/routes.dart';

String? redirect({
  required bool isLoggedIn,
  required bool isOnboardingCompleted,
  required String matchedLocation,
  bool isPasswordRecovery = false,
}) =>
    resolveAppRedirect(
      isLoggedIn: isLoggedIn,
      isOnboardingCompleted: isOnboardingCompleted,
      isPasswordRecovery: isPasswordRecovery,
      matchedLocation: matchedLocation,
    );

void main() {
  group('resolveAppRedirect — unauthenticated auth gate (unchanged)', () {
    test('not logged in on /login stays on /login', () {
      expect(
        redirect(
          isLoggedIn: false,
          isOnboardingCompleted: false,
          matchedLocation: '/login',
        ),
        isNull,
      );
    });

    test('not logged in on / is sent to /login', () {
      expect(
        redirect(
          isLoggedIn: false,
          isOnboardingCompleted: false,
          matchedLocation: '/',
        ),
        '/login',
      );
    });

    test('not logged in on a deep route is sent to /login', () {
      expect(
        redirect(
          isLoggedIn: false,
          isOnboardingCompleted: true,
          matchedLocation: '/partner/abc',
        ),
        '/login',
      );
    });
  });

  group('resolveAppRedirect — logged in, onboarding incomplete', () {
    test('on /login is routed into /onboarding (first run)', () {
      expect(
        redirect(
          isLoggedIn: true,
          isOnboardingCompleted: false,
          matchedLocation: '/login',
        ),
        '/onboarding',
      );
    });

    test('on /onboarding stays on /onboarding', () {
      expect(
        redirect(
          isLoggedIn: true,
          isOnboardingCompleted: false,
          matchedLocation: '/onboarding',
        ),
        isNull,
      );
    });

    test('on main shell is forced back to /onboarding', () {
      expect(
        redirect(
          isLoggedIn: true,
          isOnboardingCompleted: false,
          matchedLocation: '/',
        ),
        '/onboarding',
      );
    });

    test('on a deep route is forced back to /onboarding', () {
      expect(
        redirect(
          isLoggedIn: true,
          isOnboardingCompleted: false,
          matchedLocation: '/partner/abc',
        ),
        '/onboarding',
      );
    });
  });

  group('resolveAppRedirect — logged in, onboarding complete', () {
    test('on /login is routed into main shell', () {
      expect(
        redirect(
          isLoggedIn: true,
          isOnboardingCompleted: true,
          matchedLocation: '/login',
        ),
        '/',
      );
    });

    test('on /onboarding never re-sees onboarding, routed to main shell', () {
      expect(
        redirect(
          isLoggedIn: true,
          isOnboardingCompleted: true,
          matchedLocation: '/onboarding',
        ),
        '/',
      );
    });

    test('on main shell stays on main shell', () {
      expect(
        redirect(
          isLoggedIn: true,
          isOnboardingCompleted: true,
          matchedLocation: '/',
        ),
        isNull,
      );
    });

    test('on a deep route stays put', () {
      expect(
        redirect(
          isLoggedIn: true,
          isOnboardingCompleted: true,
          matchedLocation: '/partner/abc',
        ),
        isNull,
      );
    });
  });

  group('resolveAppRedirect — password recovery preserved', () {
    test('recovery on /login stays on /login even when incomplete', () {
      expect(
        redirect(
          isLoggedIn: true,
          isOnboardingCompleted: false,
          matchedLocation: '/login',
          isPasswordRecovery: true,
        ),
        isNull,
      );
    });

    test('recovery on /login stays on /login even when complete', () {
      expect(
        redirect(
          isLoggedIn: true,
          isOnboardingCompleted: true,
          matchedLocation: '/login',
          isPasswordRecovery: true,
        ),
        isNull,
      );
    });
  });
}
