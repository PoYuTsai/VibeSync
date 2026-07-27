import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/core/services/keyboard_privacy_purge_service.dart';
import 'package:vibesync/features/keyboard/data/providers/keyboard_context_sync_provider.dart';
import 'package:vibesync/features/keyboard/data/services/keyboard_context_bridge.dart';
import 'package:vibesync/features/keyboard/domain/entities/keyboard_context_snapshot.dart';
import 'package:vibesync/shared/widgets/ai_data_sharing_consent.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AiDataSharingConsent.debugUserIdOverride = () => 'owner-1';
  });

  tearDown(() {
    AiDataSharingConsent.debugUserIdOverride = null;
  });

  test('keyboard screenshot consent is independent from general AI consent',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      '${AiDataSharingConsent.acceptedKeyForTesting}::owner-1',
      true,
    );

    expect(await AiDataSharingConsent.hasKeyboardScreenshotConsent(), isFalse);
  });

  test('partner sharing defaults off and cannot enable before consent',
      () async {
    expect(
      await AiDataSharingConsent.hasKeyboardPartnerContextSharingEnabled(),
      isFalse,
    );
    expect(
      await AiDataSharingConsent.setKeyboardPartnerContextSharingEnabled(true),
      isFalse,
    );
  });

  test('revoking screenshot consent also revokes partner context sharing',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      '${AiDataSharingConsent.keyboardScreenshotConsentKey}::owner-1',
      true,
    );
    await prefs.setString(
      '${AiDataSharingConsent.keyboardScreenshotConsentAcceptedAtKey}::owner-1',
      DateTime.utc(2026, 7, 27).toIso8601String(),
    );
    expect(
      await AiDataSharingConsent.setKeyboardPartnerContextSharingEnabled(true),
      isTrue,
    );

    await AiDataSharingConsent.revokeKeyboardScreenshotConsent();

    expect(await AiDataSharingConsent.hasKeyboardScreenshotConsent(), isFalse);
    expect(
      await AiDataSharingConsent.keyboardScreenshotConsentAcceptedAt(),
      isNull,
    );
    expect(
      await AiDataSharingConsent.hasKeyboardPartnerContextSharingEnabled(),
      isFalse,
    );
  });

  test('consent revocation purges native context without a published snapshot',
      () async {
    final bridge = _RecordingKeyboardContextBridge();
    final coordinator = KeyboardScreenshotPrivacyCoordinator(
      contextSync: KeyboardContextSyncCoordinator(bridge: bridge),
    );

    await coordinator.revokeScreenshotConsent(ownerUserId: 'owner-1');

    expect(bridge.publishedSnapshots, isEmpty);
    expect(bridge.purgeScopes, [KeyboardContextPurgeScope.consentRevoked]);
    expect(await AiDataSharingConsent.hasKeyboardScreenshotConsent(), isFalse);
  });

  test('failed native purge still invalidates local consent first', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      '${AiDataSharingConsent.keyboardScreenshotConsentKey}::owner-1',
      true,
    );
    await prefs.setString(
      '${AiDataSharingConsent.keyboardScreenshotConsentAcceptedAtKey}::owner-1',
      DateTime.utc(2026, 7, 27).toIso8601String(),
    );
    final coordinator = KeyboardScreenshotPrivacyCoordinator(
      contextSync: KeyboardContextSyncCoordinator(
        bridge: _RecordingKeyboardContextBridge(
          purgeError: StateError('native purge failed'),
        ),
      ),
    );

    await expectLater(
      coordinator.revokeScreenshotConsent(ownerUserId: 'owner-1'),
      throwsA(isA<KeyboardPrivacyPurgeException>()),
    );

    expect(await AiDataSharingConsent.hasKeyboardScreenshotConsent(), isFalse);
    expect(
      prefs.getString(
        KeyboardScreenshotPrivacyKeys.nativeCleanupPendingScope,
      ),
      KeyboardContextPurgeScope.consentRevoked.wireName,
    );
  });

  test('revocation keeps the initiating owner bound across native purge',
      () async {
    var currentOwner = 'owner-1';
    AiDataSharingConsent.debugUserIdOverride = () => currentOwner;
    final prefs = await SharedPreferences.getInstance();
    for (final owner in ['owner-1', 'owner-2']) {
      await prefs.setBool(
        '${AiDataSharingConsent.keyboardScreenshotConsentKey}::$owner',
        true,
      );
      await prefs.setString(
        '${AiDataSharingConsent.keyboardScreenshotConsentAcceptedAtKey}::$owner',
        DateTime.utc(2026, 7, 27).toIso8601String(),
      );
    }
    final coordinator = KeyboardScreenshotPrivacyCoordinator(
      contextSync: KeyboardContextSyncCoordinator(
        bridge: _RecordingKeyboardContextBridge(
          onPurge: () => currentOwner = 'owner-2',
        ),
      ),
    );

    await coordinator.revokeScreenshotConsent();

    expect(
      prefs.getBool(
        '${AiDataSharingConsent.keyboardScreenshotConsentKey}::owner-1',
      ),
      isNull,
    );
    expect(
      prefs.getBool(
        '${AiDataSharingConsent.keyboardScreenshotConsentKey}::owner-2',
      ),
      isTrue,
    );
  });
}

class _RecordingKeyboardContextBridge implements KeyboardContextBridge {
  _RecordingKeyboardContextBridge({this.purgeError, this.onPurge});

  final Object? purgeError;
  final void Function()? onPurge;
  final publishedSnapshots = <KeyboardContextSnapshot>[];
  final purgeScopes = <KeyboardContextPurgeScope>[];

  @override
  Future<KeyboardContextPublishResult> publish(
    KeyboardContextSnapshot snapshot,
  ) async {
    publishedSnapshots.add(snapshot);
    return KeyboardContextPublishResult(storedRevision: snapshot.revision);
  }

  @override
  Future<void> purge(KeyboardContextPurgeScope scope) async {
    purgeScopes.add(scope);
    onPurge?.call();
    final error = purgeError;
    if (error != null) throw error;
  }
}
