import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/auth_callback_contract.dart';
import '../config/environment.dart';

/// The only callback failure details that may cross the service boundary.
///
/// This intentionally contains no callback URI, token, email address, or
/// provider message.  Those values are inspected only long enough to select a
/// retry category.
enum EmailAuthCallbackFailureKind { expired, denied, malformed }

class EmailAuthCallbackFailure {
  const EmailAuthCallbackFailure({
    required this.kind,
    EmailAuthFlow? flow,
    bool? isPasswordRecovery,
  })  : assert(flow != null || isPasswordRecovery != null),
        flow = flow ??
            (isPasswordRecovery == true
                ? EmailAuthFlow.recovery
                : EmailAuthFlow.signup);

  final EmailAuthCallbackFailureKind kind;
  final EmailAuthFlow flow;

  bool get isPasswordRecovery => flow == EmailAuthFlow.recovery;

  @override
  String toString() => 'EmailAuthCallbackFailure(kind: $kind, flow: $flow)';
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

  static EmailAuthCallbackFailure? tryFromCallback(
    Uri callback, {
    Object? error,
  }) {
    final flow = AuthCallbackUriPolicy.emailAuthFlow(callback);
    if (flow == null) {
      return null;
    }
    return _fromMarkedCallback(callback, flow: flow, error: error);
  }

  static EmailAuthCallbackFailure fromCallback(
    Uri callback, {
    Object? error,
  }) {
    final selectedFlow = AuthCallbackUriPolicy.emailAuthFlow(callback);
    if (selectedFlow == null) {
      throw ArgumentError.value(
        callback,
        'callback',
        'Email callback must carry exactly one supported auth_flow marker',
      );
    }
    return _fromMarkedCallback(callback, flow: selectedFlow, error: error);
  }

  static EmailAuthCallbackFailure _fromMarkedCallback(
    Uri callback, {
    required EmailAuthFlow flow,
    Object? error,
  }) {
    final normalized = _normalize(callback);
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
      flow: flow,
    );
  }

  static Uri _normalize(Uri uri) {
    final normalizedRaw = uri.hasQuery
        ? uri.toString().replaceAll('#', '&')
        : uri.toString().replaceAll('#', '?');
    return Uri.parse(normalizedRaw);
  }
}
