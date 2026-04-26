import 'dart:convert';

import 'package:characters/characters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/domain/services/partner_summary_builder.dart';

Partner _partner({
  String id = 'p-1',
  String name = '糖糖',
  String? customNote,
  String ownerUserId = 'u-1',
}) =>
    Partner(
      id: id,
      name: name,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 4, 1),
      ownerUserId: ownerUserId,
      customNote: customNote,
    );

Conversation _convo({
  required String id,
  required DateTime updatedAt,
  int? lastEnthusiasmScore,
  int currentRound = 0,
  int messageCount = 0,
  String? snapshotJson,
  String ownerUserId = 'u-1',
}) {
  final messages = List<Message>.generate(
    messageCount,
    (i) => Message(
      id: '$id-m$i',
      content: 'm$i',
      isFromMe: i.isEven,
      timestamp: updatedAt,
    ),
  );
  return Conversation(
    id: id,
    name: 'c-$id',
    messages: messages,
    createdAt: updatedAt,
    updatedAt: updatedAt,
    lastEnthusiasmScore: lastEnthusiasmScore,
    currentRound: currentRound,
    lastAnalysisSnapshotJson: snapshotJson,
    ownerUserId: ownerUserId,
  );
}

String _snapshot({
  List<String> interests = const [],
  List<String> traits = const [],
  List<String> notes = const [],
  int? heat,
}) =>
    jsonEncode({
      'targetProfile': {
        'interests': interests,
        'traits': traits,
        'notes': notes,
      },
      if (heat != null) 'heat': heat,
    });

