import 'package:flutter/foundation.dart' show TargetPlatform;

enum AuthEntryPlatform {
  android,
  ios,
  other;

  static AuthEntryPlatform fromTargetPlatform(TargetPlatform platform) {
    switch (platform) {
      case TargetPlatform.android:
        return AuthEntryPlatform.android;
      case TargetPlatform.iOS:
        return AuthEntryPlatform.ios;
      default:
        return AuthEntryPlatform.other;
    }
  }
}

enum AuthEntryPoint { google, email, apple }

/// Presentation policy for the native authentication entry points.
///
/// The lists are the rendered roles: Android keeps Google and Email primary
/// and places Apple in a continuity-only secondary slot, while iOS preserves
/// its existing Google-then-Apple primary order.
class AuthEntryPolicy {
  const AuthEntryPolicy._({
    required this.primaryEntries,
    required this.secondaryEntries,
    required this.appleLabel,
  });

  factory AuthEntryPolicy.forPlatform(AuthEntryPlatform platform) {
    switch (platform) {
      case AuthEntryPlatform.android:
        return const AuthEntryPolicy._(
          primaryEntries: [AuthEntryPoint.google, AuthEntryPoint.email],
          secondaryEntries: [AuthEntryPoint.apple],
          appleLabel: '已有 iPhone VibeSync 帳號？使用 Apple 繼續',
        );
      case AuthEntryPlatform.ios:
        return const AuthEntryPolicy._(
          primaryEntries: [AuthEntryPoint.google, AuthEntryPoint.apple],
          secondaryEntries: [],
          appleLabel: '使用 Apple 繼續',
        );
      case AuthEntryPlatform.other:
        return const AuthEntryPolicy._(
          primaryEntries: [AuthEntryPoint.email],
          secondaryEntries: [],
          appleLabel: '使用 Apple 繼續',
        );
    }
  }

  final List<AuthEntryPoint> primaryEntries;
  final List<AuthEntryPoint> secondaryEntries;
  final String appleLabel;
}
