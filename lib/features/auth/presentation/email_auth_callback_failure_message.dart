import '../../../core/services/email_auth_callback_failure.dart';

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