void main() {
  late PartnerSummaryBuilder builder;

  setUp(() {
    builder = PartnerSummaryBuilder();
  });

  test('empty conversations returns header-only marker', () {
    final s = builder.build(partner: _partner(), conversations: const []);
    expect(s, contains('[對象背景：糖糖]'));
    expect(
      s.characters.length,
      lessThanOrEqualTo(PartnerSummaryBuilder.kHardCharCap),
    );
  });

  test('first-conversation partner: summary returns single-line marker', () {
    final s = builder.build(
      partner: _partner(),
      conversations: [
        _convo(id: 'c1', updatedAt: DateTime(2026, 4, 1)),
      ],
    );
    expect(s, contains('[對象背景：糖糖]'));
    expect(s, contains('這是你跟此對象的第一次對話'));
  });

  test(
      'all conversations no analysis snapshot: summary returns analysis-pending marker',
      () {
    final s = builder.build(
      partner: _partner(),
      conversations: [
        _convo(id: 'c1', updatedAt: DateTime(2026, 1, 1)),
        _convo(id: 'c2', updatedAt: DateTime(2026, 2, 1)),
        _convo(id: 'c3', updatedAt: DateTime(2026, 3, 1)),
      ],
    );
    expect(s, contains('[對象背景：糖糖]'));
    expect(s, contains('過往對話尚未分析'));
  });

  test('takes top N=8 interests / traits ranked by lastInteraction desc', () {
    final s = builder.build(
      partner: _partner(),
      conversations: [
        _convo(
          id: 'old',
          updatedAt: DateTime(2026, 1, 1),
          lastEnthusiasmScore: 50,
          snapshotJson: _snapshot(interests: const ['ZZ-old']),
        ),
        _convo(
          id: 'new',
          updatedAt: DateTime(2026, 4, 20),
          lastEnthusiasmScore: 80,
          snapshotJson: _snapshot(interests: const [
            'A',
            'B',
            'C',
            'D',
            'E',
            'F',
            'G',
            'H',
            'I',
          ]),
        ),
      ],
    );
    // Newer conversation's first 8 interests should appear; the old "ZZ-old"
    // is ranked last (cap=8) and should be cut.
    expect(s, contains('A、B、C、D、E、F、G、H'));
    expect(s, isNot(contains('ZZ-old')));
    expect(s, isNot(contains('I')));
  });

  test('takes most-recent 5 notes joined with separator', () {
    final s = builder.build(
      partner: _partner(),
      conversations: [
        _convo(
          id: 'c1',
          updatedAt: DateTime(2026, 4, 1),
          lastEnthusiasmScore: 80,
          snapshotJson: _snapshot(notes: const [
            'n1',
            'n2',
            'n3',
            'n4',
            'n5',
            'n6',
            'n7',
          ]),
        ),
      ],
    );
    expect(s, contains('過往備註'));
    // Builder keeps the 5 most recent notes; n1 / n2 (oldest) drop off.
    expect(s, isNot(contains('n1')));
    expect(s, isNot(contains('n2')));
    expect(s, contains('n3'));
    expect(s, contains('n7'));
  });

  test('partner.ownerUserId != conversation.ownerUserId returns empty summary',
      () {
    final s = builder.build(
      partner: _partner(ownerUserId: 'u-A'),
      conversations: [
        _convo(
          id: 'c1',
          updatedAt: DateTime(2026, 4, 1),
          ownerUserId: 'u-B', // mismatch
          snapshotJson: _snapshot(interests: const ['hike']),
        ),
      ],
    );
    expect(s, isEmpty,
        reason: 'owner mismatch is an anti-bleed safeguard — return nothing');
  });

  test(
      'single conversation lastAnalysisSnapshotJson parse failure: builder still assembles',
      () {
    final s = builder.build(
      partner: _partner(),
      conversations: [
        _convo(
          id: 'bad',
          updatedAt: DateTime(2026, 4, 1),
          lastEnthusiasmScore: 70,
          snapshotJson: 'not-valid-json{',
        ),
        _convo(
          id: 'good',
          updatedAt: DateTime(2026, 4, 2),
          lastEnthusiasmScore: 80,
          snapshotJson: _snapshot(interests: const ['hiking']),
        ),
      ],
    );
    expect(s, contains('興趣：hiking'),
        reason: 'good snapshot survives even when sibling fails to parse');
  });

  test('unnamed partner: uses fallback "對象 #" + id last 4 chars', () {
    final s = builder.build(
      partner: _partner(id: 'partner-id-abcd', name: ''),
      conversations: [
        _convo(
          id: 'c1',
          updatedAt: DateTime(2026, 4, 1),
          lastEnthusiasmScore: 70,
          snapshotJson: _snapshot(interests: const ['x']),
        ),
      ],
    );
    expect(s, contains('對象 #abcd'));
  });

  test(
      'user-set customNote 1000 chars: final summary still <= 1500 (truncation works)',
      () {
    final s = builder.build(
      partner: _partner(customNote: 'X' * 1000),
      conversations: [
        _convo(
          id: 'c1',
          updatedAt: DateTime(2026, 4, 1),
          lastEnthusiasmScore: 70,
          snapshotJson: _snapshot(
            interests: List.generate(8, (i) => 'interest$i'),
            traits: List.generate(8, (i) => 'trait$i'),
            notes: List.generate(5, (i) => 'note$i'),
          ),
        ),
      ],
    );
    expect(
      s.characters.length,
      lessThanOrEqualTo(PartnerSummaryBuilder.kHardCharCap),
    );
  });

  test('truncation preserves "[truncated]" suffix marker', () {
    // Construct a customNote large enough to force truncation.
    final s = builder.build(
      partner: _partner(customNote: 'Z' * 4000),
      conversations: [
        _convo(
          id: 'c1',
          updatedAt: DateTime(2026, 4, 1),
          lastEnthusiasmScore: 70,
          snapshotJson: _snapshot(interests: const ['a']),
        ),
      ],
    );
    expect(s, endsWith('[truncated]'));
    expect(s.characters.length,
        lessThanOrEqualTo(PartnerSummaryBuilder.kHardCharCap));
  });

  test('truncation does NOT split a ZWJ emoji grapheme cluster (Codex r2 P2)',
      () {
    // ZWJ family: 1 grapheme cluster, 7 codepoints, 11 UTF-16 code units.
    const family = '\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}';
    // Tile enough families that the buffer crosses kHardCharCap mid-cluster.
    // 2000 clusters × 1 grapheme each = 2000 graphemes, well past 1500.
    final note = family * 2000;
    final s = builder.build(
      partner: _partner(customNote: note),
      conversations: [
        _convo(
          id: 'c1',
          updatedAt: DateTime(2026, 4, 1),
          lastEnthusiasmScore: 70,
          snapshotJson: _snapshot(interests: const ['a']),
        ),
      ],
    );

    // Cap respected.
    expect(
      s.characters.length,
      lessThanOrEqualTo(PartnerSummaryBuilder.kHardCharCap),
    );
    expect(
      s.length,
      lessThanOrEqualTo(PartnerSummaryBuilder.kServerCodeUnitCap),
    );

    // No orphan surrogate / lone ZWJ — round-trip codeUnits must stay
    // valid UTF-16 (no unpaired high/low surrogate).
    final units = s.codeUnits;
    for (var i = 0; i < units.length; i++) {
      final u = units[i];
      final isHigh = u >= 0xD800 && u <= 0xDBFF;
      final isLow = u >= 0xDC00 && u <= 0xDFFF;
      if (isHigh) {
        expect(i + 1 < units.length, isTrue,
            reason: 'orphan high surrogate at position $i');
        final next = units[i + 1];
        expect(next >= 0xDC00 && next <= 0xDFFF, isTrue,
            reason: 'high surrogate at $i not followed by low surrogate');
        i++; // skip the paired low surrogate
      } else {
        expect(isLow, isFalse, reason: 'orphan low surrogate at position $i');
      }
    }

    // Ends with the truncation marker, not mid-emoji.
    expect(s, endsWith('[truncated]'));
  });

  test('truncation does NOT split a CJK char (basic non-ASCII boundary)', () {
    final note = '中' * 4000;
    final s = builder.build(
      partner: _partner(customNote: note),
      conversations: [
        _convo(
          id: 'c1',
          updatedAt: DateTime(2026, 4, 1),
          lastEnthusiasmScore: 70,
          snapshotJson: _snapshot(interests: const ['a']),
        ),
      ],
    );
    expect(
      s.characters.length,
      lessThanOrEqualTo(PartnerSummaryBuilder.kHardCharCap),
    );
    expect(
      s.length,
      lessThanOrEqualTo(PartnerSummaryBuilder.kServerCodeUnitCap),
    );
    expect(s, endsWith('[truncated]'));
  });

  test('summary mentions latest heat from most-recent conversation', () {
    final s = builder.build(
      partner: _partner(),
      conversations: [
        _convo(
          id: 'old',
          updatedAt: DateTime(2026, 1, 1),
          lastEnthusiasmScore: 30,
          snapshotJson: _snapshot(interests: const ['x']),
        ),
        _convo(
          id: 'new',
          updatedAt: DateTime(2026, 4, 20),
          lastEnthusiasmScore: 88,
          snapshotJson: _snapshot(interests: const ['y']),
        ),
      ],
    );
    expect(s, contains('最近熱度：88'));
  });

  test('customNote takes precedence over past notes when present', () {
    final s = builder.build(
      partner: _partner(customNote: '我記得她喜歡跑步'),
      conversations: [
        _convo(
          id: 'c1',
          updatedAt: DateTime(2026, 4, 1),
          lastEnthusiasmScore: 70,
          snapshotJson: _snapshot(notes: const ['n1', 'n2']),
        ),
      ],
    );
    expect(s, contains('你的備註：我記得她喜歡跑步'));
    expect(s, isNot(contains('過往備註')));
  });
}
