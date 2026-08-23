import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
          'com.poyutsai.vibesync://email-callback?type=recovery&error_code=otp_expired&email=private@example.com',
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
          'com.poyutsai.vibesync://email-callback?type=signup&error=access_denied',
        ),
      );

      expect(failure.kind, EmailAuthCallbackFailureKind.denied);
      expect(failure.isPasswordRecovery, isFalse);
    });

    test('classifies a malformed callback as retryable without raw error', () {
      final failure = EmailAuthCallbackFailureClassifier.fromCallback(
        Uri.parse('com.poyutsai.vibesync://email-callback?type=recovery'),
        error: AuthException('raw provider token should not be retained'),
      );

      expect(failure.kind, EmailAuthCallbackFailureKind.malformed);
      expect(failure.isPasswordRecovery, isTrue);
      expect(failure.toString(), isNot(contains('raw provider token')));
    });
  });

  group('EmailAuthCallbackFailureMessage', () {
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
