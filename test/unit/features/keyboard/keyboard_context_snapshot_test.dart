import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/keyboard/domain/entities/keyboard_context_snapshot.dart';

void main() {
  final generatedAt = DateTime.utc(2026, 7, 27, 4);

  test('serializes every required field including explicit nullable values',
      () {
    final snapshot = KeyboardContextSnapshot(
      schemaVersion: 1,
      ownerUserId: 'owner-1',
      revision: 'revision',
      generatedAt: generatedAt,
      expiresAt: generatedAt.add(const Duration(hours: 24)),
      consent: KeyboardContextConsent(
        version: KeyboardContextConsent.currentVersion,
        acceptedAt: generatedAt.subtract(const Duration(minutes: 1)),
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

    expect(snapshot.toJson(), {
      'schemaVersion': 1,
      'ownerUserId': 'owner-1',
      'revision': 'revision',
      'generatedAt': '2026-07-27T04:00:00.000Z',
      'expiresAt': '2026-07-28T04:00:00.000Z',
      'consent': {
        'version': 'keyboard_screenshot_ai_202607_v2',
        'acceptedAt': '2026-07-27T03:59:00.000Z',
        'latestScreenshotDetectionEnabled': true,
        'partnerContextSharingEnabled': false,
      },
      'globalVoice': {
        'primary': 'steady',
        'secondary': null,
        'sourceUpdatedAt': '2026-07-27T04:00:00.000Z',
      },
      'partners': <Object?>[],
    });
    expect(jsonDecode(snapshot.canonicalJson), snapshot.toJson());
  });

  test('canonical JSON is independent from map insertion order', () {
    final first = canonicalJsonEncode({
      'z': 1,
      'a': {
        'b': 2,
        'a': 1,
      },
    });
    final second = canonicalJsonEncode({
      'a': {
        'a': 1,
        'b': 2,
      },
      'z': 1,
    });

    expect(first, second);
    expect(first, '{"a":{"a":1,"b":2},"z":1}');
  });

  test('all wire timestamps use UTC millisecond precision', () {
    final precise = DateTime.utc(2026, 7, 27, 4, 5, 6, 123, 456);
    final snapshot = KeyboardContextSnapshot(
      schemaVersion: 1,
      ownerUserId: 'owner-1',
      revision: 'revision',
      generatedAt: precise,
      expiresAt: precise.add(const Duration(hours: 24)),
      consent: KeyboardContextConsent(
        version: KeyboardContextConsent.currentVersion,
        acceptedAt: precise,
        latestScreenshotDetectionEnabled: true,
        partnerContextSharingEnabled: true,
      ),
      globalVoice: KeyboardContextVoice(
        primary: KeyboardVoice.steady,
        secondary: null,
        sourceUpdatedAt: precise,
      ),
      partners: [
        KeyboardContextPartner(
          partnerId: 'partner-1',
          displayName: 'Partner',
          confirmedAliases: const [],
          contextStatus: KeyboardPartnerContextStatus.available,
          facts: [
            KeyboardContextFact(
              kind: KeyboardContextFactKind.userNote,
              text: 'note',
              updatedAt: precise,
            ),
          ],
          outcomeStats: null,
          effectiveVoice: KeyboardContextVoice(
            primary: KeyboardVoice.playful,
            secondary: null,
            sourceUpdatedAt: precise,
          ),
          contextRevision: 'context-revision',
          sourceUpdatedAt: precise,
        ),
      ],
    );

    final json = snapshot.toJson();
    final partner = (json['partners']! as List).single as Map<String, Object?>;
    final fact = (partner['facts']! as List).single as Map<String, Object?>;
    expect(json['generatedAt'], '2026-07-27T04:05:06.123Z');
    expect(json['expiresAt'], '2026-07-28T04:05:06.123Z');
    expect(
      (json['consent']! as Map<String, Object?>)['acceptedAt'],
      '2026-07-27T04:05:06.123Z',
    );
    expect(
      (json['globalVoice']! as Map<String, Object?>)['sourceUpdatedAt'],
      '2026-07-27T04:05:06.123Z',
    );
    expect(fact['updatedAt'], '2026-07-27T04:05:06.123Z');
    expect(partner['sourceUpdatedAt'], '2026-07-27T04:05:06.123Z');
  });
}
