import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final config = File(
    'ios/SharedKeyboard/KeyboardSharedConfig.swift',
  ).readAsStringSync();
  final api = File(
    'ios/VibeSyncKeyboard/KeyboardAssistAPI.swift',
  ).readAsStringSync();
  final pending = File(
    'ios/VibeSyncKeyboard/KeyboardAssistPendingReplay.swift',
  ).readAsStringSync();
  final project = File(
    'ios/Runner.xcodeproj/project.pbxproj',
  ).readAsStringSync();
  final runnerBridge = File(
    'ios/Runner/KeyboardContextBridge.swift',
  ).readAsStringSync();

  test('pending replay metadata is bounded, short lived, and Keychain backed',
      () {
    expect(config, contains('keyboardAssistPendingAccountPrefix'));
    expect(config, contains('"keyboard_assist_pending_"'));
    expect(config, contains('keyboardAssistPendingTTL'));
    expect(config, contains('23 * 60 * 60'));
    expect(config, contains('maximumKeyboardAssistPendingCount'));

    expect(pending, contains('struct KeyboardAssistPendingMetadata'));
    expect(pending, contains('let documentIdentifier: UUID'));
    expect(
      pending,
      contains('final class KeyboardAssistPendingKeychainStorage'),
    );
    expect(pending, contains('KeyboardSharedConfig.keychainService'));
    expect(pending, contains('KeyboardSharedConfig.keychainAccessGroup'));
    expect(
      pending,
      contains('kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly'),
    );
    expect(pending, isNot(contains('struct KeyboardAssistPendingImage')));
    expect(
      'KeyboardAssistPendingReplay.swift in Sources'.allMatches(project).length,
      4,
    );
    expect(
      runnerBridge,
      contains('"keyboard_assist_pending_"'),
    );
  });

  test('POST persists metadata before any network task can be created', () {
    final submit = api.indexOf('func submit(');
    final persist = api.indexOf(
      'pendingReplayStore.persist(',
      submit,
    );
    final start = api.indexOf('return start(', submit);

    expect(submit, greaterThanOrEqualTo(0));
    expect(persist, greaterThan(submit));
    expect(start, greaterThan(persist));
    expect(api, contains('case pendingReplayUnavailable'));
    expect(api, contains('case noPendingReplay'));
  });

  test('restart recovery is owner-bound, image-free GET of the old request',
      () {
    expect(api, contains('func recoverPending('));
    expect(api, contains('func recoverLatestPending('));
    expect(api, contains('struct KeyboardAssistRecoveredPending'));
    expect(api, contains('pendingReplayStore.matching('));
    expect(api, contains('pendingReplayStore.latest('));
    expect(
      api,
      contains('documentIdentifier: UUID,\n        session auth:'),
    );
    expect(api, contains('func clearPendingAfterPresentation('));
    expect(
      api,
      contains('protocol KeyboardAssistPendingPresentationClearing'),
    );
    expect(api, contains('request.httpMethod = "GET"'));
    expect(
      api,
      contains('URLQueryItem(\n                name: "requestId"'),
    );
  });
}
