import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The prior turn is one piece of data doing two jobs: it stops the next batch
/// repeating lines the user has already seen, and it lets the server recognise
/// its own candidates being read back out of a screenshot. It must never become
/// a source of facts, and it must never cross into a different conversation.
void main() {
  final contracts = File('ios/SharedKeyboard/KeyboardAssistContracts.swift');
  final coordinator = File(
    'ios/VibeSyncKeyboard/KeyboardScreenshotAssistCoordinator.swift',
  );
  final serverContract = File(
    'supabase/functions/keyboard-assist/contract.ts',
  );
  final compilerPrompt = File(
    'supabase/functions/keyboard-assist/compiler_prompt.ts',
  );
  final billing = File('supabase/functions/keyboard-assist/billing.ts');
  final pipeline = File('supabase/functions/keyboard-assist/pipeline.ts');

  test('the wire shape stays additive and explicitly nullable', () {
    final source = contracts.readAsStringSync();

    expect(source, contains('struct KeyboardAssistPriorTurn'));
    // Absent prior turn keeps the original v1 request byte shape.
    expect(
      source,
      contains('try container.encodeIfPresent(priorTurn, forKey: .priorTurn)'),
    );
    // The server requires both keys inside the object, so nil travels as null.
    expect(
      source,
      contains('try container.encode(insertedText, forKey: .insertedText)'),
    );
    expect(
      serverContract.readAsStringSync(),
      contains('priorTurn: KeyboardAssistPriorTurn | null;'),
    );
  });

  test('a prior turn never crosses into a different conversation', () {
    final source = coordinator.readAsStringSync();
    final start = source.indexOf('func priorTurnForCurrentDocument()');
    expect(start, greaterThanOrEqualTo(0));
    final body = source.substring(start, start + 400);

    expect(body, contains('document == boundDocumentIdentifier'));
    expect(source, contains('priorTurn: priorTurnForCurrentDocument()'));
    // Switching account drops it outright.
    final ownerChanged = source.indexOf('func ownerDidChange()');
    expect(
      source.substring(ownerChanged, ownerChanged + 260),
      contains('priorTurn = nil'),
    );
  });

  test('an invalid hint is dropped rather than shipped', () {
    final source = coordinator.readAsStringSync();
    final start = source.indexOf('private func rememberOffered(');
    expect(start, greaterThanOrEqualTo(0));
    final body = source.substring(start, start + 600);

    expect(body, contains('guard candidate.isValid else'));
    expect(body, contains('priorTurn = nil'));
  });

  test('the hint informs generation without becoming evidence', () {
    expect(
      compilerPrompt.readAsStringSync(),
      contains('不是\n   事實來源'),
      reason: 'Grounding still requires every fact to come from the capture.',
    );
    // The judge only ever sees the normalized transcript.
    expect(
      pipeline.readAsStringSync(),
      contains('priorTurn: input.priorTurn,'),
    );
  });

  test('the replay hash ignores the hint so a safe retry stays safe', () {
    final source = billing.readAsStringSync();

    expect(
      source,
      contains('Deliberately excludes priorTurn'),
      reason: 'A same-payload retry is rebuilt from stored pending metadata, '
          'which cannot reproduce the hint.',
    );
    expect(source, isNot(contains('input.priorTurn')));
  });
}
