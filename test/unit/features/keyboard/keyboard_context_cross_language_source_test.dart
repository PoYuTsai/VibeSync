import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final swiftEnvelope = File('ios/SharedKeyboard/KeyboardContextEnvelope.swift')
      .readAsStringSync();
  final swiftAssistContracts =
      File('ios/SharedKeyboard/KeyboardAssistContracts.swift')
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

  test('DecodingError keyNotFound uses concrete Swift CodingKeys', () {
    final directShorthand = RegExp(
      r'DecodingError\.keyNotFound\(\s*\.[A-Za-z_]\w*',
      multiLine: true,
    );
    final shorthandTernary = RegExp(
      r'DecodingError\.keyNotFound\([\s\S]{0,160}'
      r'\?\s*\.[A-Za-z_]\w*\s*:\s*\.[A-Za-z_]\w*',
      multiLine: true,
    );
    const multilineRegressionFixture = '''
throw DecodingError.keyNotFound(
    .uncertainty,
    context
)
throw DecodingError.keyNotFound(
    hasPrimary ? .secondary : .primary,
    context
)
''';

    expect(
      directShorthand.allMatches(multilineRegressionFixture),
      hasLength(1),
    );
    expect(
      shorthandTernary.allMatches(multilineRegressionFixture),
      hasLength(1),
    );

    for (final entry in {
      'KeyboardContextEnvelope.swift': swiftEnvelope,
      'KeyboardAssistContracts.swift': swiftAssistContracts,
    }.entries) {
      expect(
        directShorthand.allMatches(entry.value),
        isEmpty,
        reason: '${entry.key} must qualify keyNotFound keys because Swift 6 '
            'cannot infer enum cases from the any CodingKey existential.',
      );
      expect(
        shorthandTernary.allMatches(entry.value),
        isEmpty,
        reason: '${entry.key} must type keyNotFound ternaries as CodingKeys.',
      );
    }
  });
}
