import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/keyboard/domain/entities/keyboard_assist_feature_flags.dart';

void main() {
  final receivedAt = DateTime.utc(2026, 7, 27, 4);
  final now = receivedAt.add(const Duration(minutes: 1));

  test('missing authenticated receipt defaults every capability off', () {
    const capabilities = KeyboardAssistFeatureFlags();

    expect(
      capabilities.canSendScreenshot(
        ownerUserId: 'owner-1',
        now: now,
      ),
      isFalse,
    );
    expect(
      capabilities.canUseLinkedPartner(
        ownerUserId: 'owner-1',
        now: now,
        hasConsent: true,
        hasValidContext: true,
      ),
      isFalse,
    );
  });

  test('v1 trusts an unexpired authenticated receipt for the same owner', () {
    final capabilities = KeyboardAssistFeatureFlags(
      screenshotReceipt: _receipt(
        ownerUserId: 'owner-1',
        receivedAt: receivedAt,
      ),
    );

    expect(
      capabilities.canSendScreenshot(
        ownerUserId: 'owner-1',
        now: now,
      ),
      isTrue,
    );
    expect(
      capabilities.canSendScreenshot(
        ownerUserId: 'owner-2',
        now: now,
      ),
      isFalse,
    );
  });

  test('disabled, expired, future, or incompatible receipts fail closed', () {
    bool canSend(KeyboardAssistCapabilityReceipt receipt, DateTime at) {
      return KeyboardAssistFeatureFlags(
        screenshotReceipt: receipt,
      ).canSendScreenshot(ownerUserId: 'owner-1', now: at);
    }

    expect(
      canSend(
        _receipt(
          ownerUserId: 'owner-1',
          receivedAt: receivedAt,
          enabled: false,
        ),
        now,
      ),
      isFalse,
    );
    expect(
      canSend(
        KeyboardAssistCapabilityReceipt(
          contractVersion:
              KeyboardAssistCapabilityReceipt.screenshotV1ContractVersion,
          ownerUserId: 'owner-1',
          enabled: true,
          pipelineVersion: 'compiler-judge-v1',
          receivedAt: receivedAt,
          expiresAt: receivedAt.add(const Duration(minutes: 6)),
        ),
        now,
      ),
      isFalse,
    );
    expect(
      canSend(
        _receipt(ownerUserId: 'owner-1', receivedAt: receivedAt),
        receivedAt.add(const Duration(minutes: 5)),
      ),
      isFalse,
    );
    expect(
      canSend(
        _receipt(
          ownerUserId: 'owner-1',
          receivedAt: now.add(const Duration(seconds: 1)),
        ),
        now,
      ),
      isFalse,
    );
    expect(
      canSend(
        _receipt(
          ownerUserId: 'owner-1',
          receivedAt: receivedAt,
          contractVersion: 'unknown',
        ),
        now,
      ),
      isFalse,
    );
  });

  test('v2 layers its own capability receipt, consent, and valid context', () {
    final capabilities = KeyboardAssistFeatureFlags(
      screenshotReceipt: _receipt(
        ownerUserId: 'owner-1',
        receivedAt: receivedAt,
      ),
      linkedPartnerV2Receipt: _receipt(
        ownerUserId: 'owner-1',
        receivedAt: receivedAt,
        contractVersion:
            KeyboardAssistCapabilityReceipt.linkedPartnerV2ContractVersion,
      ),
    );

    expect(
      capabilities.canUseLinkedPartner(
        ownerUserId: 'owner-1',
        now: now,
        hasConsent: true,
        hasValidContext: true,
      ),
      isTrue,
    );
    expect(
      capabilities.canUseLinkedPartner(
        ownerUserId: 'owner-1',
        now: now,
        hasConsent: false,
        hasValidContext: true,
      ),
      isFalse,
    );
    expect(
      capabilities.canUseLinkedPartner(
        ownerUserId: 'owner-1',
        now: now,
        hasConsent: true,
        hasValidContext: false,
      ),
      isFalse,
    );
  });
}

KeyboardAssistCapabilityReceipt _receipt({
  required String ownerUserId,
  required DateTime receivedAt,
  String contractVersion =
      KeyboardAssistCapabilityReceipt.screenshotV1ContractVersion,
  bool enabled = true,
}) {
  return KeyboardAssistCapabilityReceipt(
    contractVersion: contractVersion,
    ownerUserId: ownerUserId,
    enabled: enabled,
    pipelineVersion: 'compiler-judge-v1',
    receivedAt: receivedAt,
    expiresAt: receivedAt.add(const Duration(minutes: 5)),
  );
}
