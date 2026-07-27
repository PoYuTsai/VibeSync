import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source =
      File('ios/VibeSyncKeyboard/KeyboardAssistAPI.swift').readAsStringSync();

  test('an undecodable 2xx keeps the request identity for status lookup', () {
    expect(source, contains('decodeSuccessResponse'));
    final decoderStart = source.indexOf('static func decodeSuccessResponse(');
    final decoderEnd = source.indexOf(
      'static func decodeCapabilityResponse',
      decoderStart,
    );
    final decoder = source.substring(decoderStart, decoderEnd);

    expect(decoder, contains('.failure(.transportUncertain)'));
    expect(decoder, isNot(contains('.failure(.invalidResponse)')));
  });

  test('a missing HTTP response also keeps the request identity', () {
    final responseStart = source.indexOf(
      'private func start(',
    );
    final responseGuardStart = source.indexOf(
      'guard let http = response as? HTTPURLResponse',
      responseStart,
    );
    final successStart = source.indexOf(
      'if (200..<300).contains(http.statusCode)',
      responseGuardStart,
    );
    final responseGuard = source.substring(
      responseGuardStart,
      successStart,
    );

    expect(responseGuard, contains('.failure(.transportUncertain)'));
    expect(responseGuard, isNot(contains('.failure(.invalidResponse)')));
  });

  test('client timeout stays outside the 40 second server fence', () {
    expect(source, contains('request.timeoutInterval = 45'));
  });

  test('state machine has an explicit same-request lookup recovery state', () {
    final stateSource = File('ios/VibeSyncKeyboard/KeyboardAssistState.swift')
        .readAsStringSync();

    expect(stateSource, contains('case lookingUpStatus'));
    expect(stateSource, contains('case statusLookupStarted'));
    expect(stateSource, contains('networkResponseBinding'));
  });

  test('legacy invalidation releases its generating lock', () {
    final controller = File(
      'ios/VibeSyncKeyboard/KeyboardViewController.swift',
    ).readAsStringSync();
    final start = controller.indexOf(
      'private func invalidatePendingReply()',
    );
    final end = controller.indexOf(
      'private func updatePreferredHeight()',
      start,
    );
    final invalidation = controller.substring(start, end);

    expect(invalidation, contains('activeLegacyOperationID = nil'));
    expect(invalidation, contains('isGenerating = false'));
  });
}
