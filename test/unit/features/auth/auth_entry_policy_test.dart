import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/auth/presentation/auth_entry_policy.dart';

void main() {
  group('Android auth entry policy', () {
    test(
        'Google is primary social, Email is its own primary region, Apple is secondary',
        () {
      final policy = AuthEntryPolicy.forPlatform(AuthEntryPlatform.android);

      expect(policy.primarySocialEntries, [AuthEntryPoint.google]);
      expect(policy.showEmailPrimary, isTrue);
      expect(policy.secondarySocialEntries, [AuthEntryPoint.apple]);
      expect(policy.appleLabel, contains('已有 iPhone VibeSync 帳號'));
    });

    test('iOS keeps the existing Google then Apple primary order', () {
      final policy = AuthEntryPolicy.forPlatform(AuthEntryPlatform.ios);

      expect(policy.primarySocialEntries,
          [AuthEntryPoint.google, AuthEntryPoint.apple]);
      expect(policy.showEmailPrimary, isTrue);
      expect(policy.secondarySocialEntries, isEmpty);
      expect(policy.appleLabel, '使用 Apple 繼續');
    });

    test('Web exposes Email only and no native social entry', () {
      final policy = AuthEntryPolicy.forPlatform(AuthEntryPlatform.web);

      expect(policy.primarySocialEntries, isEmpty);
      expect(policy.showEmailPrimary, isTrue);
      expect(policy.secondarySocialEntries, isEmpty);
    });

    test('unsupported platforms expose no native social entry', () {
      final policy = AuthEntryPolicy.forPlatform(AuthEntryPlatform.other);

      expect(policy.primarySocialEntries, isEmpty);
      expect(policy.showEmailPrimary, isTrue);
      expect(policy.secondarySocialEntries, isEmpty);
    });

    test('runtime platform maps Web before target platform', () {
      expect(
        AuthEntryPlatform.fromRuntime(
          TargetPlatform.android,
          isWeb: false,
        ),
        AuthEntryPlatform.android,
      );
      expect(
        AuthEntryPlatform.fromRuntime(
          TargetPlatform.iOS,
          isWeb: false,
        ),
        AuthEntryPlatform.ios,
      );
      expect(
        AuthEntryPlatform.fromRuntime(
          TargetPlatform.android,
          isWeb: true,
        ),
        AuthEntryPlatform.web,
      );
      expect(
        AuthEntryPlatform.fromRuntime(
          TargetPlatform.iOS,
          isWeb: true,
        ),
        AuthEntryPlatform.web,
      );
      expect(
        AuthEntryPlatform.fromRuntime(
          TargetPlatform.linux,
          isWeb: false,
        ),
        AuthEntryPlatform.other,
      );
    });
  });
}
