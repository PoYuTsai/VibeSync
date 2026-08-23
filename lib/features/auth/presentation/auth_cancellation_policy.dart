import 'package:flutter/services.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum AuthCancellationKind { userCancelled }

/// Classifies cancellation at the integration boundary where provider error
/// types are available.  Presentation may keep cancellation quiet while all
/// other provider failures remain visible to the user.
class AuthCancellationPolicy {
  const AuthCancellationPolicy._();

  static AuthCancellationKind? classify(Object error) {
    if (error is PlatformException && error.code.toLowerCase() == 'canceled') {
      return AuthCancellationKind.userCancelled;
    }

    if (error is AuthException &&
        (error.code ?? '').toLowerCase() == 'access_denied') {
      return AuthCancellationKind.userCancelled;
    }

    if (error is SignInWithAppleAuthorizationException &&
        error.code == AuthorizationErrorCode.canceled) {
      return AuthCancellationKind.userCancelled;
    }

    return null;
  }

  static bool isCancellation(Object error) => classify(error) != null;
}
