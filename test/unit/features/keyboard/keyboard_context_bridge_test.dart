import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/keyboard/data/services/keyboard_context_bridge.dart';
import 'package:vibesync/features/keyboard/domain/entities/keyboard_context_snapshot.dart';

void main() {
  test('publishes typed snapshot through injectable channel boundary',
      () async {
    final channel = _RecordingChannel({'storedRevision': 'revision-1'});
    final bridge = MethodChannelKeyboardContextBridge(channel: channel);
    final snapshot = _snapshot();

    final result = await bridge.publish(snapshot);

    expect(result.storedRevision, 'revision-1');
    expect(channel.method, 'writeSnapshot');
    expect(channel.arguments, snapshot.toJson());
  });

  test('logout purge preserves pending replay identities', () async {
    final channel = _RecordingChannel(null);
    final bridge = MethodChannelKeyboardContextBridge(channel: channel);

    await bridge.purge(KeyboardContextPurgeScope.logout);

    expect(channel.method, 'purgeContext');
    expect(channel.arguments, {
      'scope': 'logout',
      'purgePendingReplayIdentity': false,
    });
  });

  test('account deletion purge includes pending replay identities', () async {
    final channel = _RecordingChannel(null);
    final bridge = MethodChannelKeyboardContextBridge(channel: channel);

    await bridge.purge(KeyboardContextPurgeScope.accountDeletion);

    expect(channel.arguments, {
      'scope': 'account_deletion',
      'purgePendingReplayIdentity': true,
    });
  });
}

class _RecordingChannel implements KeyboardContextChannel {
  _RecordingChannel(this.response);

  final Object? response;
  String? method;
  Object? arguments;

  @override
  Future<Object?> invoke(String method, [Object? arguments]) async {
    this.method = method;
    this.arguments = arguments;
    return response;
  }
}

KeyboardContextSnapshot _snapshot() {
  final generatedAt = DateTime.utc(2026, 7, 27, 4);
  return KeyboardContextSnapshot(
    schemaVersion: 1,
    ownerUserId: 'owner-1',
    revision: 'revision-1',
    generatedAt: generatedAt,
    expiresAt: generatedAt.add(const Duration(hours: 24)),
    consent: KeyboardContextConsent(
      version: KeyboardContextConsent.currentVersion,
      acceptedAt: generatedAt,
      latestScreenshotDetectionEnabled: true,
      partnerContextSharingEnabled: false,
    ),
    globalVoice: KeyboardContextVoice(
      primary: KeyboardVoice.steady,
      secondary: null,
      sourceUpdatedAt: generatedAt,
    ),
    partners: const [],
  );
}
