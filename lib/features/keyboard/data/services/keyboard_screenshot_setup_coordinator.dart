import '../../../../shared/widgets/ai_data_sharing_consent.dart';
import 'keyboard_photo_authorization_bridge.dart';

enum KeyboardScreenshotSetupResult {
  enabled,
  signedOut,
  consentMissing,
  accountChanged,
  photoDenied,
  photoRestricted,
  photoNotDetermined,
  localStorageFailed,
  nativeSyncFailed,
}

abstract class KeyboardScreenshotSetupEnabling {
  Future<KeyboardScreenshotSetupResult> enableAfterConsent();

  Future<bool> hasEnabledSetup();
}

typedef KeyboardOwnerUserIdResolver = String? Function();
typedef KeyboardScreenshotConsentChecker = Future<bool> Function();
typedef KeyboardScreenshotConsentAcceptedAtReader = Future<DateTime?>
    Function();
typedef KeyboardScreenshotDetectionReader = Future<bool> Function();
typedef KeyboardScreenshotDetectionWriter = Future<bool> Function(bool value);
typedef KeyboardScreenshotSetupClock = DateTime Function();

/// Completes the privacy-sensitive part of screenshot setup after the user has
/// accepted the disclosure in Flutter.
///
/// The account and receipt are re-checked after every asynchronous boundary.
/// Only Photos `.authorized` / `.limited`, a durable local setting, and an
/// owner-bound App Group receipt can produce [KeyboardScreenshotSetupResult.enabled].
class KeyboardScreenshotSetupCoordinator
    implements KeyboardScreenshotSetupEnabling {
  const KeyboardScreenshotSetupCoordinator({
    required KeyboardPhotoAuthorizationRequesting photoAuthorization,
    required KeyboardScreenshotConsentReceiptPublishing receiptPublisher,
    required KeyboardOwnerUserIdResolver ownerUserId,
    required KeyboardScreenshotConsentChecker hasConsent,
    required KeyboardScreenshotConsentAcceptedAtReader consentAcceptedAt,
    required KeyboardScreenshotDetectionReader isDetectionEnabled,
    required KeyboardScreenshotDetectionWriter setDetectionEnabled,
    KeyboardScreenshotSetupClock clock = DateTime.now,
  })  : _photoAuthorization = photoAuthorization,
        _receiptPublisher = receiptPublisher,
        _ownerUserId = ownerUserId,
        _hasConsent = hasConsent,
        _consentAcceptedAt = consentAcceptedAt,
        _isDetectionEnabled = isDetectionEnabled,
        _setDetectionEnabled = setDetectionEnabled,
        _clock = clock;

  final KeyboardPhotoAuthorizationRequesting _photoAuthorization;
  final KeyboardScreenshotConsentReceiptPublishing _receiptPublisher;
  final KeyboardOwnerUserIdResolver _ownerUserId;
  final KeyboardScreenshotConsentChecker _hasConsent;
  final KeyboardScreenshotConsentAcceptedAtReader _consentAcceptedAt;
  final KeyboardScreenshotDetectionReader _isDetectionEnabled;
  final KeyboardScreenshotDetectionWriter _setDetectionEnabled;
  final KeyboardScreenshotSetupClock _clock;

  @override
  Future<bool> hasEnabledSetup() async {
    final owner = _normalizedOwner();
    if (owner == null) return false;
    try {
      if (!await _isDetectionEnabled() || !_sameOwner(owner)) {
        return false;
      }
      final acceptedAt = await _validConsentReceipt(owner);
      if (acceptedAt == null) return false;
      final verified =
          await _receiptPublisher.hasUsableScreenshotConsentReceipt(
        ownerUserId: owner,
        version: AiDataSharingConsent.keyboardScreenshotConsentKey,
        acceptedAt: acceptedAt,
      );
      if (!verified || !_sameOwner(owner)) return false;
      final authorization =
          await _photoAuthorization.currentReadWriteAuthorization();
      return _sameOwner(owner) &&
          (authorization == KeyboardPhotoAuthorizationStatus.authorized ||
              authorization == KeyboardPhotoAuthorizationStatus.limited);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<KeyboardScreenshotSetupResult> enableAfterConsent() async {
    final owner = _normalizedOwner();
    if (owner == null) {
      return await _clearReceipt()
          ? KeyboardScreenshotSetupResult.signedOut
          : KeyboardScreenshotSetupResult.nativeSyncFailed;
    }

    final acceptedAt = await _validConsentReceipt(owner);
    if (acceptedAt == null) {
      final disabled = await _disableAndClearIfCurrent(owner);
      if (!disabled) {
        return KeyboardScreenshotSetupResult.nativeSyncFailed;
      }
      return _sameOwner(owner)
          ? KeyboardScreenshotSetupResult.consentMissing
          : KeyboardScreenshotSetupResult.accountChanged;
    }

    final int expectedEpoch;
    try {
      expectedEpoch = await _receiptPublisher.beginScreenshotConsentSetup();
    } catch (_) {
      await _disableAndClearIfCurrent(owner);
      return KeyboardScreenshotSetupResult.nativeSyncFailed;
    }
    if (!_sameOwner(owner)) {
      await _disableAndClearIfCurrent(owner);
      return KeyboardScreenshotSetupResult.accountChanged;
    }

    final KeyboardPhotoAuthorizationStatus authorization;
    try {
      authorization = await _photoAuthorization.requestReadWriteAuthorization();
    } catch (_) {
      await _disableAndClearIfCurrent(owner);
      return KeyboardScreenshotSetupResult.nativeSyncFailed;
    }
    if (authorization != KeyboardPhotoAuthorizationStatus.authorized &&
        authorization != KeyboardPhotoAuthorizationStatus.limited) {
      final disabled = await _disableAndClearIfCurrent(owner);
      if (!disabled) {
        return KeyboardScreenshotSetupResult.nativeSyncFailed;
      }
      return switch (authorization) {
        KeyboardPhotoAuthorizationStatus.denied =>
          KeyboardScreenshotSetupResult.photoDenied,
        KeyboardPhotoAuthorizationStatus.restricted =>
          KeyboardScreenshotSetupResult.photoRestricted,
        KeyboardPhotoAuthorizationStatus.notDetermined =>
          KeyboardScreenshotSetupResult.photoNotDetermined,
        KeyboardPhotoAuthorizationStatus.authorized ||
        KeyboardPhotoAuthorizationStatus.limited =>
          throw StateError('unreachable photo authorization state'),
      };
    }

    final freshAcceptedAt = await _validConsentReceipt(owner);
    if (freshAcceptedAt == null ||
        freshAcceptedAt.toUtc() != acceptedAt.toUtc()) {
      final disabled = await _disableAndClearIfCurrent(owner);
      if (!disabled) {
        return KeyboardScreenshotSetupResult.nativeSyncFailed;
      }
      return _sameOwner(owner)
          ? KeyboardScreenshotSetupResult.consentMissing
          : KeyboardScreenshotSetupResult.accountChanged;
    }

    bool settingWritten;
    try {
      settingWritten = await _setDetectionEnabled(true);
    } catch (_) {
      return await _clearReceipt()
          ? KeyboardScreenshotSetupResult.localStorageFailed
          : KeyboardScreenshotSetupResult.nativeSyncFailed;
    }
    if (!settingWritten || !_sameOwner(owner)) {
      final cleared = await _clearReceipt();
      if (!cleared) {
        return KeyboardScreenshotSetupResult.nativeSyncFailed;
      }
      return _sameOwner(owner)
          ? KeyboardScreenshotSetupResult.localStorageFailed
          : KeyboardScreenshotSetupResult.accountChanged;
    }

    try {
      await _receiptPublisher.publishScreenshotConsentReceipt(
        KeyboardScreenshotConsentReceipt(
          ownerUserId: owner,
          version: AiDataSharingConsent.keyboardScreenshotConsentKey,
          acceptedAt: acceptedAt,
          updatedAt: _canonicalUtcMilliseconds(_clock()),
        ),
        expectedEpoch: expectedEpoch,
      );
    } catch (_) {
      await _disableAndClearIfCurrent(owner);
      return KeyboardScreenshotSetupResult.nativeSyncFailed;
    }

    final finalAcceptedAt = await _validConsentReceipt(owner);
    if (finalAcceptedAt == null ||
        finalAcceptedAt.toUtc() != acceptedAt.toUtc()) {
      final disabled = await _disableAndClearIfCurrent(owner);
      if (!disabled) {
        return KeyboardScreenshotSetupResult.nativeSyncFailed;
      }
      return _sameOwner(owner)
          ? KeyboardScreenshotSetupResult.consentMissing
          : KeyboardScreenshotSetupResult.accountChanged;
    }
    return KeyboardScreenshotSetupResult.enabled;
  }

  Future<DateTime?> _validConsentReceipt(String owner) async {
    if (!_sameOwner(owner) || !await _hasConsent() || !_sameOwner(owner)) {
      return null;
    }
    final acceptedAt = await _consentAcceptedAt();
    if (!_sameOwner(owner) ||
        acceptedAt == null ||
        acceptedAt.toUtc().isAfter(_clock().toUtc())) {
      return null;
    }
    return _canonicalUtcMilliseconds(acceptedAt);
  }

  DateTime _canonicalUtcMilliseconds(DateTime value) {
    return DateTime.fromMillisecondsSinceEpoch(
      value.toUtc().millisecondsSinceEpoch,
      isUtc: true,
    );
  }

  String? _normalizedOwner() {
    final value = _ownerUserId()?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  bool _sameOwner(String expected) => _normalizedOwner() == expected;

  Future<bool> _disableAndClearIfCurrent(String owner) async {
    var disabled = true;
    if (_sameOwner(owner)) {
      try {
        disabled = await _setDetectionEnabled(false);
      } catch (_) {
        disabled = false;
      }
    }
    final cleared = await _clearReceipt();
    return disabled && cleared;
  }

  Future<bool> _clearReceipt() async {
    try {
      await _receiptPublisher.clearScreenshotConsentReceipt();
      return true;
    } catch (_) {
      return false;
    }
  }
}
