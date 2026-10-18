// 上一輪脈絡跟分析紀錄的生命週期（主審第 1 輪 P2）：用真的紀錄庫（Hive）存、收起、刪除。
// 舊制同一段對話多筆紀錄或只刪部分紀錄時，對話本身還在、快照也還在；被刪掉的那筆分析
// 不能再當上一輪送出，同一段對話裡被刪掉的較早片段也不能混進最後幾則。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/analysis/data/repositories/analysis_record_store.dart';
import 'package:vibesync/features/analysis/domain/entities/previous_round_context.dart';
import 'package:vibesync/features/analysis/domain/services/previous_round_builder.dart';
import 'package:vibesync/features/analysis_history/domain/entities/analysis_history_event.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/features/conversation/domain/services/conversation_content_revision.dart';

const _owner = 'owner-1';
const _partner = 'partner-1';
final _t0 = DateTime(2026, 10, 18, 9);

Map<String, dynamic> _v3Payload(String judgment) => {
      'guideVersion': 'v3.5',
      'read': {
        'guideVersion': 'v3.5',
        'decision': 'send',
        'light': 'green',
        'judgment': judgment,
        'plannedCards': [
          {'slot': 1, 'task': 'accept', 'locked': false},
        ],
      },
      'cards': [
        {
          'slot': 1,
          'task': 'accept',
          'method': 'reaction',
          'voice': 'default',
          'messages': ['好啊'],
          'hasInventedDetail': false,
          'hasBlank': false,
        },
      ],
      'partial': false,
    };

Message _message(int i) => Message(
      id: 'm$i',
      content: '第$i則',
      isFromMe: i.isOdd,
      timestamp: _t0.add(Duration(minutes: i)),
    );

void main() {
  late Box<dynamic> box;
  late HiveAnalysisRecordStore store;
  late List<AnalysisHistoryEvent> events;

  setUp(() async {
    Hive.init('./.dart_tool/test_hive_previous_round_lifecycle');
    box = await Hive.openBox<dynamic>(
      'previous_round_${DateTime.now().microsecondsSinceEpoch}',
    );
    store = HiveAnalysisRecordStore(() => box);
    events = [];
  });

  tearDown(() async {
    await box.deleteFromDisk();
  });

  /// 照持久化的做法：對話快照＝結果加 App meta（含歷史事件 id）並重存對話，記一筆歷史
  /// 事件；紀錄存結果原樣，存完就收起。
  Future<String> analyze(
    Conversation c,
    String judgment, {
    required DateTime at,
  }) async {
    final payload = _v3Payload(judgment);
    final eventId = 'event-${c.id}-$judgment';
    c.lastAnalysisSnapshotJson = jsonEncode({
      ...payload,
      '__vibesync_snapshot_meta_v1': {
        'messageCount': c.messages.length,
        'historyEventId': eventId,
      },
    });
    c.lastAnalyzedMessageCount = c.messages.length;
    c.updatedAt = at;
    events.add(AnalysisHistoryEvent.analyze(id: eventId, createdAt: at));
    final saved = await store.saveSuccessfulAnalysis(
      ownerUserId: _owner,
      conversation: c,
      completionKey: 'run-$judgment',
      runStartPreviousCount: 0,
      analyzedMessageCount: c.messages.length,
      analyzedContentRevision: conversationContentRevision(
        c,
        messageCount: c.messages.length,
      ),
      analysisSnapshotJson: jsonEncode(payload),
      enthusiasmScore: null,
      gameStageLabel: '',
    );
    expect(saved.accepted, isTrue, reason: saved.rejectionReason);
    expect(
      await store.archiveCurrentRecord(
        ownerUserId: _owner,
        conversationId: c.id,
      ),
      isTrue,
    );
    return saved.record!.id;
  }

  PreviousRoundContext? build(Conversation current, List<Conversation> all) =>
      const PreviousRoundBuilder().build(
        current: current,
        partnerConversations: all,
        historyEvents: events,
        liveRecordFor: (c) =>
            store.currentFor(ownerUserId: _owner, conversationId: c.id),
      );

  Conversation conversation(String id, int messages, DateTime at) =>
      Conversation(
        id: id,
        name: '小雲',
        messages: List.generate(messages, _message),
        createdAt: at,
        updatedAt: at,
        ownerUserId: _owner,
        partnerId: _partner,
      );

  test('刪掉上一段那筆紀錄（對話還在）：新片段就不帶上一輪', () async {
    final previous = conversation('prev', 2, _t0);
    final recordId = await analyze(
      previous,
      '她很熱',
      at: _t0.add(const Duration(minutes: 5)),
    );
    final next = conversation('next', 1, _t0.add(const Duration(hours: 1)));
    expect(build(next, [previous, next])?.judgment, '她很熱');

    expect(
      await store.deleteRecord(
        ownerUserId: _owner,
        conversationId: previous.id,
        recordId: recordId,
      ),
      isTrue,
    );
    // 對話與快照都還在，只是紀錄被刪了。
    expect(previous.lastAnalysisSnapshotJson, isNotNull);
    expect(build(next, [previous, next]), isNull);
  });

  test('舊制一段對話多筆紀錄：刪掉較早那筆，最後幾則只取現在那筆的片段；再刪現在那筆就不帶', () async {
    final legacy = conversation('legacy', 2, _t0);
    final olderRecordId = await analyze(
      legacy,
      '第一次',
      at: _t0.add(const Duration(minutes: 5)),
    );
    // 舊制：同一段對話之後又加了兩則再分析一次，紀錄往後接一筆。
    legacy.messages = [...legacy.messages, _message(2), _message(3)];
    final currentRecordId = await analyze(
      legacy,
      '第二次',
      at: _t0.add(const Duration(minutes: 10)),
    );
    expect(currentRecordId, isNot(olderRecordId));

    expect(
      await store.deleteRecord(
        ownerUserId: _owner,
        conversationId: legacy.id,
        recordId: olderRecordId,
      ),
      isTrue,
    );
    final next = conversation('next', 1, _t0.add(const Duration(hours: 1)));
    final context = build(next, [legacy, next])!;
    expect(context.judgment, '第二次');
    expect(context.messages.map((m) => m.content).toList(), ['第2則', '第3則']);

    expect(
      await store.deleteRecord(
        ownerUserId: _owner,
        conversationId: legacy.id,
        recordId: currentRecordId,
      ),
      isTrue,
    );
    expect(build(next, [legacy, next]), isNull);
  });
}
