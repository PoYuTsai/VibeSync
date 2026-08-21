// 注入回歸：AnalysisPersistenceCoordinator 只透過具名注入的依賴工作，
// 不碰 Riverpod。以假依賴驗證還原、修訂守門與 canonical 持久化行為。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/application/analysis_persistence_coordinator.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_models.dart';
import 'package:vibesync/features/analysis_history/domain/entities/analysis_history_event.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_write_controller.dart'
    show ConversationSaveIntent;
import 'package:vibesync/features/conversation/data/repositories/conversation_archive_store.dart'
    show conversationContentRevision;
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';

import '../../../../helpers/memory_analysis_history_repository.dart';

const _conversationId = 'persistence-conv';

Map<String, dynamic> _resultJson() => {
      'enthusiasm': {'score': 70, 'level': 'warm'},
      'gameStage': {
        'current': 'premise',
        'status': 'normal',
        'nextStep': '繼續',
      },
      'psychology': {'subtext': '有興趣', 'qualificationSignal': true},
      'topicDepth': {'current': 'personal', 'suggestion': '可深入'},
      'replies': {
        'extend': 'a',
        'resonate': 'b',
        'tease': 'c',
        'humor': 'd',
        'coldRead': 'e',
      },
      'finalRecommendation': {
        'pick': 'tease',
        'content': 'c',
        'reason': 'r',
        'psychology': 'p',
      },
      'strategy': '保持沉穩',
    };

Conversation _conversation({String? snapshotJson, int? analyzedCount}) {
  return Conversation(
    id: _conversationId,
    name: '小雲',
    messages: [
      Message(
        id: 'm1',
        content: '今天加班好累喔',
        isFromMe: false,
        timestamp: DateTime(2026, 5, 28, 12),
      ),
    ],
    createdAt: DateTime(2026, 5, 28, 12),
    updatedAt: DateTime(2026, 5, 28, 12),
    lastAnalysisSnapshotJson: snapshotJson,
    lastAnalyzedMessageCount: analyzedCount,
  );
}

class _Harness {
  _Harness({required this.conversation});

  final Conversation conversation;
  final history = MemoryAnalysisHistoryRepository();
  final savedIntents = <ConversationSaveIntent>[];
  final savedExpectedRevisions = <String?>[];
  final funnelEvents = <String>[];
  final afterPersisted = <Conversation>[];
  int notifyCount = 0;
  int invalidateCount = 0;

  late final AnalysisPersistenceCoordinator coordinator =
      AnalysisPersistenceCoordinator(
    conversationId: _conversationId,
    getConversation: (id) => id == conversation.id ? conversation : null,
    saveConversation: (conv, {required intent, expectedContentRevision}) async {
      savedIntents.add(intent);
      savedExpectedRevisions.add(expectedContentRevision);
    },
    markConversationActive: (_) async {},
    archiveEntryFor: (_) => null,
    // 擁有者缺席時所有紀錄路徑都必須在碰 store 之前就短路；真的碰到就炸。
    recordStore: () => throw UnimplementedError('record store must not be hit'),
    currentRecordOwnerUserId: () => null,
    historyRepository: () => history,
    trackFunnelOnce: (eventKey) async => funnelEvents.add(eventKey),
    lastPayloadCharCount: () => 42,
    notifyStateChanged: () {},
    invalidateRecordViews: (_) {},
    afterAnalysisPersisted: (conv) async => afterPersisted.add(conv),
  );
}

void main() {
  test('restore：讀注入的 getConversation，驗證內嵌修訂後還原並排程修復', () async {
    final base = _conversation();
    final snapshot = _resultJson()
      ..['__vibesync_snapshot_meta_v1'] = {
        'contentRevision': conversationContentRevision(base, messageCount: 1),
        'messageCount': 1,
      };
    final harness = _Harness(
      conversation: _conversation(
        snapshotJson: jsonEncode(snapshot),
        analyzedCount: 1,
      ),
    );

    final outcome = harness.coordinator.restore(repairRecord: true);
    expect(outcome, isNotNull);
    expect(outcome!.analyzedMessageCount, 1);
    expect(outcome.result.strategy, '保持沉穩');

    // 修復已排程；owner 缺席 → 不碰 store、標記待修復，等待可落定。
    expect(harness.coordinator.recordRepairFuture, isNotNull);
    await harness.coordinator.awaitSettled();
    expect(harness.coordinator.recordNeedsRepair, isTrue);
  });

  test('restore：修訂不符（同數量編輯）不得還原', () {
    final snapshot = _resultJson()
      ..['__vibesync_snapshot_meta_v1'] = {
        // 同數量、不同內容的修訂：模擬使用者就地編輯過訊息。
        'contentRevision': 'edited-away-revision',
        'messageCount': 1,
      };
    final harness = _Harness(
      conversation: _conversation(
        snapshotJson: jsonEncode(snapshot),
        analyzedCount: 1,
      ),
    );

    expect(harness.coordinator.restore(repairRecord: true), isNull);
  });

  test('persistLatestSnapshot：修訂不符時整段短路，不寫任何東西', () async {
    final harness = _Harness(conversation: _conversation());

    await harness.coordinator.persistLatestSnapshot(
      AnalysisResult.fromJson(_resultJson()),
      completionKey: 'run-1',
      previousAnalyzedCount: 0,
      analyzedMessageCount: 1,
      analyzedContentRevision: 'stale-revision',
    );

    expect(harness.savedIntents, isEmpty);
    expect(harness.history.listRecent(), isEmpty);
    expect(harness.funnelEvents, isEmpty);
    expect(harness.afterPersisted, isEmpty);
  });

  test(
      'persistLatestSnapshot：happy path 走注入依賴——canonical 存檔、'
      'payload 字數 baseline、歷史事件、漏斗與畫面後續', () async {
    final harness = _Harness(conversation: _conversation());
    final revision = conversationContentRevision(harness.conversation);

    await harness.coordinator.persistLatestSnapshot(
      AnalysisResult.fromJson(_resultJson()),
      completionKey: 'run-1',
      previousAnalyzedCount: 0,
      analyzedMessageCount: 1,
      analyzedContentRevision: revision,
    );
    await harness.coordinator.awaitSettled();

    expect(harness.savedIntents, [ConversationSaveIntent.analysisCompleted]);
    expect(harness.savedExpectedRevisions, [revision]);
    // ADR #19 規格 #8：char baseline 來自注入的 lastPayloadCharCount。
    expect(harness.conversation.lastAnalyzedCharCount, 42);
    expect(harness.conversation.lastAnalysisSnapshotJson, isNotNull);
    expect(
      harness.history.listRecent().single.kind,
      AnalysisHistoryKind.analyze,
    );
    expect(harness.funnelEvents, ['first_analysis_completed']);
    expect(harness.afterPersisted.single.id, _conversationId);
    // owner 缺席 → 紀錄未落地要標記修復（且 store accessor 從未被觸發）。
    expect(harness.coordinator.recordNeedsRepair, isTrue);
    expect(harness.coordinator.inFlightCount, 0);
  });
}
