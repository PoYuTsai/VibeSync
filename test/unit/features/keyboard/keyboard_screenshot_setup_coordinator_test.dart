import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/keyboard/data/services/keyboard_photo_authorization_bridge.dart';
import 'package:vibesync/features/keyboard/data/services/keyboard_screenshot_setup_coordinator.dart';

void main() {
  const acceptedAt = '2026-07-01T00:00:00.123456Z';
  const canonicalAcceptedAt = '2026-07-01T00:00:00.123Z';
  final now = DateTime.utc(2026, 7, 27, 12);

  test('authorized Photos access writes local setting then native receipt',
      () async {
    final events = <String>[];
    final native = _FakeNativeBridge(
      status: KeyboardPhotoAuthorizationStatus.authorized,
      events: events,
    );
    final harness = _Harness(
      native: native,
      events: events,
      now: now,
      acceptedAt: DateTime.parse(acceptedAt),
    );

    expect(
      await harness.coordinator.enableAfterConsent(),
      KeyboardScreenshotSetupResult.enabled,
    );
    expect(events, [
      'hasConsent',
      'acceptedAt',
      'beginSetup',
      'requestPhotoAuthorization',
      'hasConsent',
      'acceptedAt',
      'setDetection:true',
      'publishReceipt',
      'hasConsent',
      'acceptedAt',
    ]);
    expect(native.receipts.single.ownerUserId, 'owner-1');
    expect(
      native.receipts.single.version,
      'keyboard_screenshot_ai_202607_v2',
    );
    expect(
      native.receipts.single.acceptedAt.toIso8601String(),
      canonicalAcceptedAt,
    );
    expect(native.receipts.single.updatedAt, now);
    expect(native.publishedEpochs, [7]);
    expect(await harness.coordinator.hasEnabledSetup(), isTrue);
    expect(
      events,
      containsAllInOrder([
        'verifyReceipt',
        'currentPhotoAuthorization',
      ]),
    );
  });

  test('enabled setup fails closed when Photos access is no longer usable',
      () async {
    final events = <String>[];
    final native = _FakeNativeBridge(
      status: KeyboardPhotoAuthorizationStatus.authorized,
      events: events,
    );
    final harness = _Harness(
      native: native,
      events: events,
      now: now,
      acceptedAt: DateTime.parse(acceptedAt),
    );
    expect(
      await harness.coordinator.enableAfterConsent(),
      KeyboardScreenshotSetupResult.enabled,
    );

    native.currentStatus = KeyboardPhotoAuthorizationStatus.denied;

    expect(await harness.coordinator.hasEnabledSetup(), isFalse);
    expect(events.last, 'currentPhotoAuthorization');
  });

  for (final entry in {
    KeyboardPhotoAuthorizationStatus.denied:
        KeyboardScreenshotSetupResult.photoDenied,
    KeyboardPhotoAuthorizationStatus.restricted:
        KeyboardScreenshotSetupResult.photoRestricted,
    KeyboardPhotoAuthorizationStatus.notDetermined:
        KeyboardScreenshotSetupResult.photoNotDetermined,
  }.entries) {
    test('${entry.key.name} Photos access never enables or publishes',
        () async {
      final events = <String>[];
      final native = _FakeNativeBridge(status: entry.key, events: events);
      final harness = _Harness(
        native: native,
        events: events,
        now: now,
        acceptedAt: DateTime.parse(acceptedAt),
      );

      expect(
        await harness.coordinator.enableAfterConsent(),
        entry.value,
      );
      expect(events, contains('setDetection:false'));
      expect(events, contains('clearReceipt'));
      expect(events, isNot(contains('setDetection:true')));
      expect(events, isNot(contains('publishReceipt')));
    });
  }

  test('missing consent fails before asking Photos permission', () async {
    final events = <String>[];
    final native = _FakeNativeBridge(
      status: KeyboardPhotoAuthorizationStatus.authorized,
      events: events,
    );
    final harness = _Harness(
      native: native,
      events: events,
      now: now,
      acceptedAt: DateTime.parse(acceptedAt),
      hasConsent: false,
    );

    expect(
      await harness.coordinator.enableAfterConsent(),
      KeyboardScreenshotSetupResult.consentMissing,
    );
    expect(events, isNot(contains('requestPhotoAuthorization')));
    expect(events, isNot(contains('publishReceipt')));
  });

  test('account switch while Photos prompt is open fails closed', () async {
    final events = <String>[];
    late _Harness harness;
    final native = _FakeNativeBridge(
      status: KeyboardPhotoAuthorizationStatus.limited,
      events: events,
      afterAuthorization: () => harness.owner = 'owner-2',
    );
    harness = _Harness(
      native: native,
      events: events,
      now: now,
      acceptedAt: DateTime.parse(acceptedAt),
    );

    expect(
      await harness.coordinator.enableAfterConsent(),
      KeyboardScreenshotSetupResult.accountChanged,
    );
    expect(events, contains('clearReceipt'));
    expect(events, isNot(contains('setDetection:true')));
    expect(events, isNot(contains('publishReceipt')));
  });

  test('native receipt failure rolls local setting back', () async {
    final events = <String>[];
    final native = _FakeNativeBridge(
      status: KeyboardPhotoAuthorizationStatus.authorized,
      events: events,
      publishError: StateError('app group unavailable'),
    );
    final harness = _Harness(
      native: native,
      events: events,
      now: now,
      acceptedAt: DateTime.parse(acceptedAt),
    );

    expect(
      await harness.coordinator.enableAfterConsent(),
      KeyboardScreenshotSetupResult.nativeSyncFailed,
    );
    expect(
      events,
      containsAllInOrder([
        'setDetection:true',
        'publishReceipt',
        'setDetection:false',
        'clearReceipt',
      ]),
    );
  });

  test('signed-out setup clears any stale native receipt', () async {
    final events = <String>[];
    final native = _FakeNativeBridge(
      status: KeyboardPhotoAuthorizationStatus.authorized,
      events: events,
    );
    final harness = _Harness(
      native: native,
      events: events,
      now: now,
      acceptedAt: DateTime.parse(acceptedAt),
    )..owner = null;

    expect(
      await harness.coordinator.enableAfterConsent(),
      KeyboardScreenshotSetupResult.signedOut,
    );
    expect(events, ['clearReceipt']);
  });

  test('failed native clear never reports a benign disabled outcome', () async {
    final events = <String>[];
    final native = _FakeNativeBridge(
      status: KeyboardPhotoAuthorizationStatus.denied,
      events: events,
      clearError: StateError('channel unavailable'),
    );
    final harness = _Harness(
      native: native,
      events: events,
      now: now,
      acceptedAt: DateTime.parse(acceptedAt),
    );

    expect(
      await harness.coordinator.enableAfterConsent(),
      KeyboardScreenshotSetupResult.nativeSyncFailed,
    );
    expect(events, containsAll(['setDetection:false', 'clearReceipt']));
  });
}

