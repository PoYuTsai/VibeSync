import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The compiler always produced six candidates and the judge used to discard
/// three of them. Serving both batches from one call is what makes "換一批"
/// free: no second request, no second charge.
/// Reading a bounded window after an anchor, without falling off the end of a
/// short file.
String _window(String source, int start, int length) =>
    source.substring(start, (start + length).clamp(0, source.length));

void main() {
  final judgePrompt = File(
    'supabase/functions/keyboard-assist/judge_prompt.ts',
  );
  final serverValidate = File(
    'supabase/functions/keyboard-assist/validate.ts',
  );
  final grounding = File('supabase/functions/keyboard-assist/grounding.ts');
  final contracts = File('ios/SharedKeyboard/KeyboardAssistContracts.swift');
  final binding = File('ios/VibeSyncKeyboard/KeyboardRequestBinding.swift');
  final state = File('ios/VibeSyncKeyboard/KeyboardAssistState.swift');
  final coordinator = File(
    'ios/VibeSyncKeyboard/KeyboardScreenshotAssistCoordinator.swift',
  );

  test('one judge call produces both batches', () {
    final prompt = judgePrompt.readAsStringSync();
    final provider = File(
      'supabase/functions/keyboard-assist/provider.ts',
    ).readAsStringSync();

    // Six self-explaining options need roughly twice the output budget that
    // three did; a truncated judge is a failed request, not a short one.
    expect(provider, contains('max_tokens: 2600'));
    expect(provider, contains('input.judgeTimeoutMs ?? 12_000'));

    expect(prompt, contains('兩批各 3 個'));
    expect(prompt, contains('alternates'));
    expect(
      prompt,
      contains('alternates 要能獨立'),
      reason: 'The second batch is an equal alternative, not leftovers.',
    );
    // Degrading to one batch beats failing the request outright, so the schema
    // must not force a second batch the conversation cannot support.
    final required = provider.substring(provider.indexOf('JUDGE_OUTPUT_SCHEMA'));
    final requiredBlock = required.substring(
      required.indexOf('required: ['),
      required.indexOf('} as const;'),
    );
    expect(requiredBlock, contains('"options"'));
    expect(requiredBlock, isNot(contains('"alternates"')));
    expect(prompt, contains('可以省略 alternates'));
    expect(
      File('supabase/functions/keyboard-assist/compiler_prompt.ts')
          .readAsStringSync(),
      contains('至少三種 strategy 各出現兩次'),
      reason: 'Two distinct batches need enough strategy spread to exist.',
    );
  });

  test('the second batch is held to the first batch standard', () {
    expect(
      grounding.readAsStringSync(),
      contains('[...result.options, ...result.alternates].every('),
      reason: 'Both batches reach the user, so both must be grounded.',
    );
    final validate = serverValidate.readAsStringSync();
    expect(validate, contains('function isBatchOfThree('));
    expect(
      validate,
      contains('return strategies.size === 3;'),
    );
    expect(
      contracts.readAsStringSync(),
      contains('alternates.isEmpty || Self.isBatchOfThree(alternates)'),
    );
  });

  test('swapping never becomes a second billed request', () {
    final source = coordinator.readAsStringSync();
    final start = source.indexOf('func swapBatch()');
    expect(start, greaterThanOrEqualTo(0));
    final body = _window(source, start, 420);

    expect(body, contains('stateMachine.send(.batchSwapped)'));
    for (final forbidden in [
      'network.',
      'prepareAndSubmit',
      'fetchLatest',
      'start(hasFullAccess',
    ]) {
      expect(
        body,
        isNot(contains(forbidden)),
        reason: '"換一批" must serve candidates this request already produced.',
      );
    }

    // The swap stays inside resultsPreview, so no new ledger entry can follow.
    final machine = state.readAsStringSync();
    final swap = machine.indexOf('case .batchSwapped:');
    expect(swap, greaterThanOrEqualTo(0));
    final transition = _window(machine, swap, 320);
    expect(transition, contains('case .resultsPreview(let presentation) = state'));
    expect(transition, contains('presentation.canSwapBatch'));
    expect(transition, contains('state = .resultsPreview(presentation.swappingBatch())'));
  });

  test('swapping is reversible and keeps the same request identity', () {
    final source = binding.readAsStringSync();
    final start = source.indexOf('func swappingBatch()');
    expect(start, greaterThanOrEqualTo(0));
    final body = _window(source, start, 700);

    expect(body, contains('binding: binding'));
    expect(body, contains('options: alternates'));
    expect(body, contains('alternates: options'));
    expect(
      body,
      contains('presentedAt: presentedAt'),
      reason: 'Swapping must not extend the safe insertion window.',
    );
  });

  test('both batches count as offered for leak detection', () {
    expect(
      coordinator.readAsStringSync(),
      contains('(ready.options + ready.alternates).map(\\.text)'),
      reason: 'Anything shown to the user can leak back through a screenshot.',
    );
  });
}
