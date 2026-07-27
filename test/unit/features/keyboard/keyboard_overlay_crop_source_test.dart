import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A screenshot taken while our keyboard is on screen contains our own panel,
/// including the candidate replies produced moments earlier. Uploading that
/// wastes budget, dilutes the chat text once the capture is downscaled, and
/// lets the compiler transcribe our suggestions as if they were chat messages.
void main() {
  final preprocessor = File(
    'ios/VibeSyncKeyboard/KeyboardImagePreprocessor.swift',
  );
  final coordinator = File(
    'ios/VibeSyncKeyboard/KeyboardScreenshotAssistCoordinator.swift',
  );
  final controller = File(
    'ios/VibeSyncKeyboard/KeyboardViewController.swift',
  );

  test('the trim happens before the uploaded bytes are hashed', () {
    final source = preprocessor.readAsStringSync();
    final trim = source.indexOf('Self.croppingBottom(source, fraction: fraction)');
    final digest = source.indexOf('SHA256.hash(data: data)');

    expect(trim, greaterThanOrEqualTo(0));
    expect(digest, greaterThan(trim));
    expect(source, contains('static func croppingBottom('));
    expect(
      source,
      contains('image.imageOrientation == .up'),
      reason: 'CGImage cropping is pixel-space, so a rotated capture must be '
          'left alone rather than trimmed along the wrong edge.',
    );
  });

  test('geometry is read on the main thread, never inside the worker', () {
    final source = coordinator.readAsStringSync();

    expect(source, contains('typealias OverlayFractionProvider'));
    for (final site in RegExp(
      r'let overlayFraction = (self\.)?overlayFractionProvider\(',
    ).allMatches(source)) {
      final worker = source.indexOf('schedulePreprocessing', site.end);
      expect(
        worker,
        greaterThan(site.end),
        reason: 'The fraction must be captured before the work is scheduled.',
      );
    }
    expect(
      RegExp(r'croppingBottomFraction: overlayFraction').allMatches(source),
      hasLength(3),
      reason: 'Every preprocessing path uploads a trimmed capture.',
    );
    expect(
      source,
      contains('private func trimmedPreview('),
      reason: 'The preview must show the same pixels that get uploaded.',
    );
  });

  test('a capture taken before the keyboard appeared is never trimmed', () {
    final source = controller.readAsStringSync();
    final start = source.indexOf('func keyboardOverlayFraction(');
    expect(start, greaterThanOrEqualTo(0));
    final body = source.substring(start, start + 700);

    expect(body, contains('capturedAt >= visibleSince'));
    expect(
      body,
      contains('min(overlayHeight / screenHeight, 0.7)'),
      reason: 'An unexpected geometry reading must never eat the chat.',
    );
    expect(source, contains('keyboardVisibleSince = Date()'));
    expect(source, contains('keyboardVisibleSince = nil'));
  });

  test('the trim uses the height at capture time, not at upload time', () {
    final source = controller.readAsStringSync();

    expect(source, contains('let overlayHeight = heightWhenCaptured(capturedAt)'));
    final lookup = source.indexOf('private func heightWhenCaptured(');
    expect(lookup, greaterThanOrEqualTo(0));
    expect(
      source.substring(lookup, lookup + 260),
      contains(r'overlayHeightSamples.last('),
      reason: 'The panel grows while the request is in flight, so reading the '
          'current height would trim real conversation out of the upload.',
    );
    expect(source, contains('private func recordOverlayHeightSample()'));
    expect(
      source,
      contains('overlayHeightSamples.removeAll()'),
      reason: 'Samples belong to one keyboard session.',
    );
  });
}
