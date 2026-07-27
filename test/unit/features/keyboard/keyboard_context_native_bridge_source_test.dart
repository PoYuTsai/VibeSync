import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final bridgeFile = File('ios/Runner/KeyboardContextBridge.swift');
  final sceneDelegateFile = File('ios/Runner/SceneDelegate.swift');
  final projectFile = File('ios/Runner.xcodeproj/project.pbxproj');
  final runnerInfoFile = File('ios/Runner/Info.plist');

  test('Runner exposes typed context and photo authorization methods', () {
    expect(bridgeFile.existsSync(), isTrue);
    final source = bridgeFile.readAsStringSync();

    expect(source, contains('"vibesync/keyboard_context"'));
    expect(source, contains('case "writeSnapshot"'));
    expect(source, contains('case "purgeContext"'));
    expect(source, contains('case "requestPhotoAuthorization"'));
    expect(source, contains('case "currentPhotoAuthorization"'));
    expect(source, contains('"beginScreenshotConsentSetup"'));
    expect(source, contains('case "writeScreenshotConsentReceipt"'));
    expect(source, contains('case "clearScreenshotConsentReceipt"'));
    expect(source, contains('case "verifyScreenshotConsentReceipt"'));
    expect(source, contains('PHPhotoLibrary.requestAuthorization'));
    expect(source, contains('"storedRevision"'));
    expect(source, contains('purgePendingReplayIdentity'));
    expect(source, contains('KeyboardContextStore'));
    expect(
      source,
      contains('KeyboardSharedConfig.keyboardScreenshotConsentReceipt'),
    );
    expect(source, contains('keyboard_screenshot_consent_epoch_v1'));
    expect(source, contains('expectedEpoch'));
    expect(source, contains('staleConsentEpoch'));
  });

  test('SceneDelegate retains the channel and Xcode compiles the bridge', () {
    final sceneSource = sceneDelegateFile.readAsStringSync();
    final projectSource = projectFile.readAsStringSync();

    expect(sceneSource, contains('keyboardContextBridge'));
    expect(sceneSource, contains('configureKeyboardContextBridge'));
    expect(projectSource, contains('KeyboardContextBridge.swift in Sources'));
  });

  test('native bridge never accepts or persists screenshot bytes', () {
    final source = bridgeFile.readAsStringSync();

    expect(source, isNot(contains('UIImage')));
    expect(source, isNot(contains('PHAsset')));
    expect(source, isNot(contains('screenshotData')));
    expect(source, isNot(contains('imageData')));
  });

  test('Photos purpose string describes opt-in recent screenshot behavior', () {
    final source = runnerInfoFile.readAsStringSync();

    expect(source, contains('NSPhotoLibraryUsageDescription'));
    expect(source, contains('另行啟用'));
    expect(source, contains('最近 3 分鐘'));
    expect(source, contains('先在本機預覽'));
  });
}
