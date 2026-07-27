import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/core/services/keyboard_privacy_purge_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      '${KeyboardScreenshotPrivacyKeys.consent}::owner-a': true,
      '${KeyboardScreenshotPrivacyKeys.consentAcceptedAt}::owner-a':
          '2026-07-27T00:00:00.000Z',
      '${KeyboardScreenshotPrivacyKeys.latestScreenshotDetection}::owner-a':
          true,
      '${KeyboardScreenshotPrivacyKeys.partnerContextSharing}::owner-a': true,
      '${KeyboardScreenshotPrivacyKeys.consent}::owner-b': true,
      KeyboardScreenshotPrivacyKeys.consent: true,
      KeyboardScreenshotPrivacyKeys.consentAcceptedAt:
          '2026-07-01T00:00:00.000Z',
    });
  });

  test('purge invalidates owner local consent before native purge', () async {
    final channel = _RecordingPurgeChannel(
      onInvoke: () async {
        final preferences = await SharedPreferences.getInstance();
        for (final key in _privacyKeys) {
          expect(preferences.containsKey('$key::owner-a'), isFalse);
          expect(preferences.containsKey(key), isFalse);
        }
        expect(
          preferences.getBool(
            '${KeyboardScreenshotPrivacyKeys.consent}::owner-b',
          ),
          isTrue,
        );
      },
    );
    final service = KeyboardPrivacyPurgeService(channel: channel);

    await service.purge(
      KeyboardContextPurgeScope.logout,
      ownerUserId: 'owner-a',
    );

    expect(channel.scopes, [KeyboardContextPurgeScope.logout]);
  });

  test('unknown owner removes every legacy and account-scoped grant', () async {
    final service = KeyboardPrivacyPurgeService(
      channel: _RecordingPurgeChannel(),
    );

    await service.purge(
      KeyboardContextPurgeScope.logout,
      ownerUserId: null,
    );

    final preferences = await SharedPreferences.getInstance();
    for (final key in _privacyKeys) {
      expect(
        preferences.getKeys().where(
              (candidate) => candidate == key || candidate.startsWith('$key::'),
            ),
        isEmpty,
      );
    }
  });

  test('native failure cannot restore locally revoked consent', () async {
    final service = KeyboardPrivacyPurgeService(
      channel: _RecordingPurgeChannel(
        error: StateError('native channel unavailable'),
      ),
    );

    await expectLater(
      service.purge(
        KeyboardContextPurgeScope.consentRevoked,
        ownerUserId: 'owner-a',
      ),
      throwsA(isA<KeyboardPrivacyPurgeException>()),
    );

    final preferences = await SharedPreferences.getInstance();
    for (final key in _privacyKeys) {
      expect(preferences.containsKey('$key::owner-a'), isFalse);
    }
    expect(
      preferences.getBool(
        '${KeyboardScreenshotPrivacyKeys.consent}::owner-b',
      ),
      isTrue,
    );
    expect(
      preferences.getString(
        KeyboardScreenshotPrivacyKeys.nativeCleanupPendingScope,
      ),
      KeyboardContextPurgeScope.consentRevoked.wireName,
    );
  });

  test('pending native cleanup survives recreation and keeps exact scope',
      () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      KeyboardScreenshotPrivacyKeys.nativeCleanupPendingScope,
      KeyboardContextPurgeScope.accountDeletion.wireName,
    );
    final channel = _RecordingPurgeChannel();

    await KeyboardPrivacyPurgeService(
      channel: channel,
    ).retryPendingNativeCleanup();

    expect(channel.scopes, [KeyboardContextPurgeScope.accountDeletion]);
    expect(
      preferences.containsKey(
        KeyboardScreenshotPrivacyKeys.nativeCleanupPendingScope,
      ),
      isFalse,
    );
  });

  test('strong pending cleanup cannot be downgraded by a later callback',
      () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      KeyboardScreenshotPrivacyKeys.nativeCleanupPendingScope,
      KeyboardContextPurgeScope.accountDeletion.wireName,
    );
    var weakerCallbackCalled = false;
    final channel = _RecordingPurgeChannel();
    final service = KeyboardPrivacyPurgeService(channel: channel);

    await service.purgeNativeWithRetryMarker(
      KeyboardContextPurgeScope.consentRevoked,
      operation: () async => weakerCallbackCalled = true,
    );

    expect(weakerCallbackCalled, isFalse);
    expect(channel.scopes, [KeyboardContextPurgeScope.accountDeletion]);
  });

  test('unknown pending scope fails closed to account deletion cleanup',
      () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      KeyboardScreenshotPrivacyKeys.nativeCleanupPendingScope,
      'unknown_future_scope',
    );
    final channel = _RecordingPurgeChannel();

    await KeyboardPrivacyPurgeService(
      channel: channel,
    ).retryPendingNativeCleanup();

    expect(channel.scopes, [KeyboardContextPurgeScope.accountDeletion]);
  });
}

const _privacyKeys = [
  KeyboardScreenshotPrivacyKeys.consent,
  KeyboardScreenshotPrivacyKeys.consentAcceptedAt,
  KeyboardScreenshotPrivacyKeys.latestScreenshotDetection,
  KeyboardScreenshotPrivacyKeys.partnerContextSharing,
];

class _RecordingPurgeChannel implements KeyboardPrivacyPurgeChannel {
  _RecordingPurgeChannel({
    this.onInvoke,
    this.error,
  });

  final Future<void> Function()? onInvoke;
  final Object? error;
  final scopes = <KeyboardContextPurgeScope>[];

  @override
  Future<void> invokePurge(KeyboardContextPurgeScope scope) async {
    scopes.add(scope);
    await onInvoke?.call();
    final invocationError = error;
    if (invocationError != null) throw invocationError;
  }
}
