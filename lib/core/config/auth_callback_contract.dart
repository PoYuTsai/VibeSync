import 'environment.dart';

/// URI ownership checks shared by native OAuth and Email callback paths.
///
/// The scheme/host values are declared in AppConfig and audited against the
/// machine-readable contract files by Android contract tests and gate scripts.
/// A callback is valid only when it has the exact contract origin and one of
/// the two fixed Email flow paths. Query/fragment data is intentionally left
/// to Supabase Auth to validate.
class AuthCallbackUriPolicy {
  static bool isOAuthCallback(Uri uri) {
    return _matches(uri, AppConfig.authRedirectUri);
  }

  static bool isEmailCallback(Uri uri) {
    return emailAuthFlow(uri) != null;
  }

  /// Returns one and only one fixed Email flow path. The path is merely retry
  /// provenance; it never authenticates the callback or enters recovery.
  static EmailAuthFlow? emailAuthFlow(Uri uri) {
    if (!_matchesEmailOrigin(uri)) {
      return null;
    }

    switch (uri.path) {
      case '/signup':
        return EmailAuthFlow.signup;
      case '/recovery':
        return EmailAuthFlow.recovery;
      default:
        return null;
    }
  }

  /// Returns true only for an exact Email flow path carrying a result that
  /// Supabase's PKCE callback parser can consume or reject explicitly.
  ///
  /// Keeping this gate separate from [isEmailCallback] prevents a bare,
  /// early, or malformed deep link from reaching [getSessionFromUrl].
  static bool isProcessableEmailAuthCallback(Uri uri) {
    if (emailAuthFlow(uri) == null) {
      return false;
    }

    final normalizedUri = _normalize(uri);

    const resultKeys = {
      'code',
      'error',
      'error_code',
      'error_description',
    };
    return resultKeys.any(
      (key) => (normalizedUri.queryParameters[key] ?? '').trim().isNotEmpty,
    );
  }

  static Uri _normalize(Uri uri) {
    final normalizedRaw = uri.hasQuery
        ? uri.toString().replaceAll('#', '&')
        : uri.toString().replaceAll('#', '?');
    return Uri.tryParse(normalizedRaw) ?? uri;
  }

  static bool _matches(Uri uri, String expectedUri) {
    final expected = Uri.parse(expectedUri);
    return uri.scheme == expected.scheme &&
        uri.host == expected.host &&
        uri.port == expected.port &&
        uri.userInfo == expected.userInfo &&
        uri.path == expected.path;
  }

  static bool _matchesEmailOrigin(Uri uri) {
    final expected = Uri.parse(AppConfig.authEmailRedirectUri);
    return uri.scheme == expected.scheme &&
        uri.host == expected.host &&
        uri.port == expected.port &&
        uri.userInfo == expected.userInfo;
  }
}
