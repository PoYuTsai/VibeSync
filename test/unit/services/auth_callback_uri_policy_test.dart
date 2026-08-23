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

    test('accepts Email confirmation, resend, and recovery callbacks only', () {
      for (final type in ['signup', 'recovery']) {
        expect(
          AuthCallbackUriPolicy.isEmailCallback(
            Uri.parse(
                'com.poyutsai.vibesync://email-callback?type=$type&code=abc'),
          ),
          isTrue,
        );
      }
      expect(
        AuthCallbackUriPolicy.isEmailCallback(
          Uri.parse('com.poyutsai.vibesync://email-callback?code=abc'),
        ),
        isTrue,
      );
      expect(
        AuthCallbackUriPolicy.isEmailCallback(
          Uri.parse(
              'com.poyutsai.vibesync://login-callback?type=recovery&code=abc'),
        ),
        isFalse,
      );
      expect(
        AuthCallbackUriPolicy.isEmailCallback(
          Uri.parse('com.poyutsai.vibesync://email-callback/wrong?code=abc'),
        ),
        isFalse,
      );
    });

    test('processes only exact Email callbacks carrying an auth result', () {
      expect(
        AuthCallbackUriPolicy.isProcessableEmailAuthCallback(
          Uri.parse(
            'com.poyutsai.vibesync://email-callback?type=recovery&code=abc',
          ),
        ),
        isTrue,
      );
      expect(
        AuthCallbackUriPolicy.isProcessableEmailAuthCallback(
          Uri.parse(
            'com.poyutsai.vibesync://email-callback?error_description=expired',
          ),
        ),
        isTrue,
      );
      expect(
        AuthCallbackUriPolicy.isProcessableEmailAuthCallback(
          Uri.parse('com.poyutsai.vibesync://email-callback?type=recovery'),
        ),
        isFalse,
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
            'com.poyutsai.vibesync://email-callback:443?code=abc',
          ),
        ),
        isFalse,
      );
    });

    test('AppConfig exposes independent Android Email callback', () {
      expect(AppConfig.authEmailRedirectUri, contains('email-callback'));
      expect(AppConfig.authRedirectUri, contains('login-callback'));
    });
  });
}
