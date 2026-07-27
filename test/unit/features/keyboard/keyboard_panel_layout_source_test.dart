import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _window(String source, int start, int length) =>
    source.substring(start, (start + length).clamp(0, source.length));

/// The panel is one surface with two input sources, not two modes. The
/// screenshot flow adds an analysis card and self-explaining candidates on top
/// of the paste flow that already worked, rather than replacing it.
void main() {
  final controller = File(
    'ios/VibeSyncKeyboard/KeyboardViewController.swift',
  );
  final coordinator = File(
    'ios/VibeSyncKeyboard/KeyboardScreenshotAssistCoordinator.swift',
  );

  test('the analysis says what is going on and whose turn it is', () {
    final source = controller.readAsStringSync();
    final start = source.indexOf('private func renderAnalysisCard(');
    expect(start, greaterThanOrEqualTo(0));
    final body = _window(source, start, 1400);

    expect(body, contains('presentation.cue'));
    expect(body, contains('輪到你回'));
    expect(body, contains('她沒在等你回'));
    expect(
      body,
      contains('presentation.uncertainty'),
      reason: 'Saying what we could not read beats being confidently wrong.',
    );
    // A fabricated affinity score is banned server-side and stays out here too.
    expect(source, isNot(contains('好感度')));
  });

  test('every candidate explains itself', () {
    final source = controller.readAsStringSync();
    final start = source.indexOf('private func makeCandidateRow(');
    expect(start, greaterThanOrEqualTo(0));
    final body = _window(source, start, 1800);

    expect(body, contains('strategyTitle(option.strategy)'));
    expect(body, contains('strategyColor(option.strategy)'));
    expect(body, contains(r'"\(option.why) · \(option.effect)"'));
    expect(
      body,
      contains('#selector(insertScreenshotCandidate(_:))'),
      reason: 'Insertion stays an explicit tap on the line itself.',
    );
    // The old row crammed all four fields into one button title.
    expect(
      source,
      isNot(contains(r'"\(strategyTitle(option.strategy))\n\(option.text)')),
    );
  });

  test('the paste flow survives alongside the screenshot flow', () {
    final source = controller.readAsStringSync();

    expect(source, contains('#selector(loadClipboard)'));
    expect(source, contains('#selector(generateReply(_:))'));
    expect(source, contains('#selector(insertGeneratedReply)'));
    expect(
      source,
      contains('截圖聊天畫面會自動分析；或複製訊息後點「載入」'),
      reason: 'The empty state teaches both paths without a mode switch.',
    );
  });

  test('the free second batch is only offered when it exists', () {
    final source = controller.readAsStringSync();

    expect(
      source,
      contains('screenshotSwapButton.isHidden = !presentation.canSwapBatch'),
    );
    expect(source, contains('#selector(swapCandidateBatch)'));
    final action = source.indexOf('func swapCandidateBatch()');
    expect(action, greaterThanOrEqualTo(0));
    expect(
      _window(source, action, 140),
      contains('screenshotCoordinator.swapBatch()'),
    );
  });

  test('an explicit voice replaces the pair instead of diluting it', () {
    final source = coordinator.readAsStringSync();

    expect(source, contains('func setVoiceOverride('));
    expect(
      source,
      contains(r'KeyboardAssistVoice(primary: $0, secondary: nil)'),
    );
    // Falling back to the app-side voice is what keeps one personality.
    expect(source, contains('primary: context?.globalVoice.primary'));
    expect(
      controller.readAsStringSync(),
      contains('風格：跟隨 App'),
    );
  });
}
