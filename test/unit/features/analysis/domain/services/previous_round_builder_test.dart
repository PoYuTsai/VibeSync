// 上一輪脈絡（previousRound，Eric 2026-10-18）：只從同一個對象、這個片段建立之前
// 最近一次的 v3 結果組；上限跟伺服器一樣（每段 120、最多 4 則、合計 600）；
// 什麼都沒有就不帶。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/entities/previous_round_context.dart';
import 'package:vibesync/features/analysis/domain/services/previous_round_builder.dart';
import 'package:vibesync/features/analysis_history/domain/entities/analysis_history_event.dart';
import 'package:vibesync/features/coaching_memory/domain/entities/coaching_outcome_event.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';

const _partner = 'partner-a';
final _t0 = DateTime(2026, 10, 18, 9);

Map<String, dynamic> _v3Result({
  String decision = 'send',
  String light = 'yellow',
  String judgment = '她只回了貼圖，先等她多說一點。',
}) =>
    {
      'guideVersion': 'v3.5',
      'read': {
        'guideVersion': 'v3.5',
        'decision': decision,
        'light': light,
        'judgment': judgment,
        'plannedCards': [
          {'slot': 1, 'task': 'accept', 'locked': false},
        ],
      },
      'cards': decision == 'send'
          ? [
              {
                'slot': 1,
                'task': 'accept',
                'method': 'reaction',
                'voice': 'default',
                'messages': ['那週六去吃早午餐？'],
                'hasInventedDetail': false,
                'hasBlank': false,
              },
            ]
          : [],
      'partial': false,
    };

String _snapshot(
  Map<String, dynamic> result, {
  String? historyEventId,
  String? runId,
  int? messageCount,
}) =>
    jsonEncode({
      ...result,
      '__vibesync_snapshot_meta_v1': {
        'contentRevision': 'rev',
        if (messageCount != null) 'messageCount': messageCount,
        if (historyEventId != null) 'historyEventId': historyEventId,
        if (runId != null) 'analysisRunId': runId,
      },
    });

List<Message> _messages(List<(bool, String)> items) => [
      for (final (i, (isFromMe, content)) in items.indexed)
        Message(
          id: 'm$i',
          content: content,
          isFromMe: isFromMe,
          timestamp: _t0,
        ),
    ];

Conversation _segment({
  required String id,
  String? partnerId = _partner,
  String? snapshotJson,
  List<(bool, String)> messages = const [(false, '在嗎')],
  DateTime? createdAt,
  DateTime? updatedAt,
  String? ownerUserId = 'user-1',
}) {
  final msgs = _messages(messages);
  return Conversation(
    id: id,
    name: '小雲',
    messages: msgs,
    createdAt: createdAt ?? _t0,
    updatedAt: updatedAt ?? createdAt ?? _t0,
    lastAnalysisSnapshotJson: snapshotJson,
    lastAnalyzedMessageCount: snapshotJson == null ? null : msgs.length,
    partnerId: partnerId,
    ownerUserId: ownerUserId,
  );
}

AnalysisHistoryEvent _event(String id, DateTime createdAt) =>
    AnalysisHistoryEvent.analyze(id: id, createdAt: createdAt);

CoachingOutcomeEvent _copy(
  String id,
  String text, {
  required DateTime at,
  CoachingUserAction action = CoachingUserAction.sentAsIs,
  CoachingOutcomeSource source = CoachingOutcomeSource.analyze,
}) =>
    CoachingOutcomeEvent.create(
      id: id,
      source: source,
      suggestedMoveSummary: text,
      userAction: action,
      createdAt: at,
    );

PreviousRoundContext? _build({
  required Conversation current,
  required List<Conversation> others,
  List<AnalysisHistoryEvent> events = const [],
  Map<String, List<CoachingOutcomeEvent>> outcomes = const {},
}) =>
    const PreviousRoundBuilder().build(
      current: current,
      partnerConversations: [current, ...others],
      historyEvents: events,
      outcomesFor: (id) => outcomes[id] ?? const [],
    );