class _Harness {
  _Harness({
    required _FakeNativeBridge native,
    required this.events,
    required DateTime now,
    required DateTime? acceptedAt,
    bool hasConsent = true,
  })  : _acceptedAt = acceptedAt,
        _hasConsent = hasConsent {
    coordinator = KeyboardScreenshotSetupCoordinator(
      photoAuthorization: native,
      receiptPublisher: native,
      ownerUserId: () => owner,
      hasConsent: () async {
        events.add('hasConsent');
        return _hasConsent;
      },
      consentAcceptedAt: () async {
        events.add('acceptedAt');
        return _acceptedAt;
      },
      isDetectionEnabled: () async {
        events.add('isDetectionEnabled');
        return true;
      },
      setDetectionEnabled: (value) async {
        events.add('setDetection:$value');
        return true;
      },
      clock: () => now,
    );
  }

  final List<String> events;
  final DateTime? _acceptedAt;
  final bool _hasConsent;
  String? owner = 'owner-1';
  late final KeyboardScreenshotSetupCoordinator coordinator;
}

class _FakeNativeBridge
    implements
        KeyboardPhotoAuthorizationRequesting,
        KeyboardScreenshotConsentReceiptPublishing {
  _FakeNativeBridge({
    required this.status,
    required this.events,
    this.afterAuthorization,
    this.publishError,
    this.clearError,
  });

  final KeyboardPhotoAuthorizationStatus status;
  final List<String> events;
  final void Function()? afterAuthorization;
  final Object? publishError;
  final Object? clearError;
  final receipts = <KeyboardScreenshotConsentReceipt>[];
  final publishedEpochs = <int>[];
  KeyboardPhotoAuthorizationStatus? currentStatus;

  @override
  Future<int> beginScreenshotConsentSetup() async {
    events.add('beginSetup');
    return 7;
  }

  @override
  Future<KeyboardPhotoAuthorizationStatus>
      currentReadWriteAuthorization() async {
    events.add('currentPhotoAuthorization');
    return currentStatus ?? status;
  }

  @override
  Future<KeyboardPhotoAuthorizationStatus>
      requestReadWriteAuthorization() async {
    events.add('requestPhotoAuthorization');
    afterAuthorization?.call();
    return status;
  }

  @override
  Future<void> publishScreenshotConsentReceipt(
    KeyboardScreenshotConsentReceipt receipt, {
    required int expectedEpoch,
  }) async {
    events.add('publishReceipt');
    final error = publishError;
    if (error != null) throw error;
    receipts.add(receipt);
    publishedEpochs.add(expectedEpoch);
  }

  @override
  Future<void> clearScreenshotConsentReceipt() async {
    events.add('clearReceipt');
    final error = clearError;
    if (error != null) throw error;
  }

  @override
  Future<bool> hasUsableScreenshotConsentReceipt({
    required String ownerUserId,
    required String version,
    required DateTime acceptedAt,
  }) async {
    events.add('verifyReceipt');
    return receipts.any(
      (receipt) =>
          receipt.ownerUserId == ownerUserId &&
          receipt.version == version &&
          receipt.acceptedAt.toUtc() == acceptedAt.toUtc(),
    );
  }
}
