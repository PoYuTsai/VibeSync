import 'package:supabase_flutter/supabase_flutter.dart';

class AuthRecoveryHelper {
  static Uri normalizeAuthCallbackUri(Uri uri) {
    final normalizedRaw = uri.hasQuery
        ? uri.toString().replaceAll('#', '&')
        : uri.toString().replaceAll('#', '?');
    return Uri.parse(normalizedRaw);
  }

  static bool isPasswordRecoveryLink(Uri? uri) {
    if (uri == null) {
      return false;
    }

    final normalizedUri = normalizeAuthCallbackUri(uri);
    return normalizedUri.queryParameters['type'] == 'recovery';
  }

  static bool nextPasswordRecoveryState({
    required AuthChangeEvent event,
    required bool currentState,
  }) {
    switch (event) {
      case AuthChangeEvent.passwordRecovery:
        return true;
      case AuthChangeEvent.signedIn:
      case AuthChangeEvent.signedOut:
        return false;
      default:
        return currentState;
    }
  }
}
