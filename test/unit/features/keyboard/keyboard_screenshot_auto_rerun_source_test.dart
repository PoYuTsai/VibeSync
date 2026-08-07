import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every ready result is billed, so automatic behaviour has to be provably
/// stingy: reopening the keyboard, or an unrelated photo library mutation,
/// must never spend a second charge on a capture this chat already analysed.
void main() {
  final coordinator = File(
    'ios/VibeSyncKeyboard/KeyboardScreenshotAssistCoordinator.swift',
  );
  final provider = File(
    'ios/VibeSyncKeyboard/LatestScreenshotProvider.swift',
  );
  final controller = File(
    'ios/VibeSyncKeyboard/KeyboardViewController.swift',
  );

  test('an already analysed capture cannot start a second billed run', () {
    final source = coordinator.readAsStringSync();

    expect(source, contains('private func alreadyAnalyzed('));
    expect(
      source,
      contains('lastAnalyzedAsset == screenshot.assetIdentifier &&'),
    );
    expect(
      source,
      contains('lastAnalyzedDocument == boundDocumentIdentifier'),
      reason: 'The same capture in a different chat is genuinely new work.',
    );

    final guardSite = source.indexOf('guard !self.alreadyAnalyzed(screenshot)');
    final generate = source.indexOf(
      'self.confirmPreviewAndGenerate()',
      guardSite,
    );
    expect(guardSite, greaterThanOrEqualTo(0));
    expect(
      generate,
      greaterThan(guardSite),
      reason: 'The guard must precede the request that spends quota.',
    );

    // An explicit retry is the user asking for the work again.
    expect(source, contains('func startForcingReanalysis(hasFullAccess: Bool)'));
  });

  test('a library notification peeks before discarding visible results', () {
    final source = coordinator.readAsStringSync();
    final start = source.indexOf('func libraryDidChange(hasFullAccess: Bool)');
    expect(start, greaterThanOrEqualTo(0));
    // 視窗要涵蓋整個函式；2026-08-07 白名單補了停止等待 case＋註解後
    // 舊的 2200 會把函式尾巴截掉，indexOf 假性 -1。
    final body = source.substring(start, start + 3000);

    // In-flight work owns its request; only a settled panel may restart.
    expect(body, contains('case .idle,'));
    expect(body, contains('.resultsPreview,'));
    // 2026-08-07 Bruce：按 X 停止等待後截新圖必須能開新一輪。
    expect(body, contains('.failed(_, .lookupSameRequest):'));
    expect(body, contains('default:\n            return'));
    // Bursts of PhotoKit notifications must not become bursts of round trips.
    expect(body, contains('timeIntervalSince(previous) < 1'));
    final peek = body.indexOf('screenshotProvider.fetchLatest(');
    final restart = body.indexOf('self.start(hasFullAccess: hasFullAccess)');
    expect(peek, greaterThanOrEqualTo(0));
    expect(
      restart,
      greaterThan(peek),
      reason: 'Restarting before checking would wipe results the user is '
          'reading whenever any unrelated photo changes.',
    );
    expect(body, contains('!self.alreadyAnalyzed(screenshot)'));
  });

  test('observation is registered with the keyboard and torn down with it', () {
    expect(
      controller.readAsStringSync(),
      contains('screenshotCoordinator.startObservingLibrary('),
    );
    expect(
      coordinator.readAsStringSync(),
      contains('stopObservingLibrary()'),
    );

    final source = provider.readAsStringSync();
    expect(source, contains('PHPhotoLibraryChangeObserver'));
    expect(
      source,
      contains('PHPhotoLibrary.shared().unregisterChangeObserver(relay)'),
    );
    expect(
      source,
      contains('DispatchQueue.main.async { [onChange] in'),
      reason: 'PhotoKit delivers on a private queue; keyboard state is main '
          'thread only.',
    );
  });
}
