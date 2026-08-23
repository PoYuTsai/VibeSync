import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibesync/core/config/auth_callback_contract.dart';
import 'package:vibesync/core/config/environment.dart';
import 'package:vibesync/core/services/email_auth_callback_failure.dart';
import 'package:vibesync/features/auth/presentation/email_auth_callback_failure_message.dart';

void main() {
  group('EmailAuthCallbackFailureStore', () {
    test('retains a cold-start failure until LoginScreen consumes it', () {
      final store = EmailAuthCallbackFailureStore();
      const failure = EmailAuthCallbackFailure(
        kind: EmailAuthCallbackFailureKind.expired,
        isPasswordRecovery: true,
      );

      store.publish(failure);

      expect(store.pending, same(failure));
      expect(store.consume(), same(failure));
      expect(store.pending, isNull);
    });

    test('publishes live failures and clears stale state after success',
        () async {
      final store = EmailAuthCallbackFailureStore();
      const failure = EmailAuthCallbackFailure(
        kind: EmailAuthCallbackFailureKind.denied,
        isPasswordRecovery: false,
      );
      final event = store.events.first;

      store.publish(failure);

      expect(await event, same(failure));
      expect(store.pending, same(failure));
      store.clear();
      expect(store.pending, isNull);
    });
  });

  group('EmailAuthCallbackFailureClassifier', () {
    test('classifies expired recovery callback without retaining raw data', () {
      final failure = EmailAuthCallbackFailureClassifier.fromCallback(
        Uri.parse(
          'com.poyutsai.vibesync://email-callback?auth_flow=recovery&error_code=otp_expired&email=private@example.com',
        ),
      );

      expect(failure.kind, EmailAuthCallbackFailureKind.expired);
      expect(failure.isPasswordRecovery, isTrue);
      expect(failure.toString(), isNot(contains('private@example.com')));
      expect(failure.toString(), isNot(contains('otp_expired')));
    });

    test('classifies denied confirmation callback', () {
      final failure = EmailAuthCallbackFailureClassifier.fromCallback(
        Uri.parse(
          'com.poyutsai.vibesync://email-callback?auth_flow=signup&error=access_denied',
        ),
      );

      expect(failure.kind, EmailAuthCallbackFailureKind.denied);
      expect(failure.isPasswordRecovery, isFalse);
    });

    test('classifies a malformed callback as retryable without raw error', () {
      final failure = EmailAuthCallbackFailureClassifier.fromCallback(
        Uri.parse('com.poyutsai.vibesync://email-callback?auth_flow=recovery'),
        error: AuthException('raw provider token should not be retained'),
      );

      expect(failure.kind, EmailAuthCallbackFailureKind.malformed);
      expect(failure.isPasswordRecovery, isTrue);
      expect(failure.toString(), isNot(contains('raw provider token')));
    });

    test('uses the recovery marker when Supabase error has no type parameter',
        () {
      final failure = EmailAuthCallbackFailureClassifier.tryFromCallback(
        Uri.parse(
          'com.poyutsai.vibesync://email-callback?auth_flow=recovery&error=invalid_grant&error_code=otp_expired',
        ),
      );

      expect(failure, isNotNull);
      expect(failure!.flow, EmailAuthFlow.recovery);
      expect(failure.isPasswordRecovery, isTrue);
    });

    test('unknown, missing, or duplicate markers publish no failure', () {
      for (final query in [
        'error=access_denied',
        'auth_flow=unknown&error=access_denied',
        'auth_flow=signup&auth_flow=recovery&error=access_denied',
      ]) {
        expect(
          EmailAuthCallbackFailureClassifier.tryFromCallback(
            Uri.parse('com.poyutsai.vibesync://email-callback?$query'),
          ),
          isNull,
          reason: 'marker must fail closed: $query',
        );
      }
      expect(
        EmailAuthCallbackFailureClassifier.tryFromCallback(
          Uri.parse(
            'com.poyutsai.vibesync://email-callback?auth_flow=recovery&type=signup&error=access_denied',
          ),
        ),
        isNotNull,
        reason: 'Supabase type is not callback provenance',
      );
    });

    test('marked successful code callback remains processable', () {
      expect(
        AuthCallbackUriPolicy.isProcessableEmailAuthCallback(
          Uri.parse(
            'com.poyutsai.vibesync://email-callback?auth_flow=signup&code=accepted-code',
          ),
        ),
        isTrue,
      );
      expect(
        AppConfig.authEmailSignupRedirectUri,
        contains('auth_flow=signup'),
      );
      expect(
        AppConfig.authEmailRecoveryRedirectUri,
        contains('auth_flow=recovery'),
      );
    });
  });

  group('EmailAuthCallbackFailureMessage', () {
    test('presentation state keeps callback retry after empty-email validation',
        () {
      const failure = EmailAuthCallbackFailure(
        kind: EmailAuthCallbackFailureKind.expired,
        isPasswordRecovery: true,
      );

      final notice = EmailAuthCallbackFailurePresentationState.fromFailure(
        failure,
      );
      final retry = EmailAuthCallbackFailurePresentationState.retryValidation(
        failure: failure,
        message: '請先輸入有效的 Email 再重設密碼。',
      );

      expect(notice.failure, same(failure));
      expect(notice.errorMessage, contains('重新寄送重設密碼信'));
      expect(retry.failure, same(failure));
      expect(retry.errorMessage, contains('請先輸入有效的 Email'));
      expect(retry.noticeMessage, isNull);
    });

    test('uses actionable Traditional-Chinese retry copy', () {
      expect(
        EmailAuthCallbackFailureMessage.forFailure(
          const EmailAuthCallbackFailure(
            kind: EmailAuthCallbackFailureKind.expired,
            isPasswordRecovery: true,
          ),
        ),
        allOf(contains('重設密碼'), contains('重新寄送')),
      );
      expect(
        EmailAuthCallbackFailureMessage.retryLabel(
          const EmailAuthCallbackFailure(
            kind: EmailAuthCallbackFailureKind.denied,
            isPasswordRecovery: false,
          ),
        ),
        contains('驗證信'),
      );
    });
  });
}
