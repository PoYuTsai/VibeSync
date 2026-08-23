import 'environment.dart';

/// URI ownership checks shared by native OAuth and Email callback paths.
///
/// The scheme/host values are declared in AppConfig and audited against the
/// machine-readable contract files by Android contract tests and gate scripts.
/// A callback is valid only when it has the exact contract origin and no path;
/// query/fragment data is intentionally left to Supabase Auth to validate.
class AuthCallbackUriPolicy {
  static bool isOAuthCallback(Uri uri) {
    return _matches(uri, AppConfig.authRedirectUri);
  }

  static bool isEmailCallback(Uri uri) {
    return _matches(uri, AppConfig.authEmailRedirectUri);
  }

  /// Returns true only for an exact Email callback carrying a result that
  /// Supabase's PKCE callback parser can consume or reject explicitly.
  ///
  /// Keeping this gate separate from [isEmailCallback] prevents a bare,
  /// early, or malformed deep link from reaching [getSessionFromUrl].
  static bool isProcessableEmailAuthCallback(Uri uri) {
    if (!isEmailCallback(uri)) {
      return false;
    }

    final normalized = uri.hasQuery
        ? uri.toString().replaceAll('#', '&')
        : uri.toString().replaceAll('#', '?');
    final normalizedUri = Uri.tryParse(normalized);
    if (normalizedUri == null) {
      return false;
    }

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

  static bool _matches(Uri uri, String expectedUri) {
    final expected = Uri.parse(expectedUri);
    return uri.scheme == expected.scheme &&
        uri.host == expected.host &&
        uri.port == expected.port &&
        uri.userInfo == expected.userInfo &&
        uri.path == expected.path;
  }
}
