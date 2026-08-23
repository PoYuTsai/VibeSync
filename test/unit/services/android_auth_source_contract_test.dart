import 'package:flutter_test/flutter_test.dart';

import '../android/android_contract_helpers.dart';

void main() {
  test('Android UI exposes Google, Email, and a clearly secondary Apple entry',
      () {
    final source = readRepoFile(
      'lib/features/auth/presentation/screens/login_screen.dart',
    );

    expect(source, contains('AuthEntryPlatform.fromTargetPlatform'));
    expect(source, contains('AuthEntryPolicy'));
    expect(
      readRepoFile('lib/features/auth/presentation/auth_entry_policy.dart'),
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

  test('recovery state is driven by accepted auth events, not raw links', () {
    final source = readRepoFile('lib/core/services/supabase_service.dart');
    expect(source, contains('AuthRecoveryHelper.nextPasswordRecoveryState'));
    expect(source, isNot(contains('isPasswordRecoveryLink(')));
    expect(
        source, isNot(contains('_syncPasswordRecoveryStateFromInitialLink')));
  });

  test('OAuth cancellation uses typed policy and always clears loading', () {
    final source = readRepoFile(
      'lib/features/auth/presentation/screens/login_screen.dart',
    );
    expect(source, contains('AuthCancellationPolicy.isCancellation(e)'));
    expect(source, isNot(contains('_isCancellationError')));
    expect(source, contains('finally'));
    expect(source, contains('setState(() => _isLoading = false)'));
  });

  test('entry policy drives rendered primary and secondary entries', () {
    final source = readRepoFile(
      'lib/features/auth/presentation/screens/login_screen.dart',
    );
    expect(source, contains('entryPolicy.primaryEntries'));
    expect(source, contains('entryPolicy.secondaryEntries'));
    expect(source, contains('AuthEntryPlatform.fromTargetPlatform'));
    expect(source, isNot(contains('_isAndroid')));
    expect(source, isNot(contains('_isIOS')));
  });

  test('Apple runbook preserves ordered client ID audiences and URL layers',
      () {
    final docs = readRepoFile('docs/integrations/auth.md');
    expect(
        docs,
        contains(
            '[Services ID first, com.poyutsai.vibesync native App ID later]'));
    expect(docs, contains('M2 external pending'));
    expect(docs, contains('Supabase HTTPS callback'));
    expect(docs, contains('App custom redirect'));
    expect(docs, contains('signInWithIdToken'));
  });
}
