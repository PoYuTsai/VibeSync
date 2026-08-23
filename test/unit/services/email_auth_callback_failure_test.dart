import 'dart:async';

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
        flow: EmailAuthFlow.recovery,
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
        flow: EmailAuthFlow.signup,
      );
      final event = store.events.first;

      store.publish(failure);

      expect(await event, same(failure));
      expect(store.pending, same(failure));
      store.clear();
      expect(store.pending, isNull);
    });
  });

  test('serial callback processing waits for accepted work before failures',
      () async {
    final order = <String>[];
    final publishedFailures = <String>[];
    final releaseAccepted = Completer<void>();
    final acceptance = EmailAuthCallbackAcceptanceGate();
    final processor = EmailAuthCallbackSerialProcessor((uri) async {
      if (uri.path == '/signup') {
        order.add('signup:start');
        acceptance.markAccepted();
        await releaseAccepted.future;
        order.add('signup:end');
        return;
      }
      order.add('recovery:failure');
      if (acceptance.shouldPublishFailure) {
        publishedFailures.add(uri.path);
      }
    });

    final accepted = processor.enqueue(
      Uri.parse('com.poyutsai.vibesync://email-callback/signup?code=ok'),
    );
    final staleFailure = processor.enqueue(
      Uri.parse(
        'com.poyutsai.vibesync://email-callback/recovery?error=expired',
      ),
    );

    await Future<void>.delayed(Duration.zero);
    expect(order, ['signup:start']);
    expect(publishedFailures, isEmpty);

    releaseAccepted.complete();
    await accepted;
    await staleFailure;
    expect(order, ['signup:start', 'signup:end', 'recovery:failure']);
    expect(publishedFailures, isEmpty);

    acceptance.reset();
    await processor.enqueue(
      Uri.parse(
        'com.poyutsai.vibesync://email-callback/recovery?error=expired',
      ),
    );
    expect(publishedFailures, ['/recovery']);
  });

  group('EmailAuthCallbackFailureClassifier', () {
    test('classifies expired recovery callback without retaining raw data', () {
      final failure = EmailAuthCallbackFailureClassifier.fromCallback(
        Uri.parse(
          'com.poyutsai.vibesync://email-callback/recovery?error_code=otp_expired&email=private@example.com',
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
          'com.poyutsai.vibesync://email-callback/signup?error=access_denied',
        ),
      );

      expect(failure.kind, EmailAuthCallbackFailureKind.denied);
      expect(failure.isPasswordRecovery, isFalse);
    });

    test('classifies a malformed callback as retryable without raw error', () {
      final failure = EmailAuthCallbackFailureClassifier.fromCallback(
        Uri.parse('com.poyutsai.vibesync://email-callback/recovery'),
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
          'com.poyutsai.vibesync://email-callback/recovery?error=invalid_grant&error_code=otp_expired',
        ),
      );

      expect(failure, isNotNull);
      expect(failure!.flow, EmailAuthFlow.recovery);
      expect(failure.isPasswordRecovery, isTrue);
    });

    test('unknown, missing, or extra flow paths publish no failure', () {
      for (final query in [
        'com.poyutsai.vibesync://email-callback?error=access_denied',
        'com.poyutsai.vibesync://email-callback/unknown?error=access_denied',
        'com.poyutsai.vibesync://email-callback/signup/recovery?error=access_denied',
      ]) {
        expect(
          EmailAuthCallbackFailureClassifier.tryFromCallback(
            Uri.parse(query),
          ),
          isNull,
          reason: 'flow path must fail closed: $query',
        );
      }
      expect(
        EmailAuthCallbackFailureClassifier.tryFromCallback(
          Uri.parse(
            'com.poyutsai.vibesync://email-callback/recovery?auth_flow=signup&type=signup&error=access_denied',
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
            'com.poyutsai.vibesync://email-callback/signup?code=accepted-code',
          ),
        ),
        isTrue,
      );
      expect(
        AppConfig.authEmailSignupRedirectUri,
        endsWith('/signup'),
      );
      expect(
        AppConfig.authEmailRecoveryRedirectUri,
        endsWith('/recovery'),
      );
    });
  });

  group('EmailAuthCallbackFailureMessage', () {
    test('presentation state keeps callback retry after empty-email validation',
        () {
      const failure = EmailAuthCallbackFailure(
        kind: EmailAuthCallbackFailureKind.expired,
        flow: EmailAuthFlow.recovery,
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
            flow: EmailAuthFlow.recovery,
          ),
        ),
        allOf(contains('重設密碼'), contains('重新寄送')),
      );
      expect(
        EmailAuthCallbackFailureMessage.retryLabel(
          const EmailAuthCallbackFailure(
            kind: EmailAuthCallbackFailureKind.denied,
            flow: EmailAuthFlow.signup,
          ),
        ),
        contains('驗證信'),
      );
    });

    test('signup failure survives resend failure and clears on success', () {
      const failure = EmailAuthCallbackFailure(
        kind: EmailAuthCallbackFailureKind.denied,
        flow: EmailAuthFlow.signup,
      );

      var state = EmailAuthCallbackRetryState.fromFailure(failure);
      state = state.requestStarted();
      state = state.requestFailed('重新寄送驗證信失敗，請再試一次。');
      expect(state.failure, same(failure));
      expect(state.errorMessage, contains('重新寄送驗證信失敗'));

      state = state.requestSucceeded('驗證信已重新寄出。');
      expect(state.failure, isNull);
      expect(state.noticeMessage, '驗證信已重新寄出。');
    });

    test('recovery failure survives reset failure and clears on success', () {
      const failure = EmailAuthCallbackFailure(
        kind: EmailAuthCallbackFailureKind.expired,
        flow: EmailAuthFlow.recovery,
      );

      var state = EmailAuthCallbackRetryState.fromFailure(failure);
      state = state.requestStarted();
      state = state.requestFailed('寄送重設密碼信失敗，請再試一次。');
      expect(state.failure, same(failure));
      expect(state.errorMessage, contains('寄送重設密碼信失敗'));

      state = state.requestSucceeded('重設密碼信已重新寄出。');
      expect(state.failure, isNull);
      expect(state.noticeMessage, '重設密碼信已重新寄出。');
    });
  });

  group('EmailAuthRetryVisibilityPolicy', () {
    test(
      'callback failure owns retry region over matching or blank pending email',
      () {
        expect(
          EmailAuthRetryVisibilityPolicy.showPendingVerificationResend(
            pendingEmail: 'pending@example.com',
            typedEmail: '',
            hasCallbackFailure: true,
          ),
          isFalse,
        );
        expect(
          EmailAuthRetryVisibilityPolicy.showPendingVerificationResend(
            pendingEmail: 'pending@example.com',
            typedEmail: 'pending@example.com',
            hasCallbackFailure: true,
          ),
          isFalse,
        );
      },
    );

    test('pending verification remains visible without callback failure', () {
      expect(
        EmailAuthRetryVisibilityPolicy.showPendingVerificationResend(
          pendingEmail: 'pending@example.com',
          typedEmail: '',
          hasCallbackFailure: false,
        ),
        isTrue,
      );
      expect(
        EmailAuthRetryVisibilityPolicy.showPendingVerificationResend(
          pendingEmail: 'pending@example.com',
          typedEmail: 'pending@example.com',
          hasCallbackFailure: false,
        ),
        isTrue,
      );
    });
  });
}
