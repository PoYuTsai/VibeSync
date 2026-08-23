import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/core/config/auth_callback_contract.dart';
import 'package:vibesync/core/config/environment.dart';

void main() {
  group('auth callback URI policy', () {
    test('accepts only the exact OAuth callback origin', () {
      expect(
        AuthCallbackUriPolicy.isOAuthCallback(
          Uri.parse('com.poyutsai.vibesync://login-callback?code=abc'),
        ),
        isTrue,
      );
      expect(
        AuthCallbackUriPolicy.isOAuthCallback(
          Uri.parse('com.poyutsai.vibesync://login-callback/wrong?code=abc'),
        ),
        isFalse,
      );
      expect(
        AuthCallbackUriPolicy.isOAuthCallback(
          Uri.parse('com.poyutsai.other://login-callback?code=abc'),
        ),
        isFalse,
      );
      expect(
        AuthCallbackUriPolicy.isOAuthCallback(
          Uri.parse('com.poyutsai.vibesync://wrong-host?code=abc'),
        ),
        isFalse,
      );
      expect(
        AuthCallbackUriPolicy.isOAuthCallback(
          Uri.parse(
            'com.poyutsai.vibesync://login-callback:443?code=abc',
          ),
        ),
        isFalse,
      );
      expect(
        AuthCallbackUriPolicy.isOAuthCallback(
          Uri.parse(
            'user:pass@com.poyutsai.vibesync://login-callback?code=abc',
          ),
        ),
        isFalse,
      );
    });

    test('accepts only exact Email flow paths', () {
      for (final path in ['/signup', '/recovery']) {
        expect(
          AuthCallbackUriPolicy.isEmailCallback(
            Uri.parse('com.poyutsai.vibesync://email-callback$path?code=abc'),
          ),
          isTrue,
        );
      }
      expect(
        AuthCallbackUriPolicy.isEmailCallback(
          Uri.parse('com.poyutsai.vibesync://email-callback?code=abc'),
        ),
        isFalse,
      );
      expect(
        AuthCallbackUriPolicy.isEmailCallback(
          Uri.parse(
              'com.poyutsai.vibesync://email-callback/signup/recovery?code=abc'),
        ),
        isFalse,
      );
      expect(
        AuthCallbackUriPolicy.isEmailCallback(
          Uri.parse('com.poyutsai.vibesync://email-callback/wrong?code=abc'),
        ),
        isFalse,
      );
      expect(
        AuthCallbackUriPolicy.isEmailCallback(
          Uri.parse('com.poyutsai.vibesync://email-callback/signup/?code=abc'),
        ),
        isFalse,
      );
      expect(
        AuthCallbackUriPolicy.isEmailCallback(
          Uri.parse('com.poyutsai.other://email-callback/signup?code=abc'),
        ),
        isFalse,
      );
      expect(
        AuthCallbackUriPolicy.isEmailCallback(
          Uri.parse(
            'user:pass@com.poyutsai.vibesync://email-callback/signup?code=abc',
          ),
        ),
        isFalse,
      );
      expect(
        AuthCallbackUriPolicy.isEmailCallback(
          Uri.parse('com.poyutsai.vibesync://login-callback?code=abc'),
        ),
        isFalse,
      );
    });

    test('processes only exact Email callbacks carrying an auth result', () {
      expect(
        AuthCallbackUriPolicy.isProcessableEmailAuthCallback(
          Uri.parse(
            'com.poyutsai.vibesync://email-callback/recovery?code=abc',
          ),
        ),
        isTrue,
      );
      expect(
        AuthCallbackUriPolicy.isProcessableEmailAuthCallback(
          Uri.parse(
            'com.poyutsai.vibesync://email-callback/signup#error_description=expired',
          ),
        ),
        isTrue,
      );
      expect(
        AuthCallbackUriPolicy.isProcessableEmailAuthCallback(
          Uri.parse(
            'com.poyutsai.vibesync://email-callback/recovery',
          ),
        ),
        isFalse,
      );
      expect(
        AuthCallbackUriPolicy.isProcessableEmailAuthCallback(
          Uri.parse('com.poyutsai.vibesync://email-callback?code=abc'),
        ),
        isFalse,
      );
      expect(
        AuthCallbackUriPolicy.isProcessableEmailAuthCallback(
          Uri.parse(
            'com.poyutsai.vibesync://email-callback/recovery?auth_flow=signup&code=abc',
          ),
        ),
        isTrue,
        reason: 'query values do not override the fixed flow path',
      );
      expect(
        AuthCallbackUriPolicy.isProcessableEmailAuthCallback(
          Uri.parse(
            'com.poyutsai.vibesync://email-callback/wrong?code=abc',
          ),
        ),
        isFalse,
      );
      expect(
        AuthCallbackUriPolicy.isProcessableEmailAuthCallback(
          Uri.parse('com.poyutsai.vibesync://login-callback?code=abc'),
        ),
        isFalse,
      );
      expect(
        AuthCallbackUriPolicy.isProcessableEmailAuthCallback(
          Uri.parse(
            'com.poyutsai.vibesync://email-callback:443/recovery?code=abc',
          ),
        ),
        isFalse,
      );
    });

    test('classifies only exact Email flow paths', () {
      expect(
        AuthCallbackUriPolicy.emailAuthFlow(
          Uri.parse(
            'com.poyutsai.vibesync://email-callback/recovery?code=abc',
          ),
        ),
        EmailAuthFlow.recovery,
      );
      expect(
        AuthCallbackUriPolicy.emailAuthFlow(
          Uri.parse(
            'com.poyutsai.vibesync://email-callback/signup?code=abc',
          ),
        ),
        EmailAuthFlow.signup,
      );
      for (final uri in [
        'com.poyutsai.vibesync://email-callback?code=abc',
        'com.poyutsai.vibesync://email-callback/unknown?code=abc',
        'com.poyutsai.vibesync://email-callback/recovery/extra?code=abc',
      ]) {
        expect(
          AuthCallbackUriPolicy.emailAuthFlow(
            Uri.parse(uri),
          ),
          isNull,
          reason: 'invalid flow path must fail closed: $uri',
        );
      }
    });

    test('AppConfig exposes independent Android Email callback', () {
      expect(AppConfig.authEmailRedirectUri, contains('email-callback'));
      expect(AppConfig.authRedirectUri, contains('login-callback'));
    });
  });
}
