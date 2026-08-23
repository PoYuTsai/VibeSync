import '../../../core/services/email_auth_callback_failure.dart';

/// Chooses which Email retry region owns the UI when multiple auth notices
/// are pending. A callback failure is more specific than a stale signup
/// verification reminder, so its dedicated retry must remain visible.
class EmailAuthRetryVisibilityPolicy {
  const EmailAuthRetryVisibilityPolicy._();

  static bool showPendingVerificationResend({
    required String? pendingEmail,
    required String typedEmail,
    required bool hasCallbackFailure,
  }) {
    if (hasCallbackFailure) return false;

    final pending = (pendingEmail ?? '').trim();
    if (pending.isEmpty) return false;

    final typed = typedEmail.trim().toLowerCase();
    return typed.isEmpty || typed == pending.toLowerCase();
  }
}

/// Small lifecycle reducer for the dedicated Email callback retry action.
/// Starting a request and a failed request preserve the callback failure;
/// only a successful resend/reset clears it.
class EmailAuthCallbackRetryState {
  const EmailAuthCallbackRetryState({
    required this.failure,
    required this.errorMessage,
    required this.noticeMessage,
  });

  factory EmailAuthCallbackRetryState.fromFailure(
    EmailAuthCallbackFailure failure,
  ) {
    return EmailAuthCallbackRetryState(
      failure: failure,
      errorMessage: EmailAuthCallbackFailureMessage.forFailure(failure),
      noticeMessage: null,
    );
  }

  final EmailAuthCallbackFailure? failure;
  final String? errorMessage;
  final String? noticeMessage;

  EmailAuthCallbackRetryState requestStarted() {
    return EmailAuthCallbackRetryState(
      failure: failure,
      errorMessage: null,
      noticeMessage: null,
    );
  }

  EmailAuthCallbackRetryState requestFailed(String message) {
    return EmailAuthCallbackRetryState(
      failure: failure,
      errorMessage: message,
      noticeMessage: null,
    );
  }

  EmailAuthCallbackRetryState requestSucceeded(String message) {
    return EmailAuthCallbackRetryState(
      failure: null,
      errorMessage: null,
      noticeMessage: message,
    );
  }
}

/// Immutable presentation state for a callback failure notice.
///
/// Loading and auth-mode state intentionally do not live here: a callback
/// failure is a passive retry hint and must never rewrite an in-flight
/// operation or an accepted Supabase recovery event.
class EmailAuthCallbackFailurePresentationState {
  const EmailAuthCallbackFailurePresentationState({
    required this.failure,
    required this.errorMessage,
    required this.noticeMessage,
  });

  factory EmailAuthCallbackFailurePresentationState.fromFailure(
    EmailAuthCallbackFailure failure,
  ) {
    return EmailAuthCallbackFailurePresentationState(
      failure: failure,
      errorMessage: EmailAuthCallbackFailureMessage.forFailure(failure),
      noticeMessage: null,
    );
  }

  factory EmailAuthCallbackFailurePresentationState.retryValidation({
    required EmailAuthCallbackFailure failure,
    required String message,
  }) {
    return EmailAuthCallbackFailurePresentationState(
      failure: failure,
      errorMessage: message,
      noticeMessage: null,
    );
  }

  final EmailAuthCallbackFailure failure;
  final String? errorMessage;
  final String? noticeMessage;
}

class EmailAuthCallbackFailureMessage {
  const EmailAuthCallbackFailureMessage._();

  static String forFailure(EmailAuthCallbackFailure failure) {
    if (failure.isPasswordRecovery) {
      switch (failure.kind) {
        case EmailAuthCallbackFailureKind.expired:
          return '重設密碼連結已過期，請重新寄送重設密碼信。';
        case EmailAuthCallbackFailureKind.denied:
          return '重設密碼連結未被接受，請重新寄送重設密碼信。';
        case EmailAuthCallbackFailureKind.malformed:
          return '重設密碼連結格式無效，請重新寄送重設密碼信。';
      }
    }

    switch (failure.kind) {
      case EmailAuthCallbackFailureKind.expired:
        return 'Email 驗證連結已過期，請重新寄送驗證信。';
      case EmailAuthCallbackFailureKind.denied:
        return 'Email 驗證連結未被接受，請重新寄送驗證信。';
      case EmailAuthCallbackFailureKind.malformed:
        return 'Email 驗證連結格式無效，請重新寄送驗證信。';
    }
  }

  static String retryLabel(EmailAuthCallbackFailure failure) {
    return failure.isPasswordRecovery ? '重新寄送重設密碼信' : '重新寄送驗證信';
  }
}
