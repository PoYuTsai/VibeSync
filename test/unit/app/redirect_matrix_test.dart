// test/unit/app/redirect_matrix_test.dart
//
// Pure redirect-matrix test for the app router's auth + onboarding gate.
// `resolveAppRedirect` is the single decision function the live GoRouter
// redirect delegates to, so the full matrix can be asserted without mounting
// widgets, Supabase, or SharedPreferences.
//
// Matrix (matchedLocation x isLoggedIn x isOnboardingCompleted x recovery):
//   - Unauthenticated + onboarding incomplete -> forced to /onboarding
//     (2026-08-18: onboarding moved before login).
//   - Unauthenticated + onboarding complete -> only /login is reachable.
//   - Authenticated + onboarding incomplete -> forced to /onboarding.
//   - Authenticated + onboarding complete   -> never sees /login or /onboarding.
//   - Password recovery keeps the user on /login to set a new password.
//   - onboarding 轉換第 12 步：第 1 頁右上「我有帳號」直接到登入，App 要先記成看過
//     onboarding 再 go('/login')，否則會被拉回 /onboarding（見倒數第二組）。
//   - 18+ 年齡確認（AGE-01）：登入、看完 onboarding 之後，帳號還沒確認成年就只能
//     待在 /age-gate，設定頁開著（見最後一組）。其他組都當已確認成年。
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/app/routes.dart';

String? redirect({
  required bool isLoggedIn,
  required bool isOnboardingCompleted,
  required String matchedLocation,
  bool isPasswordRecovery = false,
  bool isAdultConfirmed = true,
}) =>
    resolveAppRedirect(
      isLoggedIn: isLoggedIn,
      isOnboardingCompleted: isOnboardingCompleted,
      isPasswordRecovery: isPasswordRecovery,
      isAdultConfirmed: isAdultConfirmed,
      matchedLocation: matchedLocation,
    );

void main() {
  group('resolveAppRedirect — unauthenticated gate（onboarding 先於登入）', () {
    test('not logged in + onboarding incomplete on /login goes to /onboarding',
        () {
      expect(
        redirect(
          isLoggedIn: false,
          isOnboardingCompleted: false,
          matchedLocation: '/login',
        ),
        '/onboarding',
      );
    });

    test('not logged in + onboarding incomplete on /onboarding stays', () {
      expect(
        redirect(
          isLoggedIn: false,
          isOnboardingCompleted: false,
          matchedLocation: '/onboarding',
        ),
        isNull,
      );
    });

    test('not logged in + onboarding complete on /login stays on /login', () {
      expect(
        redirect(
          isLoggedIn: false,
          isOnboardingCompleted: true,
          matchedLocation: '/login',
        ),
        isNull,
      );
    });

    test('not logged in + onboarding complete on /onboarding goes to /login',
        () {
      expect(
        redirect(
          isLoggedIn: false,
          isOnboardingCompleted: true,
          matchedLocation: '/onboarding',
        ),
        '/login',
      );
    });

    test('not logged in + onboarding incomplete on / goes to /onboarding', () {
      expect(
        redirect(
          isLoggedIn: false,
          isOnboardingCompleted: false,
          matchedLocation: '/',
        ),
        '/onboarding',
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

  // onboarding 轉換第 12 步：「我有帳號」＝OnboardingService.markCompleted() 之後
  // 才 go('/login')。三步照順序走一遍，順序反過來就是迴圈。
  group('resolveAppRedirect — 「我有帳號」直接到登入（不卡迴圈）', () {
    test('還沒記成看過 onboarding 就去 /login：會被拉回 /onboarding', () {
      expect(
        redirect(
          isLoggedIn: false,
          isOnboardingCompleted: false,
          matchedLocation: '/login',
        ),
        '/onboarding',
      );
    });

    test('先記成看過再去 /login：停在登入頁', () {
      expect(
        redirect(
          isLoggedIn: false,
          isOnboardingCompleted: true,
          matchedLocation: '/login',
        ),
        isNull,
      );
    });

    test('登入之後從 /login 進首頁，不會再看到 onboarding', () {
      expect(
        redirect(
          isLoggedIn: true,
          isOnboardingCompleted: true,
          matchedLocation: '/login',
        ),
        '/',
      );
      expect(
        redirect(
          isLoggedIn: true,
          isOnboardingCompleted: true,
          matchedLocation: '/onboarding',
        ),
        '/',
      );
    });
  });

  group('resolveAppRedirect — 18+ 年齡確認（AGE-01）', () {
    String? notConfirmed(String location, {bool onboarded = true}) => redirect(
          isLoggedIn: true,
          isOnboardingCompleted: onboarded,
          matchedLocation: location,
          isAdultConfirmed: false,
        );

    test('還沒確認成年（沒紀錄或未成年）：哪裡都導去 /age-gate', () {
      for (final location in [
        '/',
        '/login',
        '/onboarding',
        '/partner/p1',
        '/paywall',
        '/practice-collection',
        // 鍵盤設定不開：別用 startsWith('/settings') 一次放行整組設定子頁。
        '/settings/keyboard',
      ]) {
        expect(notConfirmed(location), '/age-gate', reason: location);
      }
    });

    test('還沒確認成年：停在 /age-gate，設定頁（登出、刪除帳號）與 AI 隱私說明開著', () {
      expect(notConfirmed('/age-gate'), isNull);
      expect(notConfirmed('/settings'), isNull);
      expect(notConfirmed('/settings/ai-privacy'), isNull);
    });

    test('onboarding 還沒看完：先看 onboarding，再問年齡', () {
      expect(notConfirmed('/', onboarded: false), '/onboarding');
      expect(notConfirmed('/onboarding', onboarded: false), isNull);
      expect(notConfirmed('/age-gate', onboarded: false), '/onboarding');
    });

    test('沒登入：照舊先 onboarding／登入，不問年齡', () {
      for (final onboarded in [false, true]) {
        expect(
          redirect(
            isLoggedIn: false,
            isOnboardingCompleted: onboarded,
            matchedLocation: '/age-gate',
            isAdultConfirmed: false,
          ),
          onboarded ? '/login' : '/onboarding',
        );
      }
    });

    test('重設密碼中：停在 /login 設新密碼，不被年齡確認打斷', () {
      expect(
        redirect(
          isLoggedIn: true,
          isOnboardingCompleted: true,
          matchedLocation: '/login',
          isPasswordRecovery: true,
          isAdultConfirmed: false,
        ),
        isNull,
      );
    });

    test('確認成年之後：/age-gate 回首頁，其他頁照常', () {
      expect(
        redirect(
          isLoggedIn: true,
          isOnboardingCompleted: true,
          matchedLocation: '/age-gate',
        ),
        '/',
      );
      expect(
        redirect(
          isLoggedIn: true,
          isOnboardingCompleted: true,
          matchedLocation: '/partner/p1',
        ),
        isNull,
      );
    });
  });
}
