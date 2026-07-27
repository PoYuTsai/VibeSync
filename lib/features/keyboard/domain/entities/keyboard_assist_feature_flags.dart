import 'package:flutter/foundation.dart';

/// A short-lived, owner-bound receipt created only after an authenticated
/// capability response. It is a cache record, not a second client allowlist.
@immutable
class KeyboardAssistCapabilityReceipt {
  const KeyboardAssistCapabilityReceipt({
    required this.contractVersion,
    required this.ownerUserId,
    required this.enabled,
    required this.pipelineVersion,
    required this.receivedAt,
    required this.expiresAt,
  });

  static const screenshotV1ContractVersion = 'keyboard-assist-v1';
  static const linkedPartnerV2ContractVersion = 'keyboard-assist-v2';
  static const maximumLifetime = Duration(minutes: 5);

  final String contractVersion;
  final String ownerUserId;
  final bool enabled;
  final String pipelineVersion;
  final DateTime receivedAt;
  final DateTime expiresAt;

  bool isUsable({
    required String expectedContractVersion,
    required String expectedOwnerUserId,
    required DateTime now,
  }) {
    final expectedOwner = expectedOwnerUserId.trim();
    final lifetime = expiresAt.difference(receivedAt);
    return enabled &&
        contractVersion == expectedContractVersion &&
        expectedOwner.isNotEmpty &&
        expectedOwner == expectedOwnerUserId &&
        ownerUserId == expectedOwner &&
        _isSafePipelineVersion(pipelineVersion) &&
        !receivedAt.isAfter(now) &&
        expiresAt.isAfter(now) &&
        lifetime > Duration.zero &&
        lifetime <= maximumLifetime;
  }

  static bool _isSafePipelineVersion(String value) {
    return RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$').hasMatch(value);
  }
}

/// Fail-closed capability state. An absent receipt is always disabled.
///
/// V2 has its own authenticated receipt so a V1 capability can never
/// accidentally enable linked-partner context.
@immutable
class KeyboardAssistFeatureFlags {
  const KeyboardAssistFeatureFlags({
    this.screenshotReceipt,
    this.linkedPartnerV2Receipt,
  });

  final KeyboardAssistCapabilityReceipt? screenshotReceipt;
  final KeyboardAssistCapabilityReceipt? linkedPartnerV2Receipt;

  bool canSendScreenshot({
    required String ownerUserId,
    required DateTime now,
  }) {
    return screenshotReceipt?.isUsable(
          expectedContractVersion:
              KeyboardAssistCapabilityReceipt.screenshotV1ContractVersion,
          expectedOwnerUserId: ownerUserId,
          now: now,
        ) ==
        true;
  }

  bool canUseLinkedPartner({
    required String ownerUserId,
    required DateTime now,
    required bool hasConsent,
    required bool hasValidContext,
  }) {
    return canSendScreenshot(ownerUserId: ownerUserId, now: now) &&
        linkedPartnerV2Receipt?.isUsable(
              expectedContractVersion: KeyboardAssistCapabilityReceipt
                  .linkedPartnerV2ContractVersion,
              expectedOwnerUserId: ownerUserId,
              now: now,
            ) ==
            true &&
        hasConsent &&
        hasValidContext;
  }
}
