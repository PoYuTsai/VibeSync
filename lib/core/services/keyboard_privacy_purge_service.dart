import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum KeyboardContextPurgeScope { logout, consentRevoked, accountDeletion }

extension KeyboardContextPurgeScopeWire on KeyboardContextPurgeScope {
  String get wireName => switch (this) {
        KeyboardContextPurgeScope.logout => 'logout',
        KeyboardContextPurgeScope.consentRevoked => 'consent_revoked',
        KeyboardContextPurgeScope.accountDeletion => 'account_deletion',
      };

  bool get purgePendingReplayIdentity =>
      this == KeyboardContextPurgeScope.accountDeletion;

  static KeyboardContextPurgeScope? tryParse(String? wireName) =>
      switch (wireName) {
        'logout' => KeyboardContextPurgeScope.logout,
        'consent_revoked' => KeyboardContextPurgeScope.consentRevoked,
        'account_deletion' => KeyboardContextPurgeScope.accountDeletion,
        _ => null,
      };
}

class KeyboardScreenshotPrivacyKeys {
  const KeyboardScreenshotPrivacyKeys._();

  static const consent = 'keyboard_screenshot_ai_202607_v1';
  static const consentAcceptedAt =
      'keyboard_screenshot_ai_accepted_at_202607_v1';
  static const latestScreenshotDetection =
      'keyboard_latest_screenshot_detection_202607_v1';
  static const partnerContextSharing =
      'keyboard_partner_context_sharing_202607_v1';
  static const nativeCleanupPendingScope =
      'keyboard_native_privacy_cleanup_pending_scope_202607_v1';

  static String scoped(String key, String? ownerUserId) {
    final owner = ownerUserId?.trim();
    return owner == null || owner.isEmpty ? key : '$key::$owner';
  }
}

abstract class KeyboardPrivacyPurgeChannel {
  Future<void> invokePurge(KeyboardContextPurgeScope scope);
}

class MethodChannelKeyboardPrivacyPurgeChannel
    implements KeyboardPrivacyPurgeChannel {
  const MethodChannelKeyboardPrivacyPurgeChannel();

  static const MethodChannel _channel = MethodChannel(
    'vibesync/keyboard_context',
  );

  @override
  Future<void> invokePurge(KeyboardContextPurgeScope scope) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    await _channel.invokeMethod<void>('purgeContext', {
      'scope': scope.wireName,
      'purgePendingReplayIdentity': scope.purgePendingReplayIdentity,
    });
  }
}

class KeyboardPrivacyPurgeException implements Exception {
  const KeyboardPrivacyPurgeException({
    this.localError,
    this.nativeError,
  });

  final Object? localError;
  final Object? nativeError;

  @override
  String toString() => 'Keyboard privacy purge failed';
}

/// One fail-closed privacy boundary shared by every sign-out, revocation and
/// account-deletion path.
///
/// Local consent is invalidated first. Native purge then advances the App
/// Group consent epoch and clears the receipt, so an enable operation that
/// started before this call cannot write its stale grant back afterward.
class KeyboardPrivacyPurgeService {
  KeyboardPrivacyPurgeService({
    KeyboardPrivacyPurgeChannel channel =
        const MethodChannelKeyboardPrivacyPurgeChannel(),
  }) : _channel = channel;

  final KeyboardPrivacyPurgeChannel _channel;

  static KeyboardPrivacyPurgeService _live = KeyboardPrivacyPurgeService();

  static KeyboardPrivacyPurgeService get live => _live;

  @visibleForTesting
  static set debugLiveOverride(KeyboardPrivacyPurgeService? value) {
    _live = value ?? KeyboardPrivacyPurgeService();
  }

  Future<void> purge(
    KeyboardContextPurgeScope scope, {
    required String? ownerUserId,
    Future<void> Function()? nativeOperation,
  }) async {
    Object? localError;
    Object? nativeError;
    try {
      await clearLocalConsent(ownerUserId: ownerUserId);
    } catch (error) {
      localError = error;
    }
    try {
      await purgeNativeWithRetryMarker(
        scope,
        operation: nativeOperation,
      );
    } catch (error) {
      nativeError = error;
    }
    if (localError != null || nativeError != null) {
      throw KeyboardPrivacyPurgeException(
        localError: localError,
        nativeError: nativeError,
      );
    }
  }

