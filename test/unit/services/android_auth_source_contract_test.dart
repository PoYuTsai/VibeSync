import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../android/android_contract_helpers.dart';

void main() {
  test('Android UI exposes Google, Email, and a clearly secondary Apple entry',
      () {
    final source = readRepoFile(
      'lib/features/auth/presentation/screens/login_screen.dart',
    );

    expect(source, contains('AuthEntryPlatform.fromRuntime'));
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
    expect(
      source,
      contains('emailRedirectTo: AppConfig.authEmailSignupRedirectUri'),
    );
    expect(
      source,
      contains('redirectTo: AppConfig.authEmailRecoveryRedirectUri'),
    );
    expect(
      source,
      isNot(contains('emailRedirectTo: AppConfig.authEmailRedirectUri')),
    );
  });

  test('Email deep links disable permissive auto handling and use the gate',
      () {
    final source = readRepoFile('lib/core/services/supabase_service.dart');
    expect(source, contains('detectSessionInUri: kIsWeb'));
    expect(source, contains('_appLinks.uriLinkStream'));
    expect(source, contains('.asyncMap(_emailCallbackProcessor.enqueue)'));
    expect(source, isNot(contains('unawaited(_handleIncomingAuthLink')));
    expect(
      source,
      contains('AuthCallbackUriPolicy.isProcessableEmailAuthCallback(uri)'),
    );
    expect(source, contains('_emailCallbackAcceptance.shouldPublishFailure'));
    expect(source, contains('_emailCallbackAcceptance.markAccepted()'));
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
    final policy = readRepoFile(
      'lib/features/auth/presentation/auth_cancellation_policy.dart',
    );
    expect(source, contains('AuthCancellationPolicy.isCancellation(e)'));
    expect(source, isNot(contains('_isCancellationError')));
    expect(source, contains('finally'));
    expect(source, contains('setState(() => _isLoading = false)'));
    expect(policy, contains('PlatformException'));
    expect(policy, contains('AuthException'));
    expect(policy, contains('AuthorizationErrorCode.canceled'));
    expect(policy, isNot(contains('toString')));
    expect(
      File('lib/features/auth/domain/auth_cancellation_policy.dart')
          .existsSync(),
      isFalse,
    );
  });

  test('entry policy drives rendered primary and secondary entries', () {
    final source = readRepoFile(
      'lib/features/auth/presentation/screens/login_screen.dart',
    );
    expect(source, contains('entryPolicy.primarySocialEntries'));
    expect(source, contains('entryPolicy.showEmailPrimary'));
    expect(source, contains('entryPolicy.secondarySocialEntries'));
    expect(source, contains('AuthEntryPlatform.fromRuntime'));
    expect(source, contains('kIsWeb'));
    expect(source,
        isNot(contains('.where((entry) => entry != AuthEntryPoint.email)')));
    expect(source, isNot(contains('_isAndroid')));
    expect(source, isNot(contains('_isIOS')));
  });

  test('Email callback failures use a buffered typed state, not auth errors',
      () {
    final source = readRepoFile('lib/core/services/supabase_service.dart');
    final login = readRepoFile(
      'lib/features/auth/presentation/screens/login_screen.dart',
    );

    expect(source, contains('EmailAuthCallbackFailureStore'));
    expect(source, contains('pendingEmailAuthCallbackFailure'));
    expect(source, contains('emailAuthCallbackFailureChanges'));
    expect(source, contains('AuthCallbackUriPolicy.emailAuthFlow(uri)'));
    expect(
        source, contains('EmailAuthCallbackFailureClassifier.tryFromCallback'));
    expect(source, contains('EmailAuthCallbackAcceptanceGate'));
    expect(source, isNot(contains('notifyException')));
    expect(source, isNot(contains("queryParameters['type']")));
    expect(login, contains('pendingEmailAuthCallbackFailure'));
    expect(login, contains('emailAuthCallbackFailureChanges'));
    expect(login, contains('EmailAuthCallbackFailureMessage'));
  });

  test(
      'callback failure handler is passive and retry validation preserves state',
      () {
    final source = readRepoFile(
      'lib/features/auth/presentation/screens/login_screen.dart',
    );
    final handler = RegExp(
      r'void _handleEmailAuthCallbackFailure\([\s\S]*?\n  }',
    ).firstMatch(source)?.group(0);
    expect(handler, isNotNull);
    expect(handler, isNot(contains('_isLoading')));
    expect(handler, isNot(contains('_isSignUp')));
    expect(handler, isNot(contains('_isPasswordRecoveryMode')));
    expect(source, contains('_setEmailCallbackRetryValidationError'));
    expect(source, contains('_setEmailCallbackRetryFailureError'));
    expect(source, contains('_beginEmailCallbackRetry'));
    expect(source, contains('EmailAuthCallbackRetryState'));
    expect(source, contains('if (!_isValidEmail(email))'));
  });

  test('Email callback failure accepts only a required typed flow', () {
    final source = readRepoFile(
      'lib/core/services/email_auth_callback_failure.dart',
    );
    expect(source, contains('required this.flow'));
    expect(source, isNot(contains('bool? isPasswordRecovery')));
    expect(source, contains('EmailAuthCallbackSerialProcessor'));
  });

  test('Email redirect builder keeps Web bare and native paths distinct', () {
    final source = readRepoFile('lib/core/config/environment.dart');
    expect(source, contains('emailAuthRedirectUriFor'));
    expect(source, contains('required bool isWeb'));
    expect(source, contains("return _bareWebLoginRedirectUri(base)"));
    expect(source, contains(r".replace(path: '/${flow.path}')"));
  });

  test('signed out and explicit sign out clear buffered Email failures', () {
    final source = readRepoFile('lib/core/services/supabase_service.dart');
    expect(source, contains('AuthChangeEvent.signedOut'));
    expect(source, contains('clearEmailAuthCallbackFailure();'));
    expect(source, contains('_emailCallbackAcceptance.reset();'));
    final signedOut = RegExp(
      r'if \(authState.event == AuthChangeEvent.signedOut\) \{[\s\S]*?\n    \}',
    ).firstMatch(source)?.group(0);
    expect(signedOut, isNotNull);
    expect(signedOut, contains('_emailCallbackAcceptance.reset();'));
    final signOut = RegExp(
      r'static Future<void> signOut\(\) async \{[\s\S]*?\n  }',
    ).firstMatch(source)?.group(0);
    expect(signOut, isNotNull);
    expect(signOut, contains('clearEmailAuthCallbackFailure();'));
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
    expect(docs, contains('com.poyutsai.vibesync://email-callback/signup'));
    expect(docs, contains('com.poyutsai.vibesync://email-callback/recovery'));
    expect(docs, isNot(contains('auth_flow=')));
    expect(docs, contains('signInWithIdToken'));
  });

  test('manifest gate treats leading wildcard hosts as possible owners', () {
    final gate = readRepoFile('tools/android/assert-merged-manifest.py');

    expect(gate, contains('def host_may_match'));
    expect(gate, contains("pattern.startswith('*')"));
    expect(gate, contains('def assert_filter_contract(filters'));
    expect(gate, isNot(contains('def assert_filter_contract(component')));
  });
}
