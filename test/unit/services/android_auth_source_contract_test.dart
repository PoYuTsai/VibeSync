import 'package:flutter_test/flutter_test.dart';

import '../android/android_contract_helpers.dart';

void main() {
  test('Android UI exposes Google, Email, and a clearly secondary Apple entry',
      () {
    final source = readRepoFile(
      'lib/features/auth/presentation/screens/login_screen.dart',
    );

    expect(source, contains('isAndroidPlatform'));
    expect(source, contains('AuthEntryPolicy'));
    expect(
      readRepoFile('lib/features/auth/domain/auth_entry_policy.dart'),
      contains('已有 iPhone VibeSync 帳號'),
    );
    expect(source, contains('_signInWithGoogle'));
    expect(source, contains('_signInWithApple'));
  });

  test('Android social auth uses Supabase OAuth for Apple and Google', () {
    final source = readRepoFile(
      'lib/core/services/social_auth/social_auth_native.dart',
    );

    expect(source, contains('isAndroidPlatform'));
    expect(source, contains('OAuthProvider.apple'));
    expect(source, contains('OAuthProvider.google'));
    expect(source, contains('FlutterWebAuth2.authenticate'));
    expect(source, contains('AppConfig.authRedirectUri'));
    expect(source, contains('AuthCallbackUriPolicy.isOAuthCallback'));
  });

  test('iOS retains native Apple token flow', () {
    final source = readRepoFile(
      'lib/core/services/social_auth/social_auth_native.dart',
    );

    expect(source, contains('SignInWithApple.getAppleIDCredential'));
    expect(source, contains('signInWithIdToken'));
    expect(source, contains('provider: OAuthProvider.apple'));
  });

  test('all Android Email auth requests use the Email callback getter', () {
    final source = readRepoFile('lib/core/services/supabase_service.dart');
    expect(source, contains('emailRedirectTo: AppConfig.authEmailRedirectUri'));
    expect(source, contains('redirectTo: AppConfig.authEmailRedirectUri'));
  });

  test('Email deep links disable permissive auto handling and use the gate',
      () {
    final source = readRepoFile('lib/core/services/supabase_service.dart');
    expect(source, contains('detectSessionInUri: kIsWeb'));
    expect(source, contains('_appLinks.uriLinkStream'));
    expect(
      source,
      contains('AuthCallbackUriPolicy.isProcessableEmailAuthCallback(uri)'),
    );
  });
}
