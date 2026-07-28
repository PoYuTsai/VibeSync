import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Opening the keyboard must not, by itself, spend a charge. The trigger is the
/// user taking a screenshot *while the keyboard is on screen* — the same
/// gesture that already produces the iOS capture animation — not "whatever is
/// the newest thing in the camera roll".
void main() {
  final provider = File(
    'ios/VibeSyncKeyboard/LatestScreenshotProvider.swift',
  );
  final coordinator = File(
    'ios/VibeSyncKeyboard/KeyboardScreenshotAssistCoordinator.swift',
  );
  final controller = File(
    'ios/VibeSyncKeyboard/KeyboardViewController.swift',
  );

  test('the session floor is applied on top of the recency window', () {
    final source = provider.readAsStringSync();

    expect(source, contains('sessionStartedAt: @escaping () -> Date?'));
    final start = source.indexOf('let floor = ignoringSessionFloor');
    expect(
      start,
      greaterThanOrEqualTo(0),
      reason: 'Both floors apply; the later one wins.',
    );
    final body = source.substring(start, start + 320);
    expect(body, contains('sessionStartedAt() ?? .distantPast'));
    expect(body, contains('reference.addingTimeInterval(-recencyWindow)'));
    expect(body, contains('let earliest = max('));
  });

  test('the floor is the moment this keyboard became visible', () {
    expect(
      coordinator.readAsStringSync(),
      contains('sessionStartedAt: @escaping () -> Date?'),
    );

    final source = controller.readAsStringSync();
    final start = source.indexOf('sessionStartedAt: { [weak self] in');
    expect(start, greaterThanOrEqualTo(0));
    expect(
      source.substring(start, start + 90),
      contains('self?.keyboardVisibleSince'),
    );
    // viewWillAppear stamps it; viewWillDisappear clears it.
    expect(source, contains('keyboardVisibleSince = Date()'));
    expect(source, contains('keyboardVisibleSince = nil'));
  });

  test('only an explicit tap may reach past the floor', () {
    final source = coordinator.readAsStringSync();

    expect(source, contains('private var includePreSessionCapture = false'));
    final forced = source.indexOf('func startForcingReanalysis(');
    expect(forced, greaterThanOrEqualTo(0));
    expect(
      source.substring(forced, forced + 260),
      contains('includingPreSessionCapture: true'),
    );
    // The automatic library-notification peek is always strict.
    final auto = source.indexOf('func libraryDidChange(hasFullAccess: Bool)');
    expect(
      source.substring(auto, auto + 2400),
      contains('ignoringSessionFloor: false'),
    );
    // Scoped to one run: every start() that is not the forced one resets it,
    // so it cannot leak into the next automatic run.
    expect(
      source,
      contains('start(hasFullAccess: hasFullAccess, includingPreSessionCapture: false)'),
    );
    expect(
      source,
      contains('includePreSessionCapture = includingPreSessionCapture'),
    );
    // The pre-spend re-reads belong to the same run and must agree with it,
    // otherwise a tapped run invalidates itself right before paying. "換一批"
    // is one of them: it re-reads before spending, inside the run the user
    // started by tapping.
    expect(
      RegExp('ignoringSessionFloor: includePreSessionCapture')
          .allMatches(source),
      hasLength(4),
    );

    expect(
      controller.readAsStringSync(),
      contains('assistPreSessionButton'),
      reason: 'The escape hatch has to be reachable while the panel is empty.',
    );
  });

  test('an empty surface is an invitation, not a failure report', () {
    expect(
      coordinator.readAsStringSync(),
      contains('message: "截圖這則對話，就會自動分析"'),
    );
    expect(
      coordinator.readAsStringSync(),
      isNot(contains('找不到最近三分鐘內的截圖')),
    );
  });
}
