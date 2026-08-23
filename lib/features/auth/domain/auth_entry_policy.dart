enum AuthEntryPoint { google, email, apple }

/// Product-level ordering and copy for native authentication entry points.
///
/// Keeping this policy platform-aware and UI-independent makes the Android
/// primary/secondary distinction testable without pretending a desktop test
/// runner is an Android device.
class AuthEntryPolicy {
  const AuthEntryPolicy._({
    required this.primaryEntries,
    required this.secondaryEntries,
    required this.appleLabel,
  });

  factory AuthEntryPolicy.forPlatform({
    required bool isAndroid,
    required bool isIOS,
  }) {
    if (isAndroid) {
      return const AuthEntryPolicy._(
        primaryEntries: [AuthEntryPoint.google, AuthEntryPoint.email],
        secondaryEntries: [AuthEntryPoint.apple],
        appleLabel: '已有 iPhone VibeSync 帳號？使用 Apple 繼續',
      );
    }

    if (isIOS) {
      return const AuthEntryPolicy._(
        primaryEntries: [AuthEntryPoint.google, AuthEntryPoint.apple],
        secondaryEntries: [],
        appleLabel: '使用 Apple 繼續',
      );
    }

    return const AuthEntryPolicy._(
      primaryEntries: [AuthEntryPoint.email],
      secondaryEntries: [],
      appleLabel: '使用 Apple 繼續',
    );
  }

  final List<AuthEntryPoint> primaryEntries;
  final List<AuthEntryPoint> secondaryEntries;
  final String appleLabel;
}
