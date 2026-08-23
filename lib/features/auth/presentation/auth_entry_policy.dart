import 'package:flutter/foundation.dart' show TargetPlatform;

enum AuthEntryPlatform {
  android,
  ios,
  web,
  other;

  static AuthEntryPlatform fromRuntime(
    TargetPlatform platform, {
    required bool isWeb,
  }) {
    if (isWeb) return AuthEntryPlatform.web;

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

enum AuthEntryPoint { google, apple }

/// Presentation policy for the native authentication entry points.
///
/// The lists are the rendered roles: Android keeps Google and Email primary
/// and places Apple in a continuity-only secondary slot, while iOS preserves
/// its existing Google-then-Apple primary order.
class AuthEntryPolicy {
  const AuthEntryPolicy._({
    required this.primarySocialEntries,
    required this.showEmailPrimary,
    required this.secondarySocialEntries,
    required this.appleLabel,
  });

  factory AuthEntryPolicy.forPlatform(AuthEntryPlatform platform) {
    switch (platform) {
      case AuthEntryPlatform.android:
        return const AuthEntryPolicy._(
          primarySocialEntries: [AuthEntryPoint.google],
          showEmailPrimary: true,
          secondarySocialEntries: [AuthEntryPoint.apple],
          appleLabel: '已有 iPhone VibeSync 帳號？使用 Apple 繼續',
        );
      case AuthEntryPlatform.ios:
        return const AuthEntryPolicy._(
          primarySocialEntries: [AuthEntryPoint.google, AuthEntryPoint.apple],
          showEmailPrimary: true,
          secondarySocialEntries: [],
          appleLabel: '使用 Apple 繼續',
        );
      case AuthEntryPlatform.web:
      case AuthEntryPlatform.other:
        return const AuthEntryPolicy._(
          primarySocialEntries: [],
          showEmailPrimary: true,
          secondarySocialEntries: [],
          appleLabel: '使用 Apple 繼續',
        );
    }
  }

  /// Social entries rendered in the primary social region, in order.
  final List<AuthEntryPoint> primarySocialEntries;

  /// Whether the independent Email form is rendered as the primary Email
  /// region. Email is deliberately not represented as a social entry.
  final bool showEmailPrimary;

  /// Social entries rendered in the secondary region, in order.
  final List<AuthEntryPoint> secondarySocialEntries;

  final String appleLabel;
}
