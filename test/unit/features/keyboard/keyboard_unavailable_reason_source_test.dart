import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _window(String source, int start, int length) =>
    source.substring(start, (start + length).clamp(0, source.length));

/// A fixed-length window silently drops branches as soon as the function grows,
/// so slice to the next declaration instead.
String _functionBody(String source, String signature) {
  final start = source.indexOf(signature);
  if (start < 0) return '';
  final end = source.indexOf('\n    private func ', start + signature.length);
  return source.substring(start, end < 0 ? source.length : end);
}

/// The states that hide the screenshot panel also hide the panel's own status
/// label, so a real user experienced "I screenshot and nothing happens" with no
/// explanation anywhere. Whatever reason those states carry has to reach the
/// always-visible line instead.
void main() {
  final controller = File(
    'ios/VibeSyncKeyboard/KeyboardViewController.swift',
  );
  final coordinator = File(
    'ios/VibeSyncKeyboard/KeyboardScreenshotAssistCoordinator.swift',
  );

  test('a hidden panel still explains itself', () {
    final source = controller.readAsStringSync();
    expect(source.indexOf('private func renderScreenshotAssist('),
        greaterThanOrEqualTo(0));
    final body = _functionBody(source, 'private func renderScreenshotAssist(');

    expect(
      RegExp('surfaceUnavailableReason').allMatches(body).length,
      greaterThanOrEqualTo(2),
      reason: 'Every panel-hiding branch must be able to say why.',
    );
    expect(source, contains('private func surfaceUnavailableReason('));
  });

  test('standing the flow down never hijacks the paste flow status', () {
    final source = controller.readAsStringSync();
    final start = source.indexOf('private func surfaceUnavailableReason(');
    final body = _window(source, start, 260);

    expect(
      body,
      contains('guard let message, !message.isEmpty else { return }'),
      reason: 'viewDidDisappear and suspendForLegacyFlow pass no message; '
          'overwriting the label there would clobber the paste flow.',
    );
  });

  test('a recovered flow stops repeating a stale failure', () {
    final source = controller.readAsStringSync();
    final reset = source.indexOf('private func resetScreenshotControls()');
    expect(
      _window(source, reset, 220),
      contains('returnStatusLine()'),
      reason: 'Reset runs before every render, so a state that no longer '
          'fails hands the shared line back.',
    );
    expect(source, contains('private func returnStatusLine()'));
    expect(source, contains('statusLineBorrowed'));
  });

  test('the capability dead ends carry an actionable reason', () {
    final source = coordinator.readAsStringSync();

    expect(
      source,
      contains('暫時無法取得截圖分析授權'),
      reason: 'A failed capability call used to be silent.',
    );
    expect(
      source,
      contains('截圖分析尚未對這個帳號開啟'),
      reason: 'An unusable capability receipt used to be silent.',
    );
    // Standing the flow down stays deliberately quiet.
    final suspend = source.indexOf('func suspendForLegacyFlow()');
    expect(
      _window(source, suspend, 220),
      contains('.featureUnavailable, message: nil'),
    );
  });
}
