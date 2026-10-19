import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/entities/guide_v3_result.dart';
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
        'provenanceVersion': 1,
        'interests': interests,
        'traits': traits,
        'notes': notes,
      },
    });

void main() {
  group('PartnerAggregates.aggregateOver', () {
    test('legacy snapshot 沒有 provenance，不再升格成跨輪記憶', () {
      final legacy = jsonEncode({
        'targetProfile': {
          'interests': ['寵物互動玩笑'],
          'traits': ['幽默自信'],
          'notes': ['她喜歡狗'],
        },
      });
      final view = _partner().aggregateOver([
        _convo(
          id: 'legacy',
          updatedAt: DateTime(2026, 8, 20),
          snapshotJson: legacy,
        ),
      ]);

      expect(view.unionInterests, isEmpty);
      expect(view.unionTraits, isEmpty);
      expect(view.unionNotes, isNull);
    });

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

    test('latestIsGuideV3 看最近分析過的那段是不是 v3（各頁同一條規則）', () {
      final v3Snapshot = jsonEncode({
        'guideVersion': 'v3.5',
        'read': {'light': 'green', 'decision': 'send'},
        'cards': const [],
      });
      final v3Latest = _partner().aggregateOver([
        _convo(
            id: 'c1',
            updatedAt: DateTime(2026, 1, 1),
            lastEnthusiasmScore: 80,
            snapshotJson: _snapshot(interests: const ['咖啡'])),
        _convo(
            id: 'c2',
            updatedAt: DateTime(2026, 5, 1),
            snapshotJson: v3Snapshot),
      ]);
      expect(v3Latest.latestIsGuideV3, isTrue);
      expect(v3Latest.latestHeat, isNull);

      // 最近那段還沒分析（沒有快照）：照上一次分析（v3）算，熱度照舊看最近那段。
      final unanalyzedLatest = _partner().aggregateOver([
        _convo(
            id: 'c1',
            updatedAt: DateTime(2026, 1, 1),
            snapshotJson: v3Snapshot),
        _convo(id: 'c2', updatedAt: DateTime(2026, 5, 1)),
      ]);
      expect(unanalyzedLatest.latestIsGuideV3, isTrue);
      expect(unanalyzedLatest.latestHeat, isNull);

      // 最近分析過的是 v2：不是 v3，更早的 v3 不算數。
      final v2AfterV3 = _partner().aggregateOver([
        _convo(
            id: 'c1',
            updatedAt: DateTime(2026, 1, 1),
            snapshotJson: v3Snapshot),
        _convo(
            id: 'c2',
            updatedAt: DateTime(2026, 5, 1),
            lastEnthusiasmScore: 64,
            snapshotJson: _snapshot(traits: const ['慢熱'])),
      ]);
      expect(v2AfterV3.latestIsGuideV3, isFalse);

      final v2Latest = _partner().aggregateOver([
        _convo(
            id: 'c1',
            updatedAt: DateTime(2026, 5, 1),
            lastEnthusiasmScore: 64,
            snapshotJson: _snapshot(traits: const ['慢熱'])),
      ]);
      expect(v2Latest.latestIsGuideV3, isFalse);
      expect(PartnerAggregateView.empty().latestIsGuideV3, isFalse);
    });

    test('latestGuideV3Signals：最近那段 v3 的燈號、決定、邀約進度、冷訊號；不分方案', () {
      String v3({
        required String decision,
        String? light,
        String? inviteReadiness,
        Map<String, Object?>? cold,
      }) =>
          jsonEncode({
            'guideVersion': 'v3.5',
            'read': {
              'guideVersion': 'v3.5',
              'decision': decision,
              if (light != null) 'light': light,
              'judgment': '',
              if (inviteReadiness != null) 'inviteReadiness': inviteReadiness,
              if (cold != null) 'cold': cold,
              'plannedCards': const [],
            },
            'cards': const [],
          });

      final view = _partner().aggregateOver([
        _convo(
          id: 'old',
          updatedAt: DateTime(2026, 10, 1),
          snapshotJson: v3(decision: 'send', light: 'green'),
        ),
        _convo(
          id: 'new',
          updatedAt: DateTime(2026, 10, 18),
          snapshotJson: v3(
            decision: 'hold',
            light: 'yellow',
            inviteReadiness: 'hesitant',
            cold: {'c1': true, 'herPerfunctoryStreak': 2},
          ),
        ),
      ]);
      final signals = view.latestGuideV3Signals!;
      expect(signals.decision, GuideV3Decision.hold);
      expect(signals.light, GuideV3Light.yellow);
      expect(signals.inviteReadiness, GuideV3InviteReadiness.hesitant);
      expect(signals.c1, isTrue);
      expect(signals.herPerfunctoryStreak, 2);

      // 舊快照（伺服器還沒送新欄位）：燈號、決定照給，其他是 null。
      final legacy = _partner().aggregateOver([
        _convo(
          id: 'legacy',
          updatedAt: DateTime(2026, 10, 17),
          snapshotJson: v3(decision: 'send', light: 'red'),
        ),
      ]).latestGuideV3Signals!;
      expect(legacy.decision, GuideV3Decision.send);
      expect(legacy.light, GuideV3Light.red);
      expect(legacy.inviteReadiness, isNull);
      expect(legacy.c1, isNull);
      expect(legacy.herPerfunctoryStreak, isNull);

      // 關心不帶燈號（伺服器的判讀可能有 light，畫面本來就不給 care 顯示）。
      final care = _partner().aggregateOver([
        _convo(
          id: 'care',
          updatedAt: DateTime(2026, 10, 18),
          snapshotJson: v3(decision: 'care', light: 'red'),
        ),
      ]).latestGuideV3Signals!;
      expect(care.decision, GuideV3Decision.care);
      expect(care.light, isNull);

      // 最近分析過的是舊流程：沒有 v3 訊號（不拿更早的 v3 冒充最新）。
      final v2Latest = _partner().aggregateOver([
        _convo(
          id: 'v3',
          updatedAt: DateTime(2026, 10, 1),
          snapshotJson: v3(decision: 'send', light: 'green'),
        ),
        _convo(
          id: 'v2',
          updatedAt: DateTime(2026, 10, 18),
          lastEnthusiasmScore: 60,
          snapshotJson: _snapshot(traits: const ['慢熱']),
        ),
      ]);
      expect(v2Latest.latestGuideV3Signals, isNull);
      // 最近那段還沒分析：照上一次分析（各頁同一條規則），不會變成沒有訊號。
      final unanalyzed = _partner().aggregateOver([
        _convo(
          id: 'v3',
          updatedAt: DateTime(2026, 10, 1),
          snapshotJson: v3(decision: 'send', light: 'green'),
        ),
        _convo(id: 'blank', updatedAt: DateTime(2026, 10, 18)),
      ]);
      expect(unanalyzed.latestGuideV3Signals!.light, GuideV3Light.green);
      // v3 形狀但決定讀不懂：還是 v3（不顯示熱度），只是沒有訊號。
      final unreadable = _partner().aggregateOver([
        _convo(
          id: 'odd',
          updatedAt: DateTime(2026, 10, 18),
          snapshotJson: v3(decision: 'maybe', light: 'green'),
        ),
      ]);
      expect(unreadable.latestIsGuideV3, isTrue);
      expect(unreadable.latestGuideV3Signals, isNull);
      expect(PartnerAggregateView.empty().latestGuideV3Signals, isNull);
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
