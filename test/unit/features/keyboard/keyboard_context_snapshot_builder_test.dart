import 'dart:convert';

import 'package:characters/characters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/keyboard/domain/entities/keyboard_context_snapshot.dart';
import 'package:vibesync/features/keyboard/domain/services/keyboard_context_snapshot_builder.dart';

void main() {
  final now = DateTime.utc(2026, 7, 27, 4);
  late KeyboardContextSnapshotBuilder builder;

  setUp(() {
    builder = KeyboardContextSnapshotBuilder(now: () => now);
  });

  test('builds owner-scoped allowlisted snapshot with a 24 hour TTL', () {
    final snapshot = builder.build(
      ownerUserId: 'owner-1',
      consent: _consent(partnerSharing: true),
      globalVoice: KeyboardContextVoice(
        primary: KeyboardVoice.steady,
        secondary: null,
        sourceUpdatedAt: now,
      ),
      partners: [
        _partner(
          id: 'allowed',
          owner: 'owner-1',
          allowlisted: true,
          note: '使用者自己寫的備註',
        ),
        _partner(
          id: 'wrong-owner',
          owner: 'owner-2',
          allowlisted: true,
        ),
        _partner(
          id: 'not-allowed',
          owner: 'owner-1',
          allowlisted: false,
        ),
      ],
    );

    expect(snapshot.ownerUserId, 'owner-1');
    expect(snapshot.generatedAt, now);
    expect(snapshot.expiresAt, now.add(const Duration(hours: 24)));
    expect(snapshot.partners.map((partner) => partner.partnerId), ['allowed']);
    expect(snapshot.revision, matches(RegExp(r'^[a-f0-9]{64}$')));

    final encoded = jsonEncode(snapshot.toJson());
    for (final forbidden in [
      'rawMessages',
      'conversationTranscript',
      'latestHeat',
      'unionTraits',
      'unionInterests',
      'aiNotes',
    ]) {
      expect(encoded, isNot(contains(forbidden)));
    }
  });

  test('partner context sharing is independently default-off and fail closed',
      () {
    final snapshot = builder.build(
      ownerUserId: 'owner-1',
      consent: _consent(partnerSharing: false),
      globalVoice: KeyboardContextVoice(
        primary: KeyboardVoice.steady,
        secondary: null,
        sourceUpdatedAt: now,
      ),
      partners: [_partner(id: 'partner-1', owner: 'owner-1')],
    );

    expect(snapshot.partners, isEmpty);
  });

  test('data-quality conflict keeps picker identity but strips prompt context',
      () {
    final snapshot = builder.build(
      ownerUserId: 'owner-1',
      consent: _consent(partnerSharing: true),
      globalVoice: KeyboardContextVoice(
        primary: KeyboardVoice.steady,
        secondary: null,
        sourceUpdatedAt: now,
      ),
      partners: [
        _partner(
          id: 'flagged',
          owner: 'owner-1',
          note: 'must not leave device',
          dataQualityFlagged: true,
          outcomeStats: const KeyboardOutcomeStats(
            sampleSize: 6,
            engaged: 3,
            cold: 1,
            noReply: 1,
            negative: 0,
          ),
        ),
      ],
    );

    final partner = snapshot.partners.single;
    expect(
      partner.contextStatus,
      KeyboardPartnerContextStatus.dataQualityFlagged,
    );
    expect(
      partner.toJson()['contextStatus'],
      'data_quality_flagged',
      reason: 'must match Swift KeyboardPartnerContextStatus raw value',
    );
    expect(partner.facts, isEmpty);
    expect(partner.outcomeStats, isNull);
    expect(partner.effectiveVoice, isNull);
    expect(jsonEncode(partner.toJson()), isNot(contains('must not leave')));
  });

  test('outcome statistics stay local until the minimum signal threshold', () {
    final snapshot = builder.build(
      ownerUserId: 'owner-1',
      consent: _consent(partnerSharing: true),
      globalVoice: KeyboardContextVoice(
        primary: KeyboardVoice.steady,
        secondary: null,
        sourceUpdatedAt: now,
      ),
      partners: [
        _partner(
          id: 'low-signal',
          owner: 'owner-1',
          outcomeStats: const KeyboardOutcomeStats(
            sampleSize: 2,
            engaged: 2,
            cold: 0,
            noReply: 0,
            negative: 0,
          ),
        ),
      ],
    );

    expect(snapshot.partners.single.outcomeStats, isNull);
  });

  test('caps aliases and user-authored note on grapheme boundaries', () {
    final longNote = List.filled(301, '👨‍👩‍👧‍👦').join();
    final snapshot = builder.build(
      ownerUserId: 'owner-1',
      consent: _consent(partnerSharing: true),
      globalVoice: KeyboardContextVoice(
        primary: KeyboardVoice.steady,
        secondary: null,
        sourceUpdatedAt: now,
      ),
      partners: [
        _partner(
          id: 'partner-1',
          owner: 'owner-1',
          aliases: const ['A', 'B', 'C', 'D', 'E', 'F'],
          note: longNote,
        ),
      ],
    );

    final partner = snapshot.partners.single;
    expect(partner.confirmedAliases, ['A', 'B', 'C', 'D', 'E']);
    expect(partner.facts.single.text.characters.length, 300);
    expect(partner.facts.single.text.endsWith('👨‍👩‍👧‍👦'), isTrue);
  });

  test('revision changes when prompt-relevant partner data changes', () {
    KeyboardContextSnapshot build(String note) => builder.build(
          ownerUserId: 'owner-1',
          consent: _consent(partnerSharing: true),
          globalVoice: KeyboardContextVoice(
            primary: KeyboardVoice.steady,
            secondary: null,
            sourceUpdatedAt: now,
          ),
          partners: [
            _partner(id: 'partner-1', owner: 'owner-1', note: note),
          ],
        );

    expect(build('first').revision, isNot(build('second').revision));
  });

  test('rejects stale consent versions instead of silently defaulting', () {
    expect(
      () => builder.build(
        ownerUserId: 'owner-1',
        consent: KeyboardContextConsent(
          version: 'unknown',
          acceptedAt: now,
          latestScreenshotDetectionEnabled: true,
          partnerContextSharingEnabled: false,
        ),
        globalVoice: KeyboardContextVoice(
          primary: KeyboardVoice.steady,
          secondary: null,
          sourceUpdatedAt: now,
        ),
        partners: const [],
      ),
      throwsArgumentError,
    );
  });

  test('does not build a publishable snapshot when photo detection is off', () {
    expect(
      () => builder.build(
        ownerUserId: 'owner-1',
        consent: KeyboardContextConsent(
          version: KeyboardContextConsent.currentVersion,
          acceptedAt: now,
          latestScreenshotDetectionEnabled: false,
          partnerContextSharingEnabled: false,
        ),
        globalVoice: KeyboardContextVoice(
          primary: KeyboardVoice.steady,
          secondary: null,
          sourceUpdatedAt: now,
        ),
        partners: const [],
      ),
      throwsArgumentError,
    );
  });

  test('rejects duplicate partner ids instead of producing ambiguous context',
      () {
    expect(
      () => builder.build(
        ownerUserId: 'owner-1',
        consent: _consent(partnerSharing: true),
        globalVoice: KeyboardContextVoice(
          primary: KeyboardVoice.steady,
          secondary: null,
          sourceUpdatedAt: now,
        ),
        partners: [
          _partner(id: 'duplicate', owner: 'owner-1'),
          _partner(id: 'duplicate', owner: 'owner-1'),
        ],
      ),
      throwsArgumentError,
    );
  });

  test('top-level revision ignores sub-millisecond clock differences', () {
    KeyboardContextSnapshot build(DateTime clock) {
      return KeyboardContextSnapshotBuilder(now: () => clock).build(
        ownerUserId: 'owner-1',
        consent: _consent(partnerSharing: false),
        globalVoice: KeyboardContextVoice(
          primary: KeyboardVoice.steady,
          secondary: null,
          sourceUpdatedAt: now,
        ),
        partners: const [],
      );
    }

    final first = build(DateTime.utc(2026, 7, 27, 4, 0, 0, 123, 111));
    final sameMillisecond = build(DateTime.utc(2026, 7, 27, 4, 0, 0, 123, 999));
    final nextMillisecond = build(DateTime.utc(2026, 7, 27, 4, 0, 0, 124));

    expect(first.revision, sameMillisecond.revision);
    expect(first.generatedAt.microsecond, 0);
    expect(first.revision, isNot(nextMillisecond.revision));
  });

  test('partner revision ignores only sub-millisecond source differences', () {
    KeyboardContextSnapshot build(DateTime sourceUpdatedAt) {
      return builder.build(
        ownerUserId: 'owner-1',
        consent: _consent(partnerSharing: true),
        globalVoice: KeyboardContextVoice(
          primary: KeyboardVoice.steady,
          secondary: null,
          sourceUpdatedAt: now,
        ),
        partners: [
          _partner(
            id: 'partner-1',
            owner: 'owner-1',
            note: 'note',
            sourceUpdatedAt: sourceUpdatedAt,
          ),
        ],
      );
    }

    final first = build(DateTime.utc(2026, 7, 27, 3, 0, 0, 123, 111));
    final sameMillisecond = build(DateTime.utc(2026, 7, 27, 3, 0, 0, 123, 999));
    final nextMillisecond = build(DateTime.utc(2026, 7, 27, 3, 0, 0, 124));

    expect(
      first.partners.single.contextRevision,
      sameMillisecond.partners.single.contextRevision,
    );
    expect(
      first.partners.single.contextRevision,
      isNot(nextMillisecond.partners.single.contextRevision),
    );
  });

  test('rejects invalid global voice pairs before publishing', () {
    for (final voice in [
      KeyboardContextVoice(
        primary: null,
        secondary: KeyboardVoice.playful,
        sourceUpdatedAt: now,
      ),
      KeyboardContextVoice(
        primary: KeyboardVoice.steady,
        secondary: KeyboardVoice.steady,
        sourceUpdatedAt: now,
      ),
    ]) {
      expect(
        () => builder.build(
          ownerUserId: 'owner-1',
          consent: _consent(partnerSharing: false),
          globalVoice: voice,
          partners: const [],
        ),
        throwsArgumentError,
      );
    }
  });

  test('rejects invalid effective voice pairs for available partner context',
      () {
    for (final voice in [
      KeyboardContextVoice(
        primary: null,
        secondary: KeyboardVoice.playful,
        sourceUpdatedAt: now,
      ),
      KeyboardContextVoice(
        primary: KeyboardVoice.playful,
        secondary: KeyboardVoice.playful,
        sourceUpdatedAt: now,
      ),
    ]) {
      expect(
        () => builder.build(
          ownerUserId: 'owner-1',
          consent: _consent(partnerSharing: true),
          globalVoice: KeyboardContextVoice(
            primary: KeyboardVoice.steady,
            secondary: null,
            sourceUpdatedAt: now,
          ),
          partners: [
            _partner(
              id: 'partner-1',
              owner: 'owner-1',
              effectiveVoice: voice,
            ),
          ],
        ),
        throwsArgumentError,
      );
    }
  });

  test('allows an explicitly unset global and effective voice pair', () {
    final snapshot = builder.build(
      ownerUserId: 'owner-1',
      consent: _consent(partnerSharing: true),
      globalVoice: KeyboardContextVoice(
        primary: null,
        secondary: null,
        sourceUpdatedAt: now,
      ),
      partners: [
        _partner(
          id: 'partner-1',
          owner: 'owner-1',
          effectiveVoice: KeyboardContextVoice(
            primary: null,
            secondary: null,
            sourceUpdatedAt: now,
          ),
        ),
      ],
    );

    expect(snapshot.globalVoice.primary, isNull);
    expect(snapshot.globalVoice.secondary, isNull);
    expect(snapshot.partners.single.effectiveVoice!.primary, isNull);
    expect(snapshot.partners.single.effectiveVoice!.secondary, isNull);
  });
}