void main() {
  final newSegment = _segment(
    id: 'new',
    messages: [(false, '好啊，那就週六')],
    createdAt: _t0.add(const Duration(hours: 2)),
  );

  test('組出上次的燈號、決定、判讀、他複製的那張與上一段最後幾則', () {
    final previous = _segment(
      id: 'prev',
      snapshotJson:
          _snapshot(_v3Result(), historyEventId: 'e1', runId: 'run-1'),
      messages: [(true, '週末有空嗎'), (false, '應該在家耍廢')],
      updatedAt: _t0.add(const Duration(hours: 1)),
    );
    final context = _build(
      current: newSegment,
      others: [previous],
      events: [_event('e1', _t0.add(const Duration(minutes: 30)))],
      outcomes: {
        'prev': [
          _copy(
            'analyze:prev:run-1:v3:1:accept',
            '那週六去吃早午餐？',
            at: _t0.add(const Duration(minutes: 40)),
          ),
        ],
      },
    );
    expect(context, isNotNull);
    expect(context!.toJson(), {
      'decision': 'send',
      'light': 'yellow',
      'judgment': '她只回了貼圖，先等她多說一點。',
      'sentCard': '那週六去吃早午餐？',
      'messages': [
        {'isFromMe': true, 'content': '週末有空嗎'},
        {'isFromMe': false, 'content': '應該在家耍廢'},
      ],
    });
  });

  test('沒有對象、沒有別的片段、只有 v2 結果或自傷關心：不帶', () {
    final v2Snapshot = jsonEncode({
      'enthusiasm': {'score': 70},
      'replies': {'extend': 'a'},
    });
    final orphan = _segment(id: 'new', partnerId: null);
    expect(
      _build(
        current: orphan,
        others: [
          _segment(
              id: 'p', partnerId: null, snapshotJson: _snapshot(_v3Result()))
        ],
      ),
      isNull,
    );
    expect(_build(current: newSegment, others: const []), isNull);
    expect(
      _build(
        current: newSegment,
        others: [_segment(id: 'v2', snapshotJson: v2Snapshot)],
      ),
      isNull,
    );
    expect(
      _build(
        current: newSegment,
        others: [
          _segment(
            id: 'care',
            snapshotJson: _snapshot(_v3Result(decision: 'care', judgment: '')),
          ),
        ],
      ),
      isNull,
    );
    // 壞掉的快照不擋，當沒有。
    expect(
      _build(
        current: newSegment,
        others: [_segment(id: 'bad', snapshotJson: '{not json')],
      ),
      isNull,
    );
  });

  test('挑分析時間最近的那段：看歷史事件，不被之後的存檔（updatedAt）騙；沒有事件才看 updatedAt', () {
    final older = _segment(
      id: 'older',
      snapshotJson:
          _snapshot(_v3Result(judgment: '比較早那次'), historyEventId: 'e-old'),
      // 之後被改過名之類的存檔，updatedAt 比較新。
      updatedAt: _t0.add(const Duration(minutes: 90)),
    );
    final latest = _segment(
      id: 'latest',
      snapshotJson:
          _snapshot(_v3Result(judgment: '最近那次'), historyEventId: 'e-new'),
      updatedAt: _t0.add(const Duration(minutes: 50)),
    );
    final events = [
      _event('e-old', _t0.add(const Duration(minutes: 10))),
      _event('e-new', _t0.add(const Duration(minutes: 50))),
    ];
    expect(
      _build(current: newSegment, others: [older, latest], events: events)!
          .judgment,
      '最近那次',
    );
    // 沒有歷史事件（舊資料）：退回 updatedAt。
    expect(
      _build(current: newSegment, others: [older, latest])!.judgment,
      '比較早那次',
    );
  });

  test('上一輪是 v2 或自傷關心：不帶，也不跳去更早那段 v3', () {
    final olderV3 = _segment(
      id: 'older',
      snapshotJson:
          _snapshot(_v3Result(judgment: '更早的'), historyEventId: 'e-v3'),
    );
    final latestV2 = _segment(
      id: 'v2',
      snapshotJson: jsonEncode({
        'enthusiasm': {'score': 70},
        'replies': {'extend': 'a'},
        '__vibesync_snapshot_meta_v1': {'historyEventId': 'e-v2'},
      }),
    );
    final latestCare = _segment(
      id: 'care',
      snapshotJson: _snapshot(
        _v3Result(decision: 'care', judgment: ''),
        historyEventId: 'e-care',
      ),
    );
    final events = [
      _event('e-v3', _t0.add(const Duration(minutes: 10))),
      _event('e-v2', _t0.add(const Duration(minutes: 20))),
      _event('e-care', _t0.add(const Duration(minutes: 20))),
    ];
    expect(
      _build(current: newSegment, others: [olderV3, latestV2], events: events),
      isNull,
    );
    expect(
      _build(
        current: newSegment,
        others: [olderV3, latestCare],
        events: events,
      ),
      isNull,
    );
    expect(
      _build(current: newSegment, others: [olderV3], events: events)!.judgment,
      '更早的',
    );
  });

  test('只認這個片段建立之前分析完的、同一個對象、同一個帳號，不認自己', () {
    final self = _segment(
      id: 'new',
      snapshotJson: _snapshot(_v3Result(judgment: '自己')),
      createdAt: _t0.add(const Duration(hours: 2)),
    );
    final later = _segment(
      id: 'later',
      snapshotJson: _snapshot(_v3Result(judgment: '比較晚')),
      updatedAt: _t0.add(const Duration(hours: 3)),
    );
    final otherPartner = _segment(
      id: 'other',
      partnerId: 'partner-b',
      snapshotJson: _snapshot(_v3Result(judgment: '別的對象')),
    );
    final otherOwner = _segment(
      id: 'owner',
      ownerUserId: 'user-2',
      snapshotJson: _snapshot(_v3Result(judgment: '別的帳號')),
    );
    expect(
      _build(current: self, others: [later, otherPartner, otherOwner]),
      isNull,
    );
    final earlier = _segment(
      id: 'earlier',
      snapshotJson: _snapshot(_v3Result(judgment: '上一輪')),
      updatedAt: _t0.add(const Duration(hours: 1)),
    );
    expect(
      _build(current: self, others: [later, otherPartner, otherOwner, earlier])!
          .judgment,
      '上一輪',
    );
  });

  test('他複製的那張：只認那一次 run 的 v3 卡（含再調過的），回報沒送的不算，取最後一次', () {
    final previous = _segment(
      id: 'prev',
      snapshotJson: _snapshot(_v3Result(), runId: 'run-1'),
    );
    String? sentCard(List<CoachingOutcomeEvent> events) => _build(
          current: newSegment,
          others: [previous],
          outcomes: {'prev': events},
        )!
            .sentCard;

    expect(sentCard(const []), isNull);
    expect(
      sentCard([
        _copy('analyze:prev:run-1:v3:1:accept', '第一張', at: _t0),
        _copy(
          'refine:analyze:prev:run-1:v3:2:tension:req-9',
          '再調過的第二張',
          at: _t0.add(const Duration(minutes: 5)),
        ),
        // 別次 run、v2 的卡、別的來源都不算。
        _copy(
          'analyze:prev:run-0:v3:1:accept',
          '別次的卡',
          at: _t0.add(const Duration(minutes: 9)),
        ),
        _copy(
          'analyze:prev:run-1:polish',
          '潤飾',
          at: _t0.add(const Duration(minutes: 9)),
        ),
        _copy(
          'analyze:prev:run-1:v3:3:push',
          '教練的',
          at: _t0.add(const Duration(minutes: 9)),
          source: CoachingOutcomeSource.coach,
        ),
      ]),
      '再調過的第二張',
    );
    expect(
      sentCard([
        _copy('analyze:prev:run-1:v3:1:accept', '第一張', at: _t0),
        _copy(
          'analyze:prev:run-1:v3:2:tension',
          '複製了但沒送',
          at: _t0.add(const Duration(minutes: 5)),
          action: CoachingUserAction.didNotSend,
        ),
      ]),
      '第一張',
    );
    // 快照沒有 runId（舊資料）就對不回複製紀錄。
    expect(
      _build(
        current: newSegment,
        others: [_segment(id: 'prev', snapshotJson: _snapshot(_v3Result()))],
        outcomes: {
          'prev': [_copy('analyze:prev:run-1:v3:1:accept', '卡', at: _t0)],
        },
      )!
          .sentCard,
      isNull,
    );
  });

  test('上限：每段超過 120 截到 119 加「…」、只取最後 4 則、合計超過 600 從最舊的一則拿掉', () {
    final long = '字' * 200;
    final previous = _segment(
      id: 'prev',
      snapshotJson: _snapshot(_v3Result(judgment: long), runId: 'run-1'),
      messages: [
        for (var i = 0; i < 6; i++) (i.isOdd, '第$i則${'話' * 150}'),
      ],
    );
    final context = _build(
      current: newSegment,
      others: [previous],
      outcomes: {
        'prev': [_copy('analyze:prev:run-1:v3:1:accept', '卡' * 150, at: _t0)],
      },
    )!;
    expect(context.judgment!.length, PreviousRoundBuilder.maxTextChars);
    expect(context.judgment, '${'字' * 119}…');
    expect(context.sentCard!.length, PreviousRoundBuilder.maxTextChars);
    for (final message in context.messages) {
      expect(message.content.length, PreviousRoundBuilder.maxTextChars);
    }
    // 判讀 120＋卡 120＋最多 3 則 120＝600：最後 4 則裡最舊的那則被拿掉。
    expect(context.messages.map((m) => m.content.substring(0, 3)).toList(), [
      '第3則',
      '第4則',
      '第5則',
    ]);
    expect(context.charCount, PreviousRoundBuilder.maxChars);
    // 沒有判讀與卡時，最後 4 則都留得下。
    final noExtras = _build(
      current: newSegment,
      others: [
        _segment(
          id: 'prev2',
          snapshotJson: _snapshot(_v3Result(judgment: '')),
          messages: [for (var i = 0; i < 6; i++) (i.isOdd, '第$i則')],
        ),
      ],
    )!;
    expect(noExtras.judgment, isNull);
    expect(noExtras.messages.map((m) => m.content).toList(), [
      '第2則',
      '第3則',
      '第4則',
      '第5則',
    ]);
  });

  test('截斷不切開 emoji', () {
    final previous = _segment(
      id: 'prev',
      snapshotJson: _snapshot(_v3Result(judgment: '${'字' * 118}😀😀')),
    );
    final judgment = _build(current: newSegment, others: [previous])!.judgment!;
    expect(judgment, '${'字' * 118}…');
    expect(judgment.length <= PreviousRoundBuilder.maxTextChars, isTrue);
  });

  test('只取那次分析過的訊息（快照的 messageCount）', () {
    final previous = _segment(
      id: 'prev',
      snapshotJson: _snapshot(_v3Result(judgment: ''), messageCount: 2),
      messages: [(true, '一'), (false, '二'), (true, '分析之後才加的')],
    );
    expect(
      _build(current: newSegment, others: [previous])!
          .messages
          .map((m) => m.content)
          .toList(),
      ['一', '二'],
    );
  });
}
