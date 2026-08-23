import 'package:supabase_flutter/supabase_flutter.dart';

/// Typed handling for user-aborted OAuth attempts.
///
/// The browser callback and the provider SDK do not share one error type:
/// flutter_web_auth_2 reports a platform cancellation while Supabase may
/// report the OAuth `access_denied` callback.  Keep both cases silent and
/// retryable without hiding real provider failures.
enum AuthCancellationKind { userCancelled }

class AuthCancellationPolicy {
  const AuthCancellationPolicy._();

  static AuthCancellationKind? classify(Object error) {
    final code = error is AuthException ? error.code : null;
    final normalized = '${code ?? ''} ${error.toString()}'.toLowerCase();

    if (normalized.contains('access_denied') ||
        normalized.contains('access denied') ||
        normalized.contains('cancelled') ||
        normalized.contains('canceled') ||
        RegExp(r'\bcancel\b').hasMatch(normalized)) {
      return AuthCancellationKind.userCancelled;
    }

    return null;
  }

  static bool isCancellation(Object error) => classify(error) != null;

  static bool shouldShowError(AuthCancellationKind? kind) => kind == null;

  static bool canRetry(AuthCancellationKind? kind) => true;
}
