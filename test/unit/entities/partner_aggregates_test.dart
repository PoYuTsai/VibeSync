import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/domain/extensions/partner_aggregates.dart';

Partner _partner({String name = '糖糖', String? customNote}) => Partner(
      id: 'p-1',
      name: name,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      ownerUserId: 'u-1',
      customNote: customNote,
    );

Conversation _convo({
  required String id,
  required DateTime updatedAt,
  int? lastEnthusiasmScore,
  int currentRound = 0,
  int messageCount = 0,
  String? snapshotJson,
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
  );
}

String _snapshot({
  List<String> interests = const [],
  List<String> traits = const [],
  List<String> notes = const [],
}) =>
    jsonEncode({
      'targetProfile': {
        'interests': interests,
        'traits': traits,
        'notes': notes,
      },
    });

void main() {
  group('PartnerAggregates.aggregateOver', () {
    test('empty conversation list returns safe defaults', () {
      final view = _partner().aggregateOver(const []);
      expect(view.unionInterests, isEmpty);
      expect(view.unionTraits, isEmpty);
      expect(view.unionNotes, isNull);
      expect(view.latestHeat, isNull);
      expect(view.totalRounds, 0);
      expect(view.totalMessages, 0);
      expect(view.lastInteraction, isNull);
    });

    test('latestHeat = lastEnthusiasmScore of the most-recent conversation',
        () {
      final view = _partner().aggregateOver([
        _convo(
            id: 'c1', updatedAt: DateTime(2026, 1, 1), lastEnthusiasmScore: 99),
        _convo(
            id: 'c2', updatedAt: DateTime(2026, 4, 1), lastEnthusiasmScore: 72),
        _convo(
            id: 'c3', updatedAt: DateTime(2026, 3, 1), lastEnthusiasmScore: 50),
      ]);
      expect(view.latestHeat, 72);
    });

    test(
        'latestHeat is null when most-recent conversation has null score (D5-C)',
        () {
      final view = _partner().aggregateOver([
        _convo(
            id: 'c1', updatedAt: DateTime(2026, 1, 1), lastEnthusiasmScore: 80),
        _convo(
            id: 'c2',
            updatedAt: DateTime(2026, 5, 1),
            lastEnthusiasmScore: null),
      ]);
      expect(view.latestHeat, isNull);
    });

    test('lastInteraction = max(updatedAt) across conversations', () {
      final view = _partner().aggregateOver([
        _convo(id: 'c1', updatedAt: DateTime(2026, 1, 1)),
        _convo(id: 'c2', updatedAt: DateTime(2026, 4, 1)),
        _convo(id: 'c3', updatedAt: DateTime(2026, 3, 1)),
      ]);
      expect(view.lastInteraction, DateTime(2026, 4, 1));
    });

    test('totalRounds sums currentRound across all conversations', () {
      final view = _partner().aggregateOver([
        _convo(id: 'c1', updatedAt: DateTime(2026, 1, 1), currentRound: 1),
        _convo(id: 'c2', updatedAt: DateTime(2026, 2, 1), currentRound: 2),
        _convo(id: 'c3', updatedAt: DateTime(2026, 3, 1), currentRound: 5),
      ]);
      expect(view.totalRounds, 8);
    });

    test('totalMessages sums messages.length across all conversations', () {
      final view = _partner().aggregateOver([
        _convo(id: 'c1', updatedAt: DateTime(2026, 1, 1), messageCount: 3),
        _convo(id: 'c2', updatedAt: DateTime(2026, 2, 1), messageCount: 5),
        _convo(id: 'c3', updatedAt: DateTime(2026, 3, 1), messageCount: 7),
      ]);
      expect(view.totalMessages, 15);
    });

    test('unionInterests dedupes across conversations', () {
      final view = _partner().aggregateOver([
        _convo(
          id: 'c1',
          updatedAt: DateTime(2026, 1, 1),
          snapshotJson: _snapshot(interests: ['烘焙', '貓']),
        ),
        _convo(
          id: 'c2',
          updatedAt: DateTime(2026, 3, 1),
          snapshotJson: _snapshot(interests: ['貓', '咖啡']),
        ),
      ]);
      expect(view.unionInterests.toSet(), {'烘焙', '貓', '咖啡'});
      expect(view.unionInterests.length, 3);
    });

    test('unionInterests ranks by most-recent mention and caps at N=8', () {
      final view = _partner().aggregateOver([
        _convo(
          id: 'old',
          updatedAt: DateTime(2026, 1, 1),
          snapshotJson: _snapshot(interests: ['t1', 't2', 't3', 't4', 't5']),
        ),
        _convo(
          id: 'new',
          updatedAt: DateTime(2026, 5, 1),
          snapshotJson: _snapshot(interests: ['t6', 't7', 't8', 't9']),
        ),
      ]);
      expect(view.unionInterests.length, 8);
      // Newest snapshot's tags fill the head of the list, in their snapshot order.
      expect(view.unionInterests.take(4).toList(), ['t6', 't7', 't8', 't9']);
      // Cap drops the trailing tag of the oldest snapshot (t5), not the head.
      expect(view.unionInterests, isNot(contains('t5')));
      expect(view.unionInterests, containsAll(['t1', 't2', 't3', 't4']));
    });

    test('unionTraits dedupes and ranks by recency (oldest mention sinks last)',
        () {
      final view = _partner().aggregateOver([
        _convo(
          id: 'c1',
          updatedAt: DateTime(2026, 1, 1),
          snapshotJson: _snapshot(traits: ['溫柔', '幽默']),
        ),
        _convo(
          id: 'c2',
          updatedAt: DateTime(2026, 4, 1),
          snapshotJson: _snapshot(traits: ['幽默', '主動']),
        ),
      ]);
      expect(view.unionTraits.toSet(), {'溫柔', '幽默', '主動'});
      // 「溫柔」's most-recent mention is 2026-01-01; the others are 2026-04-01.
      expect(view.unionTraits.last, '溫柔');
    });

    test(
        'unionNotes preserves chronological order (oldest first) joined with newline',
        () {
      final view = _partner().aggregateOver([
        _convo(
          id: 'c2',
          updatedAt: DateTime(2026, 3, 1),
          snapshotJson: _snapshot(notes: ['約過咖啡']),
        ),
        _convo(
          id: 'c1',
          updatedAt: DateTime(2026, 1, 1),
          snapshotJson: _snapshot(notes: ['第一次見面緊張']),
        ),
      ]);
      expect(view.unionNotes, '第一次見面緊張\n約過咖啡');
    });

    test('unionNotes dedupes exact and near-duplicate notes', () {
      final view = _partner().aggregateOver([
        _convo(
          id: 'old',
          updatedAt: DateTime(2026, 1, 1),
          snapshotJson: _snapshot(notes: [
            'like-testing-reactions',
            'father steak interest but busy',
          ]),
        ),
        _convo(
          id: 'new',
          updatedAt: DateTime(2026, 5, 1),
          snapshotJson: _snapshot(notes: [
            'likes-testing-reactions',
            'father steak interest but busy',
            'active questioning',
          ]),
        ),
      ]);

      final lines = view.unionNotes!.split('\n');
      expect(lines, [
        'likes-testing-reactions',
        'father steak interest but busy',
        'active questioning',
      ]);
      expect(lines, isNot(contains('like-testing-reactions')));
    });

    test('unionNotes keeps the latest 8 unique notes', () {
      final view = _partner().aggregateOver([
        _convo(
          id: 'old',
          updatedAt: DateTime(2026, 1, 1),
          snapshotJson: _snapshot(notes: ['n1', 'n2', 'n3', 'n4']),
        ),
        _convo(
          id: 'new',
          updatedAt: DateTime(2026, 5, 1),
          snapshotJson: _snapshot(
            notes: ['n5', 'n6', 'n7', 'n8', 'n9', 'n10'],
          ),
        ),
      ]);

      expect(view.unionNotes!.split('\n'), [
        'n1',
        'n2',
        'n5',
        'n6',
        'n7',
        'n8',
        'n9',
        'n10',
      ]);
    });

    test('unionNotes does not merge opposite notes with negation', () {
      final view = _partner().aggregateOver([
        _convo(
          id: 'old',
          updatedAt: DateTime(2026, 1, 1),
          snapshotJson: _snapshot(notes: ['可以直接提問']),
        ),
        _convo(
          id: 'new',
          updatedAt: DateTime(2026, 5, 1),
          snapshotJson: _snapshot(notes: ['不可以直接提問']),
        ),
      ]);

      expect(view.unionNotes!.split('\n'), [
        '可以直接提問',
        '不可以直接提問',
      ]);
    });

    test(
        'snapshot parse failure on one conversation: skip it, others still aggregate',
        () {
      final view = _partner().aggregateOver([
        _convo(
          id: 'c1',
          updatedAt: DateTime(2026, 1, 1),
          snapshotJson: 'not-valid-json',
        ),
        _convo(
          id: 'c2',
          updatedAt: DateTime(2026, 2, 1),
          snapshotJson: _snapshot(interests: ['咖啡']),
        ),
      ]);
      expect(view.unionInterests, ['咖啡']);
    });
  });
}
