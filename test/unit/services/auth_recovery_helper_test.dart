import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibesync/core/services/auth_recovery_helper.dart';

void main() {
  group('AuthRecoveryHelper.normalizeAuthCallbackUri', () {
    test('converts hash fragment into query string when link has no query', () {
      final uri = Uri.parse(
        'com.poyutsai.vibesync://login-callback#type=recovery&access_token=abc',
      );

      final normalized = AuthRecoveryHelper.normalizeAuthCallbackUri(uri);

      expect(normalized.queryParameters['type'], 'recovery');
      expect(normalized.queryParameters['access_token'], 'abc');
    });

    test('preserves existing query and appends hash params with ampersand', () {
      final uri = Uri.parse(
        'com.poyutsai.vibesync://login-callback?foo=bar#type=recovery',
      );

      final normalized = AuthRecoveryHelper.normalizeAuthCallbackUri(uri);

      expect(normalized.queryParameters['foo'], 'bar');
      expect(normalized.queryParameters['type'], 'recovery');
    });
  });

  group('AuthRecoveryHelper.isPasswordRecoveryLink', () {
    test('returns true for recovery callback links', () {
      final uri = Uri.parse(
        'com.poyutsai.vibesync://login-callback#type=recovery',
      );

      expect(AuthRecoveryHelper.isPasswordRecoveryLink(uri), isTrue);
    });

    test('returns false for non-recovery auth links and null', () {
      final uri = Uri.parse(
        'com.poyutsai.vibesync://login-callback#type=signup',
      );

      expect(AuthRecoveryHelper.isPasswordRecoveryLink(uri), isFalse);
      expect(AuthRecoveryHelper.isPasswordRecoveryLink(null), isFalse);
    });
  });

  group('AuthRecoveryHelper.nextPasswordRecoveryState', () {
    test('enters recovery mode on passwordRecovery event', () {
      final result = AuthRecoveryHelper.nextPasswordRecoveryState(
        event: AuthChangeEvent.passwordRecovery,
        currentState: false,
      );

      expect(result, isTrue);
    });

    test('clears recovery mode on signed in and signed out', () {
      expect(
        AuthRecoveryHelper.nextPasswordRecoveryState(
          event: AuthChangeEvent.signedIn,
          currentState: true,
        ),
        isFalse,
      );
      expect(
        AuthRecoveryHelper.nextPasswordRecoveryState(
          event: AuthChangeEvent.signedOut,
          currentState: true,
        ),
        isFalse,
      );
    });

    test('keeps existing state for unrelated auth events', () {
      final result = AuthRecoveryHelper.nextPasswordRecoveryState(
        event: AuthChangeEvent.userUpdated,
        currentState: true,
      );

      expect(result, isTrue);
    });
  });
}
