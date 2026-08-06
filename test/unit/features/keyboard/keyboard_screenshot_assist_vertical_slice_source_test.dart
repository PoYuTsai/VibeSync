import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final coordinator = File(
    'ios/VibeSyncKeyboard/KeyboardScreenshotAssistCoordinator.swift',
  );
  final controller = File(
    'ios/VibeSyncKeyboard/KeyboardViewController.swift',
  );
  final project = File('ios/Runner.xcodeproj/project.pbxproj');
  final screenshotProvider = File(
    'ios/VibeSyncKeyboard/LatestScreenshotProvider.swift',
  );

  test('authenticated capability is resolved before any photo lookup', () {
    final source = coordinator.readAsStringSync();
    final capability = source.indexOf('network.fetchCapability(');
    final photos = source.indexOf('screenshotProvider.fetchLatest(');

    expect(capability, greaterThanOrEqualTo(0));
    expect(photos, greaterThan(capability));
    expect(source, contains('SharedAuth.currentSession()'));
    expect(source, contains('KeyboardContextStore.live()'));
    expect(source, contains('KeyboardScreenshotConsentProviding'));
    expect(
      source,
      contains('keyboard_screenshot_consent_receipt_v1'),
    );
    final recovery = source.indexOf('network.recoverLatestPending(');
    final detectAfterRecovery = source.indexOf(
      'detectLatestScreenshot(',
      recovery,
    );
    expect(recovery, greaterThan(capability));
    expect(detectAfterRecovery, greaterThan(recovery));
  });

  test('a detected screenshot runs without waiting for a second tap', () {
    final source = coordinator.readAsStringSync();

    // Consent is granted once in the app, so detection now drives generation
    // directly. The re-read inside confirmPreviewAndGenerate still guarantees
    // that a capture taken during the hop cannot be uploaded in place of the
    // one the panel is showing.
    final detected = source.indexOf('case .success(let screenshot):');
    final autoPreview = source.indexOf('self.requestLocalPreview()', detected);
    final autoGenerate = source.indexOf(
      'self.confirmPreviewAndGenerate()',
      autoPreview,
    );
    expect(detected, greaterThanOrEqualTo(0));
    expect(autoPreview, greaterThan(detected));
    expect(autoGenerate, greaterThan(autoPreview));

    expect(source, contains('func requestLocalPreview()'));
    expect(source, contains('func confirmPreviewAndGenerate()'));
    expect(source, contains('previewConfirmedAt'));
    expect(source, contains('KeyboardAssistSendAuthorization('));
    expect(source, contains('clearPendingAfterPresentation('));
    expect(source, contains('context: KeyboardContextEnvelope?'));
    expect(source, contains('primary: context?.globalVoice.primary'));
    final tap = source.indexOf('let previewConfirmedAt = now()');
    final confirmationPhotoRead = source.indexOf(
      'screenshotProvider.fetchLatest(',
      tap,
    );
    final authorization = source.indexOf(
      'previewConfirmedAt: previewConfirmedAt',
      confirmationPhotoRead,
    );
    expect(tap, greaterThanOrEqualTo(0));
    expect(confirmationPhotoRead, greaterThan(tap));
    expect(authorization, greaterThan(confirmationPhotoRead));
  });

  test('ambiguous post results recover only through same request GET', () {
    final source = coordinator.readAsStringSync();
    final uncertain = source.indexOf('case .transportUncertain');
    final lookup = source.indexOf('lookupSameRequest(', uncertain);

    expect(uncertain, greaterThanOrEqualTo(0));
    expect(lookup, greaterThan(uncertain));
    expect(source, isNot(contains('retryAmbiguousPost')));
  });

  test('candidate insertion is explicit and bound to current identity', () {
    final source = coordinator.readAsStringSync();
    final view = controller.readAsStringSync();

    expect(source, contains('func insertCandidate('));
    expect(source, contains('KeyboardInsertionContext('));
    expect(source, contains('insertionCoordinator.insert('));
    expect(source, contains('func documentDidChange('));
    expect(source, contains('func ownerDidChange()'));
    expect(source, contains('func screenshotDidChange()'));
    expect(source, contains('func contextDidChange()'));
    expect(source, contains('func viewDidDisappear()'));
    expect(
      source,
      contains('try self.preprocessor.prepare(\n'
          '                            currentScreenshot.thumbnail'),
    );
    expect(
      source,
      contains('guard verified.sha256 ==\n'
          '                            presentation.binding.screenshotHash'),
    );

    final insert = source.indexOf('func insertCandidate(');
    final clearPending = source.indexOf(
      'clearPendingAfterPresentation(',
      insert,
    );
    final insertText = source.indexOf(
      'insertionCoordinator.insert(',
      clearPending,
    );
    expect(clearPending, greaterThan(insert));
    expect(insertText, greaterThan(clearPending));
    expect(source, contains('尚未插入：無法安全完成本機清理'));

    expect(
      view,
      isNot(contains('confirmScreenshotPreview')),
      reason: 'The per-upload confirmation button no longer exists.',
    );
    expect(view, contains('#selector(insertScreenshotCandidate(_:))'));
    expect(view, isNot(contains('autoInsertScreenshotCandidate')));
  });

  test('pending hash verification uses deterministic PhotoKit raster sizing',
      () {
    final source = screenshotProvider.readAsStringSync();

    expect(source, contains('requestOptions.resizeMode = .exact'));
    expect(source, contains('maximumPixelSize: 960'));
    expect(source, contains('contentMode: .aspectFit'));
  });

  test('production target compiles the coordinator and its tests', () {
    final projectSource = project.readAsStringSync();

    expect(
      'KeyboardScreenshotAssistCoordinator.swift in Sources'
          .allMatches(projectSource)
          .length,
      greaterThanOrEqualTo(2),
    );
    expect(
      projectSource,
      contains('KeyboardScreenshotAssistCoordinatorTests.swift in Sources'),
    );
  });
}
