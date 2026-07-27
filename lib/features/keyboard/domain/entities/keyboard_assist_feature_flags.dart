import 'package:flutter/foundation.dart';

/// A fail-closed client view of server-authoritative Keyboard Assist flags.
///
/// This object never enables a capability on its own. The caller must first
/// receive these values from an authenticated server capability response.
@immutable
class KeyboardAssistFeatureFlags {
  const KeyboardAssistFeatureFlags({
    this.screenshotV1Enabled = false,
    this.screenshotV1Allowlist = const <String>{},
    this.linkedPartnerV2Enabled = false,
    this.parallelGeneratorsEnabled = false,
    this.pipelineVersion = 'compiler-judge-v1',
  });

  final bool screenshotV1Enabled;
  final Set<String> screenshotV1Allowlist;
  final bool linkedPartnerV2Enabled;
  final bool parallelGeneratorsEnabled;
  final String pipelineVersion;

  bool canSendScreenshot({required String ownerUserId}) {
    final owner = ownerUserId.trim();
    return owner.isNotEmpty &&
        screenshotV1Enabled &&
        screenshotV1Allowlist.contains(owner);
  }

  bool canUseLinkedPartner({
    required String ownerUserId,
    required bool clientSupportsV2,
    required bool hasConsent,
    required bool hasValidContext,
  }) {
    return canSendScreenshot(ownerUserId: ownerUserId) &&
        linkedPartnerV2Enabled &&
        clientSupportsV2 &&
        hasConsent &&
        hasValidContext;
  }
}
