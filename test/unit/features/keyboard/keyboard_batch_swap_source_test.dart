import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// One visible batch of three, one line per angle — 延展 / 調情 / 幽默 — and no
/// "換一批". Six options across two batches cost twice the judge output for a
/// choice nobody was asking to make, and every extra constraint (two batches,
/// distinct strategies within each, no overlap between them) was another way
/// for an ordinary screenshot to be refused.
///
/// The second-batch machinery is left in place but dormant: `alternates` is
/// still optional in the contract and the client still knows how to swap, so
/// bringing it back is a server decision rather than a new build.
/// Reading a bounded window after an anchor, without falling off the end of a
/// short file.
String _window(String source, int start, int length) =>
    source.substring(start, (start + length).clamp(0, source.length));

void main() {
  final judgePrompt = File(
    'supabase/functions/keyboard-assist/judge_prompt.ts',
  );
  final compilerPrompt = File(
    'supabase/functions/keyboard-assist/compiler_prompt.ts',
  );
  final contract = File('supabase/functions/keyboard-assist/contract.ts');
  final normalize = File('supabase/functions/keyboard-assist/normalize.ts');
  final serverValidate = File(
    'supabase/functions/keyboard-assist/validate.ts',
  );
  final grounding = File('supabase/functions/keyboard-assist/grounding.ts');
  final contracts = File('ios/SharedKeyboard/KeyboardAssistContracts.swift');
  final binding = File('ios/VibeSyncKeyboard/KeyboardRequestBinding.swift');
  final state = File('ios/VibeSyncKeyboard/KeyboardAssistState.swift');
  final controller = File(
    'ios/VibeSyncKeyboard/KeyboardViewController.swift',
  );
  final coordinator = File(
    'ios/VibeSyncKeyboard/KeyboardScreenshotAssistCoordinator.swift',
  );

  test('three angles, named the same way everywhere', () {
    expect(
      contract.readAsStringSync(),
      contains('"extend",\n  "flirt",\n  "humor",'),
    );
    final compiler = compilerPrompt.readAsStringSync();
    expect(compiler, contains('extend＝延展'));
    expect(compiler, contains('flirt＝調情'));
    expect(compiler, contains('humor＝幽默'));

    // The wire value and the chip the user reads must not drift apart.
    final swift = controller.readAsStringSync();
    for (final pair in [
      ['case .extend:', '"延展"'],
      ['case .flirt:', '"調情"'],
      ['case .humor:', '"幽默"'],
    ]) {
      final at = swift.indexOf(pair[0]);
      expect(at, greaterThanOrEqualTo(0), reason: pair[0]);
      expect(_window(swift, at, 60), contains(pair[1]));
    }
  });

  test('one batch of three, and the judge is told not to build a second', () {
    expect(
      compilerPrompt.readAsStringSync(),
      contains('正好三個'),
    );
    expect(
      normalize.readAsStringSync(),
      contains('value.candidates.length !== 3'),
    );
    final prompt = judgePrompt.readAsStringSync();
    expect(prompt, contains('選出 3 個放進 options'));
    expect(prompt, contains('不要輸出 alternates'));

    // A judge that cannot be truncated still needs headroom for three
    // explained options.
    final provider = File(
      'supabase/functions/keyboard-assist/provider.ts',
    ).readAsStringSync();
    expect(provider, contains('max_tokens: 2600'));
    final requiredBlock = provider.substring(
      provider.indexOf('required: [', provider.indexOf('JUDGE_OUTPUT_SCHEMA')),
      provider.indexOf('} as const;', provider.indexOf('JUDGE_OUTPUT_SCHEMA')),
    );
    expect(requiredBlock, contains('"options"'));
    expect(requiredBlock, isNot(contains('"alternates"')));
  });

  test('a missing second batch is a shape, not a crash', () {
    expect(
      contract.readAsStringSync(),
      contains('alternates?: KeyboardAssistOption[];'),
    );
    expect(
      grounding.readAsStringSync(),
      contains('[...result.options, ...(result.alternates ?? [])].every('),
      reason: 'Anything served is grounded, and an absent batch is not an '
          'error to throw on.',
    );
    final validate = serverValidate.readAsStringSync();
    expect(validate, contains('function isBatchOfThree('));
    expect(validate, contains('return strategies.size === 3;'));
    expect(
      contracts.readAsStringSync(),
      contains('alternates.isEmpty || Self.isBatchOfThree(alternates)'),
    );
  });

  test('the dormant swap can never become a second billed request', () {
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

    final machine = state.readAsStringSync();
    final swap = machine.indexOf('case .batchSwapped:');
    expect(swap, greaterThanOrEqualTo(0));
    final transition = _window(machine, swap, 320);
    expect(transition, contains('case .resultsPreview(let presentation) = state'));
    expect(transition, contains('presentation.canSwapBatch'));
    expect(
      transition,
      contains('state = .resultsPreview(presentation.swappingBatch())'),
    );
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

  test('everything offered counts as offered for leak detection', () {
    expect(
      coordinator.readAsStringSync(),
      contains('(ready.options + ready.alternates).map(\\.text)'),
      reason: 'Anything shown to the user can leak back through a screenshot.',
    );
  });
}
