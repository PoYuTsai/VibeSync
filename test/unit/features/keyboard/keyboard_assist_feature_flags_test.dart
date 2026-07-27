import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/keyboard/domain/entities/keyboard_assist_feature_flags.dart';

void main() {
  test('all screenshot capabilities default off for missing server flags', () {
    const flags = KeyboardAssistFeatureFlags();

    expect(flags.canSendScreenshot(ownerUserId: 'owner-1'), isFalse);
    expect(
      flags.canUseLinkedPartner(
        ownerUserId: 'owner-1',
        clientSupportsV2: true,
        hasConsent: true,
        hasValidContext: true,
      ),
      isFalse,
    );
  });

  test('v1 requires both authoritative flag and owner allowlist', () {
    const flags = KeyboardAssistFeatureFlags(
      screenshotV1Enabled: true,
      screenshotV1Allowlist: {'owner-1'},
    );

    expect(flags.canSendScreenshot(ownerUserId: 'owner-1'), isTrue);
    expect(flags.canSendScreenshot(ownerUserId: 'owner-2'), isFalse);
  });

  test('v2 additionally requires capability, consent, and valid context', () {
    const flags = KeyboardAssistFeatureFlags(
      screenshotV1Enabled: true,
      screenshotV1Allowlist: {'owner-1'},
      linkedPartnerV2Enabled: true,
    );

    expect(
      flags.canUseLinkedPartner(
        ownerUserId: 'owner-1',
        clientSupportsV2: true,
        hasConsent: true,
        hasValidContext: true,
      ),
      isTrue,
    );
    expect(
      flags.canUseLinkedPartner(
        ownerUserId: 'owner-1',
        clientSupportsV2: true,
        hasConsent: false,
        hasValidContext: true,
      ),
      isFalse,
    );
  });
}
