import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// One visible batch of three, one line per angle — 延展 / 調情 / 幽默 — and
/// "換一批" means generating another three, not revealing three that were held
/// back. Producing six per request cost every screenshot the output for three
/// lines most users never asked for, and capped the feature at exactly one
/// retry; each extra cross-batch constraint was another way for an ordinary
/// screenshot to be refused outright.
/// Reading a bounded window after an anchor, without falling off the end of a
/// short file.
String _window(String source, int start, int length) =>
    source.substring(start, (start + length).clamp(0, source.length));

/// A fixed-length window silently drops assertions as soon as the function
/// grows, so slice to the next declaration instead.
String _functionBody(String source, String signature) {
  final start = source.indexOf(signature);
  if (start < 0) return '';
  final end = source.indexOf('\n    private func ', start + signature.length);
  return source.substring(start, end < 0 ? source.length : end);
}

void main() {
  final compilerPrompt = File(
    'supabase/functions/keyboard-assist/compiler_prompt.ts',
  );
  final contract = File('supabase/functions/keyboard-assist/contract.ts');
  final normalize = File('supabase/functions/keyboard-assist/normalize.ts');
  final serverValidate = File(
    'supabase/functions/keyboard-assist/validate.ts',
  );
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

  test('one call produces exactly one batch of three', () {
    expect(compilerPrompt.readAsStringSync(), contains('正好三個'));
    expect(
      normalize.readAsStringSync(),
      contains('value.candidates.length !== 3'),
    );
    final validate = serverValidate.readAsStringSync();
    expect(validate, contains('function isBatchOfThree('));
    expect(validate, contains('return strategies.size === 3;'));
  });

  test('"換一批" is another analysis, not a reserve batch', () {
    final source = coordinator.readAsStringSync();
    final body = _functionBody(source, 'func requestNewBatch()');
    expect(body, isNot(isEmpty));

    // Regenerating is the whole point: it goes back through the same submit
    // path every other generation uses.
    expect(body, contains('prepareAndSubmit'));
    expect(
      body,
      contains('rememberOffered(presentation.options.map(\\.text))'),
      reason: 'Without the lines already on screen, a new batch has no reason '
          'to differ from the one it replaces.',
    );
    // A newer screenshot while the result sat on screen means the user has
    // moved on; re-rolling the old capture would answer a stale conversation.
    expect(body, contains('screenshotProvider.fetchLatest('));
    expect(body, contains('self.screenshotDidChange()'));
    // The re-roll must stay bound to the capture that produced the result.
    expect(
      body,
      contains(
        'presentation.binding.assetIdentifier ==\n'
        '                selectedScreenshot.assetIdentifier',
      ),
    );

    // Nothing is held back any more, so nothing decides whether the button is
    // available except having a result to re-roll.
    expect(source, isNot(contains('canSwapBatch')));
    expect(source, isNot(contains('alternates')));
  });

  test('a re-roll starts a real generation, not an in-place swap', () {
    // Submitting re-seeds the state machine, so a generation can start from a
    // result without `generationStarted` needing its own `.resultsPreview`
    // case. What keeps the re-roll honest is the asset check above, not a
    // transition guard.
    final source = coordinator.readAsStringSync();
    final submit = source.indexOf('private func submitPreparedImage(');
    expect(submit, greaterThanOrEqualTo(0));
    final body = source.substring(submit);
    final seed = body.indexOf('stateMachine = KeyboardAssistStateMachine(');
    expect(seed, greaterThanOrEqualTo(0));
    expect(
      body.indexOf('stateMachine.send(.generationStarted(binding))'),
      greaterThan(seed),
    );

    // The old in-place swap is gone; there is no held-back batch to swap to.
    final machine = state.readAsStringSync();
    expect(machine, isNot(contains('batchSwapped')));
    expect(machine, isNot(contains('alternates')));
  });

  test('the button is offered whenever there is a result to re-roll', () {
    final swift = controller.readAsStringSync();
    expect(
      swift,
      contains(
        'screenshotSwapButton.isHidden =\n'
        '                !screenshotCoordinator.canRequestNewBatch',
      ),
    );
    expect(swift, contains('#selector(requestNewCandidateBatch)'));

    final source = coordinator.readAsStringSync();
    final start = source.indexOf('var canRequestNewBatch: Bool {');
    expect(start, greaterThanOrEqualTo(0));
    final body = _window(source, start, 200);
    expect(body, contains('case .resultsPreview = stateMachine.state'));
    expect(
      body,
      contains('latestScreenshot != nil'),
      reason: 'Offering a re-roll with no capture to re-roll is a dead button.',
    );
  });

  test('everything offered counts as offered for leak detection', () {
    final source = coordinator.readAsStringSync();
    expect(
      source,
      contains('rememberOffered(ready.options.map(\\.text))'),
      reason: 'Anything shown to the user can leak back through a screenshot.',
    );
    // Repeated re-rolls have to diverge from every batch the user has seen in
    // this chat, not just the one immediately before.
    final body = _functionBody(source, 'private func rememberOffered(');
    expect(body, contains('priorTurnForCurrentDocument()?.offeredTexts'));
    expect(
      body,
      contains('KeyboardSharedConfig.maximumPriorOfferedTexts'),
      reason: 'An over-long list is rejected wholesale by the contract, which '
          'would silently drop the dedupe hint entirely.',
    );
  });
}