  Future<void> clearLocalConsent({required String? ownerUserId}) async {
    final preferences = await SharedPreferences.getInstance();
    final normalizedOwner = ownerUserId?.trim();
    final hasOwner = normalizedOwner != null && normalizedOwner.isNotEmpty;
    final existingKeys = preferences.getKeys();
    for (final key in [
      KeyboardScreenshotPrivacyKeys.consent,
      KeyboardScreenshotPrivacyKeys.consentAcceptedAt,
      KeyboardScreenshotPrivacyKeys.latestScreenshotDetection,
      KeyboardScreenshotPrivacyKeys.partnerContextSharing,
    ]) {
      final targets = hasOwner
          ? <String>{key, '$key::$normalizedOwner'}
          : existingKeys
              .where(
                (candidate) =>
                    candidate == key || candidate.startsWith('$key::'),
              )
              .toSet();
      for (final target in targets) {
        if (!preferences.containsKey(target)) continue;
        final removed = await preferences.remove(target);
        if (!removed) {
          throw StateError(
            'failed to clear keyboard screenshot privacy state',
          );
        }
      }
    }
  }

  Future<void> purgeNative(KeyboardContextPurgeScope scope) {
    return _channel.invokePurge(scope);
  }

  /// Returns the device-wide native cleanup that still needs to be replayed.
  ///
  /// The marker contains only a fixed operation scope, never an account id or
  /// screenshot-derived content. An unknown value is treated as the strongest
  /// purge so corrupted state cannot weaken an account-deletion cleanup.
  Future<KeyboardContextPurgeScope?> pendingNativeCleanupScope() async {
    final preferences = await SharedPreferences.getInstance();
    final wireName = preferences.getString(
      KeyboardScreenshotPrivacyKeys.nativeCleanupPendingScope,
    );
    if (wireName == null) return null;
    return KeyboardContextPurgeScopeWire.tryParse(wireName) ??
        KeyboardContextPurgeScope.accountDeletion;
  }

  /// Replays a native privacy cleanup after an app restart.
  Future<void> retryPendingNativeCleanup() async {
    final scope = await pendingNativeCleanupScope();
    if (scope == null) return;
    await purgeNativeWithRetryMarker(scope);
  }

  /// Persists native cleanup intent before crossing the platform boundary.
  ///
  /// The marker is removed only after the native purge succeeds. This makes a
  /// channel failure or force-quit recoverable on the next settings-screen
  /// launch. A pending account-deletion purge is never downgraded by a later
  /// logout or consent-revocation attempt.
  Future<void> purgeNativeWithRetryMarker(
    KeyboardContextPurgeScope scope, {
    Future<void> Function()? operation,
  }) async {
    Object? markerError;
    Object? nativeError;
    var effectiveScope = scope;

    SharedPreferences? preferences;
    try {
      preferences = await SharedPreferences.getInstance();
      final existingWireName = preferences.getString(
        KeyboardScreenshotPrivacyKeys.nativeCleanupPendingScope,
      );
      final existing = existingWireName == null
          ? null
          : KeyboardContextPurgeScopeWire.tryParse(existingWireName) ??
              KeyboardContextPurgeScope.accountDeletion;
      if (existing == KeyboardContextPurgeScope.accountDeletion) {
        effectiveScope = existing!;
      }
      final stored = await preferences.setString(
        KeyboardScreenshotPrivacyKeys.nativeCleanupPendingScope,
        effectiveScope.wireName,
      );
      if (!stored) {
        throw StateError('failed to persist native privacy cleanup intent');
      }
    } catch (error) {
      markerError = error;
    }

    try {
      if (operation != null && effectiveScope == scope) {
        await operation();
      } else {
        await purgeNative(effectiveScope);
      }
    } catch (error) {
      nativeError = error;
    }

    if (nativeError == null && preferences != null) {
      try {
        final removed = await preferences.remove(
          KeyboardScreenshotPrivacyKeys.nativeCleanupPendingScope,
        );
        if (!removed &&
            preferences.containsKey(
              KeyboardScreenshotPrivacyKeys.nativeCleanupPendingScope,
            )) {
          throw StateError('failed to clear native privacy cleanup intent');
        }
        markerError = null;
      } catch (error) {
        markerError = error;
      }
    }

    if (markerError != null || nativeError != null) {
      throw KeyboardPrivacyPurgeException(
        localError: markerError,
        nativeError: nativeError,
      );
    }
  }
}
