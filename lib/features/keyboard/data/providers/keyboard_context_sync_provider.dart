import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/keyboard_privacy_purge_service.dart';
import '../../domain/entities/keyboard_context_snapshot.dart';
import '../../domain/services/keyboard_context_snapshot_builder.dart';
import '../services/keyboard_context_bridge.dart';
import '../services/keyboard_photo_authorization_bridge.dart';
import '../services/keyboard_screenshot_setup_coordinator.dart';
import '../../../../shared/widgets/ai_data_sharing_consent.dart';
import '../../../../core/services/supabase_service.dart';

final keyboardContextSnapshotBuilderProvider =
    Provider<KeyboardContextSnapshotBuilder>((ref) {
  return KeyboardContextSnapshotBuilder();
});

final keyboardPrivacyPurgeServiceProvider =
    Provider<KeyboardPrivacyPurgeService>((ref) {
  return KeyboardPrivacyPurgeService.live;
});

final keyboardContextBridgeProvider = Provider<KeyboardContextBridge>((ref) {
  return MethodChannelKeyboardContextBridge();
});

final keyboardContextSyncCoordinatorProvider =
    Provider<KeyboardContextSyncCoordinator>((ref) {
  return KeyboardContextSyncCoordinator(
    bridge: ref.watch(keyboardContextBridgeProvider),
  );
});

final keyboardScreenshotPrivacyCoordinatorProvider =
    Provider<KeyboardScreenshotPrivacyCoordinator>((ref) {
  return KeyboardScreenshotPrivacyCoordinator(
    contextSync: ref.watch(keyboardContextSyncCoordinatorProvider),
    privacyPurgeService: ref.watch(keyboardPrivacyPurgeServiceProvider),
  );
});

final keyboardPhotoAuthorizationBridgeProvider =
    Provider<MethodChannelKeyboardPhotoAuthorizationBridge>((ref) {
  return MethodChannelKeyboardPhotoAuthorizationBridge();
});

final keyboardScreenshotSetupCoordinatorProvider =
    Provider<KeyboardScreenshotSetupEnabling>((ref) {
  final nativeBridge = ref.watch(keyboardPhotoAuthorizationBridgeProvider);
  return KeyboardScreenshotSetupCoordinator(
    photoAuthorization: nativeBridge,
    receiptPublisher: nativeBridge,
    ownerUserId: () => SupabaseService.currentUser?.id,
    hasConsent: AiDataSharingConsent.hasKeyboardScreenshotConsent,
    consentAcceptedAt: AiDataSharingConsent.keyboardScreenshotConsentAcceptedAt,
    isDetectionEnabled:
        AiDataSharingConsent.hasKeyboardLatestScreenshotDetectionEnabled,
    setDetectionEnabled:
        AiDataSharingConsent.setKeyboardLatestScreenshotDetectionEnabled,
  );
});

/// An explicit coordinator rather than an eager listener: no snapshot is
/// published until the app has resolved owner, consent and allowlisted inputs.
class KeyboardContextSyncCoordinator {
  const KeyboardContextSyncCoordinator({required KeyboardContextBridge bridge})
      : _bridge = bridge;

  final KeyboardContextBridge _bridge;

  Future<KeyboardContextPublishResult> publish(
    KeyboardContextSnapshot snapshot,
  ) {
    return _bridge.publish(snapshot);
  }

  Future<void> purge(KeyboardContextPurgeScope scope) => _bridge.purge(scope);
}

class KeyboardScreenshotPrivacyCoordinator {
  KeyboardScreenshotPrivacyCoordinator({
    required KeyboardContextSyncCoordinator contextSync,
    KeyboardPrivacyPurgeService? privacyPurgeService,
  })  : _contextSync = contextSync,
        _privacyPurgeService =
            privacyPurgeService ?? KeyboardPrivacyPurgeService.live;

  final KeyboardContextSyncCoordinator _contextSync;
  final KeyboardPrivacyPurgeService _privacyPurgeService;

  Future<void> revokeScreenshotConsent({String? ownerUserId}) async {
    await AiDataSharingConsent.revokeKeyboardScreenshotConsent(
      ownerUserId: ownerUserId,
      privacyPurgeService: _privacyPurgeService,
      afterLocalRevocation: () =>
          _contextSync.purge(KeyboardContextPurgeScope.consentRevoked),
    );
  }
}