KeyboardContextConsent _consent({required bool partnerSharing}) {
  final now = DateTime.utc(2026, 7, 27, 4);
  return KeyboardContextConsent(
    version: KeyboardContextConsent.currentVersion,
    acceptedAt: now.subtract(const Duration(minutes: 1)),
    latestScreenshotDetectionEnabled: true,
    partnerContextSharingEnabled: partnerSharing,
  );
}

KeyboardContextPartnerSource _partner({
  required String id,
  required String owner,
  bool allowlisted = true,
  bool pinned = false,
  bool dataQualityFlagged = false,
  String? note,
  List<String> aliases = const ['LINE name'],
  KeyboardOutcomeStats? outcomeStats,
  DateTime? sourceUpdatedAt,
  KeyboardContextVoice? effectiveVoice,
}) {
  final now = DateTime.utc(2026, 7, 27, 4);
  final updatedAt = sourceUpdatedAt ?? now;
  return KeyboardContextPartnerSource(
    partnerId: id,
    ownerUserId: owner,
    displayName: 'Partner $id',
    confirmedAliases: aliases,
    userAuthoredNote: note,
    outcomeStats: outcomeStats,
    effectiveVoice: effectiveVoice ??
        KeyboardContextVoice(
          primary: KeyboardVoice.playful,
          secondary: KeyboardVoice.steady,
          sourceUpdatedAt: updatedAt,
        ),
    sourceUpdatedAt: updatedAt,
    isAllowlisted: allowlisted,
    isPinned: pinned,
    hasDataQualityConflict: dataQualityFlagged,
  );
}
