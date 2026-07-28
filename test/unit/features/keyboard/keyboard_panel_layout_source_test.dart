import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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

/// The screenshot flow owns the keyboard's main surface. The older paste flow
/// still exists — it is the only path when a conversation cannot be
/// screenshotted — but it lives behind a switch instead of sharing the panel,
/// because competing for the same half-screen made the screenshot flow read as
/// one widget among many rather than the product.
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

  test('the screenshot surface opens first and the paste flow survives', () {
    final source = controller.readAsStringSync();

    // The paste flow is intact, just no longer on the same surface.
    expect(source, contains('#selector(loadClipboard)'));
    expect(source, contains('#selector(generateReply(_:))'));
    expect(source, contains('#selector(insertGeneratedReply)'));

    expect(source, contains('private enum Mode { case assist, text, typing }'));
    expect(
      source,
      contains('show(.assist)'),
      reason: 'The keyboard opens on the screenshot surface, not the panel of '
          'buttons.',
    );
    expect(source, contains('#selector(showTextAssist)'));
    expect(source, contains('#selector(showAssist)'));
    expect(
      source,
      contains('assistPanel.addArrangedSubview(screenshotPanel)'),
      reason: 'The screenshot panel is the assist surface, not a row wedged '
          'into the paste panel.',
    );
    // Only one flow may be live, because both spend quota.
    final toText = source.indexOf('func showTextAssist()');
    expect(toText, greaterThanOrEqualTo(0));
    expect(
      _window(source, toText, 220),
      contains('screenshotCoordinator.suspendForLegacyFlow()'),
    );
  });

  test('an empty surface still says what to do, and why it cannot', () {
    final source = controller.readAsStringSync();
    final start = source.indexOf('private func renderAssistIdleView(');
    expect(start, greaterThanOrEqualTo(0));
    final body = _window(source, start, 1200);

    expect(body, contains('assistIdleTitleText'));
    expect(
      body,
      contains('renderState.message'),
      reason: 'Hiding the panel must never hide the reason it is hidden.',
    );
    expect(body, contains('case .featureUnavailable,'));
    expect(body, contains('.photoPermissionRequired'));
  });

  test('another batch is always one tap away', () {
    final source = controller.readAsStringSync();

    expect(source, contains('#selector(requestNewCandidateBatch)'));
    final action = source.indexOf('func requestNewCandidateBatch()');
    expect(action, greaterThanOrEqualTo(0));
    expect(
      _window(source, action, 140),
      contains('screenshotCoordinator.requestNewBatch()'),
    );
  });

  test('the capture and what we say about it read as a conversation', () {
    final source = controller.readAsStringSync();

    // Thumbnail on the left where the other person's messages sit, our status
    // answering from the right — a centered caption over a full-width image
    // read as a loading screen, not a reply being written.
    final row = source.indexOf('screenshotProgressRow.axis = .horizontal');
    expect(row, greaterThanOrEqualTo(0));
    final body = _window(source, row, 420);
    expect(
      body.indexOf('addArrangedSubview(screenshotPreviewImageView)'),
      lessThan(body.indexOf('addArrangedSubview(screenshotStatusBubble)')),
      reason: 'The capture leads; the bubble answers it.',
    );
    expect(
      source,
      contains('screenshotPanel.addArrangedSubview(screenshotProgressRow)'),
    );
    // An empty bubble is a grey rectangle with nothing in it.
    expect(
      source,
      contains(
        'screenshotStatusBubble.isHidden = (renderState.message ?? "").isEmpty',
      ),
    );
  });

  test('the capture animates in once and never repeats', () {
    final source = controller.readAsStringSync();
    final body = _functionBody(source, 'private func showCapture(');
    expect(body, isNot(isEmpty));

    expect(
      body,
      contains('guard isNewCapture, image != nil else { return }'),
      reason: 'Re-rendering the same capture must not re-animate it; every '
          'render state change calls through here.',
    );
    // An input view that never settles never stops redrawing.
    expect(body, isNot(contains('repeat')));
    expect(body, isNot(contains('autoreverse')));

    // Reset runs before every render, so a half-finished transform must not
    // survive into the next capture.
    final reset = _functionBody(
      source,
      'private func resetScreenshotControls()',
    );
    expect(reset, contains('screenshotPreviewImageView.transform = .identity'));
    expect(reset, contains('screenshotPreviewImageView.alpha = 1'));
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
