import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final config =
      File('ios/SharedKeyboard/KeyboardSharedConfig.swift').readAsStringSync();
  final api =
      File('ios/VibeSyncKeyboard/KeyboardAssistAPI.swift').readAsStringSync();
  final photos = File(
    'ios/VibeSyncKeyboard/LatestScreenshotProvider.swift',
  ).readAsStringSync();

  test('extension rollout uses an owner-bound short-lived receipt', () {
    expect(config, contains('KeyboardAssistCapabilityReceipt'));
    expect(config, contains('ownerUserId'));
    expect(config, contains('capabilityReceiptMaximumLifetime'));
    expect(config, isNot(contains('KeyboardFeatureFlags')));
    expect(config, isNot(contains('defaults.bool(')));
  });

  test('API negotiates capability and requires a send authorization', () {
    expect(api, contains('func fetchCapability('));
    expect(api, contains('URLQueryItem(name: "capability", value: "1")'));
    expect(api, contains('authorization: KeyboardAssistSendAuthorization'));
    expect(api, contains('try authorization.validate('));
    expect(api, contains('.reloadIgnoringLocalCacheData'));
  });

  test('photo lookup fails closed before touching PhotoKit', () {
    final capabilityGuard = photos.indexOf(
      'guard capability?.isUsable(',
    );
    final authorizationRead = photos.indexOf(
      'let status = library.authorizationStatus',
    );
    final fetch = photos.indexOf(
      'library.fetchRecentScreenshotCandidates(',
    );

    expect(capabilityGuard, greaterThanOrEqualTo(0));
    expect(authorizationRead, greaterThan(capabilityGuard));
    expect(fetch, greaterThan(authorizationRead));
    expect(photos, contains('options.predicate = NSPredicate('));
    expect(photos, contains('photoScreenshot.rawValue'));
  });
}
