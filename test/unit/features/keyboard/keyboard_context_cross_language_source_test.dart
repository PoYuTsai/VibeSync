import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final swiftEnvelope = File('ios/SharedKeyboard/KeyboardContextEnvelope.swift')
      .readAsStringSync();
  final dartSnapshot = File(
          'lib/features/keyboard/domain/entities/keyboard_context_snapshot.dart')
      .readAsStringSync();

  test('partner voice wire omits timestamp on both Dart and Swift sides', () {
    expect(dartSnapshot, contains('Map<String, Object?> toPartnerJson()'));
    expect(swiftEnvelope, contains('struct KeyboardPartnerVoice'));
    expect(
      swiftEnvelope,
      contains('var effectiveVoice: KeyboardPartnerVoice?'),
    );
  });

  test('data-quality status uses the same canonical wire value', () {
    expect(dartSnapshot, contains("'data_quality_flagged'"));
    expect(
      swiftEnvelope,
      contains('dataQualityFlagged = "data_quality_flagged"'),
    );
  });
}
