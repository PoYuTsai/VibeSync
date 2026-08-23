import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/auth/presentation/auth_entry_policy.dart';

void main() {
  group('Android auth entry policy', () {
    test('Google and Email are primary, Apple is secondary', () {
      final policy = AuthEntryPolicy.forPlatform(AuthEntryPlatform.android);

      expect(
          policy.primaryEntries, [AuthEntryPoint.google, AuthEntryPoint.email]);
      expect(policy.secondaryEntries, [AuthEntryPoint.apple]);
      expect(policy.appleLabel, contains('已有 iPhone VibeSync 帳號'));
    });

    test('iOS keeps the existing Google then Apple primary order', () {
      final policy = AuthEntryPolicy.forPlatform(AuthEntryPlatform.ios);

      expect(
          policy.primaryEntries, [AuthEntryPoint.google, AuthEntryPoint.apple]);
      expect(policy.secondaryEntries, isEmpty);
      expect(policy.appleLabel, '使用 Apple 繼續');
    });

    test('unsupported platforms expose no native social entry', () {
      final policy = AuthEntryPolicy.forPlatform(AuthEntryPlatform.other);

      expect(policy.primaryEntries, [AuthEntryPoint.email]);
      expect(policy.secondaryEntries, isEmpty);
    });

    test('TargetPlatform maps to one auth platform value', () {
      expect(
        AuthEntryPlatform.fromTargetPlatform(TargetPlatform.android),
        AuthEntryPlatform.android,
      );
      expect(
        AuthEntryPlatform.fromTargetPlatform(TargetPlatform.iOS),
        AuthEntryPlatform.ios,
      );
      expect(
        AuthEntryPlatform.fromTargetPlatform(TargetPlatform.linux),
        AuthEntryPlatform.other,
      );
    });
  });
}
