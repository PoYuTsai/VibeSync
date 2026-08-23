import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_recovery_helper.dart';

/// The only callback failure details that may cross the service boundary.
///
/// This intentionally contains no callback URI, token, email address, or
/// provider message.  Those values are inspected only long enough to select a
/// retry category.
enum EmailAuthCallbackFailureKind { expired, denied, malformed }

class EmailAuthCallbackFailure {
  const EmailAuthCallbackFailure({
    required this.kind,
    required this.isPasswordRecovery,
  });

  final EmailAuthCallbackFailureKind kind;
  final bool isPasswordRecovery;

  @override
  String toString() =>
      'EmailAuthCallbackFailure(kind: $kind, recovery: $isPasswordRecovery)';
}

/// Buffers the latest Email callback failure until the presentation layer has
/// mounted.  The pending value covers a cold-start deep link arriving before
/// LoginScreen subscribes; [events] covers callbacks received while mounted.
class EmailAuthCallbackFailureStore {
  EmailAuthCallbackFailureStore()
      : _events = StreamController<EmailAuthCallbackFailure>.broadcast(
          sync: true,
        );

  final StreamController<EmailAuthCallbackFailure> _events;
  EmailAuthCallbackFailure? _pending;

  EmailAuthCallbackFailure? get pending => _pending;

  Stream<EmailAuthCallbackFailure> get events => _events.stream;

  void publish(EmailAuthCallbackFailure failure) {
    _pending = failure;
    _events.add(failure);
  }

  EmailAuthCallbackFailure? consume() {
    final failure = _pending;
    _pending = null;
    return failure;
  }

  void clear() {
    _pending = null;
  }
}

class EmailAuthCallbackFailureClassifier {
  const EmailAuthCallbackFailureClassifier._();

  static EmailAuthCallbackFailure fromCallback(
    Uri callback, {
    Object? error,
  }) {
    final normalized = AuthRecoveryHelper.normalizeAuthCallbackUri(callback);
    final signals = <String>[
      normalized.queryParameters['error'] ?? '',
      normalized.queryParameters['error_code'] ?? '',
      normalized.queryParameters['error_description'] ?? '',
    ];
    if (error is AuthException) {
      signals.add(error.code ?? '');
      signals.add(error.statusCode ?? '');
      signals.add(error.message);
    }

    final signal = signals.join(' ').toLowerCase();
    final kind = signal.contains('expired') || signal.contains('otp_expired')
        ? EmailAuthCallbackFailureKind.expired
        : signal.contains('access_denied') ||
                signal.contains('invalid_grant') ||
                signal.contains('denied')
            ? EmailAuthCallbackFailureKind.denied
            : EmailAuthCallbackFailureKind.malformed;

    return EmailAuthCallbackFailure(
      kind: kind,
      isPasswordRecovery:
          normalized.queryParameters['type']?.toLowerCase() == 'recovery',
    );
  }
}
