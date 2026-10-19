// 注入回歸：AnalysisPersistenceCoordinator 只透過具名注入的依賴工作，
// 不碰 Riverpod。以假依賴驗證還原、修訂守門與 canonical 持久化行為。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/application/analysis_persistence_coordinator.dart';
import 'package:vibesync/features/analysis/application/ports/analysis_record_port.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_models.dart';
import 'package:vibesync/features/analysis/domain/entities/persistable_analysis.dart';
import 'package:vibesync/features/analysis/domain/entities/guide_v3_result.dart';
import 'package:vibesync/features/analysis/domain/entities/game_stage.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_record.dart';
import 'package:vibesync/features/analysis_history/domain/entities/analysis_history_event.dart';
import 'package:vibesync/features/analysis_history/domain/repositories/analysis_history_repository.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/session_context.dart';
import 'package:vibesync/features/conversation/domain/services/conversation_content_revision.dart';
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

Conversation _conversation({
  String? snapshotJson,
  int? analyzedCount,
  String? partnerId,
  String? currentGameStage,
  String? ownerUserId,
  SessionContext? sessionContext,
}) {
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
    partnerId: partnerId,
    currentGameStage: currentGameStage,
    ownerUserId: ownerUserId,
    sessionContext: sessionContext,
  );
}

/// 擁有者缺席時任何方法被呼叫都算違規。
class _ThrowingAnalysisRecordPort implements AnalysisRecordPort {
  @override
  AnalysisRecord? currentFor({
    required String ownerUserId,
    required String conversationId,
  }) =>
      throw UnimplementedError('record port must not be hit');

  @override
  Future<AnalysisRecordSaveOutcome> saveSuccessfulAnalysis({
    required String ownerUserId,
    required Conversation conversation,
    required String completionKey,
    required int runStartPreviousCount,
    required int analyzedMessageCount,
    required String analyzedContentRevision,
    required String analysisSnapshotJson,
    required int? enthusiasmScore,
    required String gameStageLabel,
    bool allowArchivedRefresh = false,
    String? sourcePlatform,
  }) =>
      throw UnimplementedError('record port must not be hit');

  @override
  Future<bool> archiveCurrentRecord({
    required String ownerUserId,
    required String conversationId,
  }) =>
      throw UnimplementedError('record port must not be hit');

  @override
  String? conversationSource({
    required String ownerUserId,
    required String conversationId,
  }) =>
      throw UnimplementedError('record port must not be hit');
}

class _RecordingAnalysisRecordPort implements AnalysisRecordPort {
  final savedStageLabels = <String>[];

  @override
  AnalysisRecord? currentFor({
    required String ownerUserId,
    required String conversationId,
  }) =>
      null;

  @override
  Future<AnalysisRecordSaveOutcome> saveSuccessfulAnalysis({
    required String ownerUserId,
    required Conversation conversation,
    required String completionKey,
    required int runStartPreviousCount,
    required int analyzedMessageCount,
    required String analyzedContentRevision,
    required String analysisSnapshotJson,
    required int? enthusiasmScore,
    required String gameStageLabel,
    bool allowArchivedRefresh = false,
    String? sourcePlatform,
  }) async {
    savedStageLabels.add(gameStageLabel);
    return const AnalysisRecordSaveOutcome(accepted: true);
  }

  @override
  Future<bool> archiveCurrentRecord({
    required String ownerUserId,
    required String conversationId,
  }) async =>
      true;

  @override
  String? conversationSource({
    required String ownerUserId,
    required String conversationId,
  }) =>
      null;
}

/// 記下每次紀錄寫入的熱度、階段與快照（v3 測試用）。
class _CapturingAnalysisRecordPort implements AnalysisRecordPort {
  final saves = <({int? score, String stage, String snapshot})>[];

  @override
  AnalysisRecord? currentFor({
    required String ownerUserId,
    required String conversationId,
  }) =>
      null;

  @override
  Future<AnalysisRecordSaveOutcome> saveSuccessfulAnalysis({
    required String ownerUserId,
    required Conversation conversation,
    required String completionKey,
    required int runStartPreviousCount,
    required int analyzedMessageCount,
    required String analyzedContentRevision,
    required String analysisSnapshotJson,
    required int? enthusiasmScore,
    required String gameStageLabel,
    bool allowArchivedRefresh = false,
    String? sourcePlatform,
  }) async {
    saves.add((
      score: enthusiasmScore,
      stage: gameStageLabel,
      snapshot: analysisSnapshotJson,
    ));
    return const AnalysisRecordSaveOutcome(accepted: true);
  }

  @override
  Future<bool> archiveCurrentRecord({
    required String ownerUserId,
    required String conversationId,
  }) async =>
      true;

  @override
  String? conversationSource({
    required String ownerUserId,
    required String conversationId,
  }) =>
      null;
}

/// 關係狀態（伺服器開關 ANALYZE_GUIDE_V3_RELATION 開著時，判讀的 relation）。
const _relationJson = <String, dynamic>{
  'stage': 'narrative',
  'heat': 72,
  'dimensions': {
    'heat': 72,
    'engagement': 70,
    'topicDepth': 45,
    'replyWillingness': 78,
    'emotionalConnection': 60,
  },
  'herMove': 'serious_question',
  'willingness': 'high',
};

/// 形狀照伺服器 guide_v3/wire.ts 的 finalResult（已剝掉伺服器專用欄位）。
Map<String, dynamic> _guideV3Json({
  String decision = 'send',
  Map<String, dynamic>? relation,
}) =>
    {
      'guideVersion': 'v3.4',
      'read': {
        'guideVersion': 'v3.4',
        'decision': decision,
        'light': 'green',
        'judgment': decision == 'care' ? '' : '她有在接你的話。',
        if (relation != null) 'relation': relation,
        if (decision == 'care') 'careMessage': '先把安全放在第一位。',
        'plannedCards': decision == 'send'
            ? [
                {'slot': 1, 'task': 'accept', 'locked': false},
              ]
            : [],
      },
      'cards': decision == 'send'
          ? [
              {
                'slot': 1,
                'task': 'accept',
                'method': 'reaction',
                'voice': 'default',
                'messages': ['那家我也想吃吃看'],
                'hasInventedDetail': false,
                'hasBlank': false,
              },
            ]
          : [],
      'partial': false,
      'usage': {
        'messagesUsed': decision == 'care' ? 0 : 1,
        'shouldChargeQuota': decision != 'care',
      },
    };

PersistableAnalysis _guideV3({
  String decision = 'send',
  String? runId,
  Map<String, dynamic>? relation,
}) =>
    PersistableAnalysis.fromGuideV3(
      GuideV3Result.fromJson(
        _guideV3Json(decision: decision, relation: relation),
      )!,
      analysisRunId: runId,
    );

class _FailOnceAnalysisHistoryRepository
    extends MemoryAnalysisHistoryRepository {
  bool failNextAppend = false;

  @override
  Future<void> append(AnalysisHistoryEvent event) async {
    if (failNextAppend) {
      failNextAppend = false;
      throw StateError('simulated history write failure');
    }
    await super.append(event);
  }
}

class _Harness {
  _Harness({
    required this.conversation,
    AnalysisRecordPort? recordPort,
    String? recordOwnerUserId,
    AnalysisHistoryRepository? historyRepository,
    void Function(Conversation conversation)? onPersistAnalysisCompleted,
  })  : _recordPort = recordPort ?? _ThrowingAnalysisRecordPort(),
        _recordOwnerUserId = recordOwnerUserId,
        _onPersistAnalysisCompleted = onPersistAnalysisCompleted,
        history = historyRepository ?? MemoryAnalysisHistoryRepository();

  final Conversation conversation;
  final AnalysisRecordPort _recordPort;
  final String? _recordOwnerUserId;
  final void Function(Conversation conversation)? _onPersistAnalysisCompleted;
  final AnalysisHistoryRepository history;
  final analysisCompletedSaves = <String>[];
  final contentChangedSaves = <String>[];
  final funnelEvents = <String>[];
  final afterPersisted = <Conversation>[];
  final silencedFollowUps = <bool>[];

  /// 協調器自己收回提醒的對象（不靠畫面；主審第 1 輪 finding 1）。
  final silencedPartners = <String>[];
  int notifyCount = 0;
  int invalidateCount = 0;

  late final AnalysisPersistenceCoordinator coordinator =
      AnalysisPersistenceCoordinator(
    conversationId: _conversationId,
    getConversation: (id) => id == conversation.id ? conversation : null,
    persistAnalysisCompleted: (conv, {required expectedContentRevision}) async {
      analysisCompletedSaves.add(expectedContentRevision);
      _onPersistAnalysisCompleted?.call(conv);
    },
    persistContentChanged: (conv) async {
      contentChangedSaves.add(conv.id);
    },
    markConversationActive: (_) async {},
    archiveMarkerFor: (_) => null,
    // 擁有者缺席時所有紀錄路徑都必須在碰 record port 之前就短路。
    recordPort: _recordPort,
    currentRecordOwnerUserId: () => _recordOwnerUserId,
    historyRepository: () => history,
    trackFunnelOnce: (eventKey) async => funnelEvents.add(eventKey),
    lastPayloadCharCount: () => 42,
    notifyStateChanged: () {},
    invalidateRecordViews: (_) {},
    afterAnalysisPersisted: (conv, {required silenceFollowUp}) async {
      afterPersisted.add(conv);
      silencedFollowUps.add(silenceFollowUp);
    },
    silenceFollowUp: (partnerId) async => silencedPartners.add(partnerId),
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
    expect(outcome.result!.strategy, '保持沉穩');

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
      PersistableAnalysis.fromResult(AnalysisResult.fromJson(_resultJson())),
      completionKey: 'run-1',
      previousAnalyzedCount: 0,
      analyzedMessageCount: 1,
      analyzedContentRevision: 'stale-revision',
    );

    expect(harness.analysisCompletedSaves, isEmpty);
    expect(harness.contentChangedSaves, isEmpty);
    expect(harness.history.listRecent(), isEmpty);
    expect(harness.funnelEvents, isEmpty);
    expect(harness.afterPersisted, isEmpty);
  });

  test(
      'persistLatestSnapshot：happy path 走注入依賴——canonical 存檔、'
      'payload 字數 baseline、歷史事件、漏斗與畫面後續', () async {
    final originalContext = SessionContext(
      meetingContext: MeetingContext.inPerson,
      duration: AcquaintanceDuration.justMet,
    );
    final analyzedContext = SessionContext(
      meetingContext: MeetingContext.committedPartner,
      duration: AcquaintanceDuration.monthPlus,
      goal: UserGoal.maintainHeat,
      userStyle: UserStyle.steady,
      userInterests: '咖啡',
      targetDescription: '慢熟',
      analysisContextNote: '重新連線',
    );
    final harness = _Harness(
      conversation: _conversation(sessionContext: originalContext),
    );
    final revision = conversationContentRevision(harness.conversation);

    await harness.coordinator.persistLatestSnapshot(
      PersistableAnalysis.fromResult(AnalysisResult.fromJson(_resultJson())),
      completionKey: 'run-1',
      previousAnalyzedCount: 0,
      analyzedMessageCount: 1,
      analyzedContentRevision: revision,
      analyzedPartnerId: null,
      analyzedIsReconnect: true,
      analyzedSessionContext: analyzedContext,
    );
    await harness.coordinator.awaitSettled();

    expect(harness.analysisCompletedSaves, [revision]);
    expect(harness.contentChangedSaves, isEmpty);
    // ADR #19 規格 #8：char baseline 來自注入的 lastPayloadCharCount。
    expect(harness.conversation.lastAnalyzedCharCount, 42);
    expect(harness.conversation.lastAnalysisSnapshotJson, isNotNull);
    expect(harness.conversation.sessionContext, same(originalContext));
    final snapshot = jsonDecode(
      harness.conversation.lastAnalysisSnapshotJson!,
    ) as Map<String, dynamic>;
    final meta =
        snapshot['__vibesync_snapshot_meta_v1'] as Map<String, dynamic>;
    final frozen = meta['sessionContext'] as Map<String, dynamic>;
    expect(frozen, {
      'meetingContext': 'committedPartner',
      'duration': 'monthPlus',
      'goal': 'maintainHeat',
      'userStyle': 'steady',
      'userInterests': '咖啡',
      'targetDescription': '慢熟',
      'analysisContextNote': '重新連線',
    });
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

  test('persistLatestSnapshot：「資料不夠」免扣時不推進字數 baseline', () async {
    final harness = _Harness(conversation: _conversation());
    harness.conversation.lastAnalyzedCharCount = 7;
    final revision = conversationContentRevision(harness.conversation);

    await harness.coordinator.persistLatestSnapshot(
      PersistableAnalysis.fromResult(AnalysisResult.fromJson({
        ..._resultJson(),
        'usage': {
          'messagesUsed': 0,
          'shouldChargeQuota': false,
          'quotaWaivedReason': 'need_context_waived',
        },
      })),
      completionKey: 'run-waived',
      previousAnalyzedCount: 0,
      analyzedMessageCount: 1,
      analyzedContentRevision: revision,
      analyzedPartnerId: null,
      analyzedIsReconnect: null,
      analyzedSessionContext: null,
    );
    await harness.coordinator.awaitSettled();

    expect(harness.analysisCompletedSaves, [revision]);
    expect(harness.conversation.lastAnalyzedCharCount, 7);
  });

  group('stage snapshot 守門（對象卡互動階段閉環）', () {
    test('合法 stage：寫入 currentGameStage，歷史事件帶 partnerId＋stage＋完成時間', () async {
      final harness = _Harness(
        conversation: _conversation(
          partnerId: 'partner-1',
          currentGameStage: 'opening',
        ),
      );
      final revision = conversationContentRevision(harness.conversation);

      await harness.coordinator.persistLatestSnapshot(
        PersistableAnalysis.fromResult(AnalysisResult.fromJson(
            _resultJson())), // gameStage.current = premise
        completionKey: 'run-1',
        previousAnalyzedCount: 0,
        analyzedMessageCount: 1,
        analyzedContentRevision: revision,
      );
      await harness.coordinator.awaitSettled();

      expect(harness.conversation.currentGameStage, 'premise');
      final event = harness.history.listRecent().single;
      expect(event.partnerId, 'partner-1');
      expect(event.gameStageLabel, 'premise');
      expect(event.createdAt, isNotNull);
    });

    test('伴侶的 opening：canonical history 保留 opening，封存可見文案寫重新連線', () async {
      final recordPort = _RecordingAnalysisRecordPort();
      final harness = _Harness(
        conversation: _conversation(
          partnerId: 'partner-1',
          ownerUserId: 'u-1',
          sessionContext: SessionContext(
            meetingContext: MeetingContext.committedPartner,
            duration: AcquaintanceDuration.monthPlus,
            goal: UserGoal.justChat,
          ),
        ),
        recordPort: recordPort,
        recordOwnerUserId: 'u-1',
      );
      final revision = conversationContentRevision(harness.conversation);
      final json = _resultJson();
      (json['gameStage'] as Map<String, dynamic>)['current'] = 'opening';

      await harness.coordinator.persistLatestSnapshot(
        PersistableAnalysis.fromResult(AnalysisResult.fromJson(json)),
        completionKey: 'run-reconnect',
        previousAnalyzedCount: 0,
        analyzedMessageCount: 1,
        analyzedContentRevision: revision,
      );
      await harness.coordinator.awaitSettled();

      expect(harness.history.listRecent().single.gameStageLabel, 'opening');
      expect(harness.history.listRecent().single.isReconnect, isTrue);
      expect(recordPort.savedStageLabels, ['重新連線']);
    });

    test('非法 stage（vibing hard）：不覆蓋舊快照、事件不帶 stage、其餘落地照舊', () async {
      final recordPort = _RecordingAnalysisRecordPort();
      final harness = _Harness(
        conversation: _conversation(
          partnerId: 'partner-1',
          currentGameStage: 'close',
          ownerUserId: 'u-1',
        ),
        recordPort: recordPort,
        recordOwnerUserId: 'u-1',
      );
      final revision = conversationContentRevision(harness.conversation);
      final json = _resultJson();
      (json['gameStage'] as Map<String, dynamic>)['current'] = 'vibing hard';

      await harness.coordinator.persistLatestSnapshot(
        PersistableAnalysis.fromResult(AnalysisResult.fromJson(json)),
        completionKey: 'run-1',
        previousAnalyzedCount: 0,
        analyzedMessageCount: 1,
        analyzedContentRevision: revision,
      );
      await harness.coordinator.awaitSettled();

      // 舊有效快照保留，不得假裝成 opening。
      expect(harness.conversation.currentGameStage, 'close');
      // 熱度事件照常 exactly-once 落地，但不帶非法 stage。
      final event = harness.history.listRecent().single;
      expect(event.gameStageLabel, isNull);
      expect(event.enthusiasmScore, 70);
      expect(recordPort.savedStageLabels, ['準備邀約']);
      expect(recordPort.savedStageLabels, isNot(contains('破冰階段')));
      expect(harness.analysisCompletedSaves, [revision]);
    });

    test('同一 content revision 重跑：不新增第二筆趨勢事件（閉環驗收 16）', () async {
      final harness = _Harness(
        conversation: _conversation(partnerId: 'partner-1'),
      );
      final revision = conversationContentRevision(harness.conversation);

      await harness.coordinator.persistLatestSnapshot(
        PersistableAnalysis.fromResult(AnalysisResult.fromJson(_resultJson())),
        completionKey: 'run-1',
        previousAnalyzedCount: 0,
        analyzedMessageCount: 1,
        analyzedContentRevision: revision,
      );
      await harness.coordinator.awaitSettled();
      expect(harness.history.listRecent(), hasLength(1));
      final firstEvent = harness.history.listRecent().single;

      // 同內容重試／重新整理：新 run、新 completionKey，但 revision 相同
      // → 原地更新同一次分析，不得長出第二筆趨勢事件或保留舊 stage。
      final rerunJson = _resultJson()
        ..['enthusiasm'] = {'score': 81, 'level': 'veryHot'}
        ..['gameStage'] = {
          'current': 'close',
          'status': 'canAdvance',
          'nextStep': '敲時間',
        };
      await harness.coordinator.persistLatestSnapshot(
        PersistableAnalysis.fromResult(AnalysisResult.fromJson(rerunJson)),
        completionKey: 'run-2-retry',
        previousAnalyzedCount: 0,
        analyzedMessageCount: 1,
        analyzedContentRevision: revision,
      );
      await harness.coordinator.awaitSettled();
      expect(harness.history.listRecent(), hasLength(1));
      final updatedEvent = harness.history.listRecent().single;
      expect(updatedEvent.id, firstEvent.id);
      expect(updatedEvent.createdAt, firstEvent.createdAt);
      expect(updatedEvent.enthusiasmScore, 81);
      expect(updatedEvent.gameStageLabel, 'close');

      // 新訊息 → 新 revision → 新分析成功才新增趨勢事件。
      harness.conversation.messages.add(
        Message(
          id: 'm2',
          content: '週六要不要喝咖啡',
          isFromMe: false,
          timestamp: DateTime(2026, 5, 28, 13),
        ),
      );
      final newRevision = conversationContentRevision(harness.conversation);
      await harness.coordinator.persistLatestSnapshot(
        PersistableAnalysis.fromResult(AnalysisResult.fromJson(_resultJson())),
        completionKey: 'run-3',
        previousAnalyzedCount: 1,
        analyzedMessageCount: 2,
        analyzedContentRevision: newRevision,
      );
      await harness.coordinator.awaitSettled();
      expect(harness.history.listRecent(), hasLength(2));
    });

    test('首次趨勢寫入失敗後重跑：補同一事件且不覆蓋更早趨勢', () async {
      final history = _FailOnceAnalysisHistoryRepository();
      await history.append(
        AnalysisHistoryEvent.analyze(
          id: 'older-event',
          createdAt: DateTime.utc(2026, 5, 1),
          conversationId: _conversationId,
          partnerId: 'partner-1',
          enthusiasmScore: 55,
          gameStageLabel: 'qualification',
        ),
      );
      history.failNextAppend = true;
      final harness = _Harness(
        conversation: _conversation(partnerId: 'partner-1'),
        historyRepository: history,
      );
      final revision = conversationContentRevision(harness.conversation);

      await harness.coordinator.persistLatestSnapshot(
        PersistableAnalysis.fromResult(AnalysisResult.fromJson(_resultJson())),
        completionKey: 'run-write-fails',
        previousAnalyzedCount: 0,
        analyzedMessageCount: 1,
        analyzedContentRevision: revision,
      );
      await harness.coordinator.awaitSettled();

      // 主 snapshot 已帶本次 event id，但 best-effort history 第一次漏寫。
      final snapshot = jsonDecode(
        harness.conversation.lastAnalysisSnapshotJson!,
      ) as Map<String, dynamic>;
      final meta =
          snapshot['__vibesync_snapshot_meta_v1'] as Map<String, dynamic>;
      final expectedEventId = meta['historyEventId'] as String;
      expect(history.listRecent().map((event) => event.id), ['older-event']);

      final rerunJson = _resultJson()
        ..['enthusiasm'] = {'score': 81, 'level': 'veryHot'}
        ..['gameStage'] = {
          'current': 'close',
          'status': 'canAdvance',
          'nextStep': '敲時間',
        };
      await harness.coordinator.persistLatestSnapshot(
        PersistableAnalysis.fromResult(AnalysisResult.fromJson(rerunJson)),
        completionKey: 'run-retry',
        previousAnalyzedCount: 0,
        analyzedMessageCount: 1,
        analyzedContentRevision: revision,
      );
      await harness.coordinator.awaitSettled();

      expect(history.listRecent(), hasLength(2));
      final older = history.listRecent().singleWhere(
            (event) => event.id == 'older-event',
          );
      expect(older.enthusiasmScore, 55);
      expect(older.gameStageLabel, 'qualification');
      final repaired = history.listRecent().singleWhere(
            (event) => event.id == expectedEventId,
          );
      expect(repaired.enthusiasmScore, 81);
      expect(repaired.gameStageLabel, 'close');
    });

    test('舊 snapshot 只有 revision/count：重跑更新匹配事件，不新增趨勢', () async {
      final conversation = _conversation(
        partnerId: 'partner-1',
        currentGameStage: 'premise',
      )..lastEnthusiasmScore = 70;
      final revision = conversationContentRevision(conversation);
      final legacySnapshot = _resultJson()
        ..['__vibesync_snapshot_meta_v1'] = {
          'contentRevision': revision,
          'messageCount': 1,
        };
      conversation
        ..lastAnalysisSnapshotJson = jsonEncode(legacySnapshot)
        ..lastAnalyzedMessageCount = 1;

      final history = MemoryAnalysisHistoryRepository();
      await history.append(
        AnalysisHistoryEvent.analyze(
          id: 'older-event',
          createdAt: DateTime.utc(2026, 5, 1),
          conversationId: _conversationId,
          partnerId: 'partner-1',
          enthusiasmScore: 45,
          gameStageLabel: 'opening',
          isReconnect: false,
        ),
      );
      await history.append(
        AnalysisHistoryEvent.analyze(
          id: 'legacy-current',
          createdAt: DateTime.utc(2026, 5, 28),
          conversationId: _conversationId,
          partnerId: 'partner-1',
          enthusiasmScore: 70,
          gameStageLabel: 'premise',
          isReconnect: false,
        ),
      );
      final harness = _Harness(
        conversation: conversation,
        historyRepository: history,
      );
      final rerunJson = _resultJson()
        ..['enthusiasm'] = {'score': 82, 'level': 'veryHot'}
        ..['gameStage'] = {
          'current': 'qualification',
          'status': 'canAdvance',
          'nextStep': '確認彼此偏好',
        };

      await harness.coordinator.persistLatestSnapshot(
        PersistableAnalysis.fromResult(AnalysisResult.fromJson(rerunJson)),
        completionKey: 'rerun-legacy-meta',
        previousAnalyzedCount: 0,
        analyzedMessageCount: 1,
        analyzedContentRevision: revision,
        analyzedPartnerId: 'partner-1',
        analyzedIsReconnect: false,
      );
      await harness.coordinator.awaitSettled();

      expect(history.listRecent(), hasLength(2));
      final updated = history.listRecent().singleWhere(
            (event) => event.id == 'legacy-current',
          );
      expect(updated.enthusiasmScore, 82);
      expect(updated.gameStageLabel, 'qualification');
      final older = history.listRecent().singleWhere(
            (event) => event.id == 'older-event',
          );
      expect(older.enthusiasmScore, 45);
      expect(older.gameStageLabel, 'opening');
    });

    test('run 起點的 partner scope 已變更：不寫 snapshot、record 或 history', () async {
      final originalContext = SessionContext(
        meetingContext: MeetingContext.datingApp,
        duration: AcquaintanceDuration.fewDays,
      );
      final conversation = _conversation(partnerId: 'partner-b')
        ..sessionContext = originalContext;
      final harness = _Harness(conversation: conversation);
      final revision = conversationContentRevision(conversation);

      await harness.coordinator.persistLatestSnapshot(
        PersistableAnalysis.fromResult(AnalysisResult.fromJson(_resultJson())),
        completionKey: 'run-started-on-a',
        previousAnalyzedCount: 0,
        analyzedMessageCount: 1,
        analyzedContentRevision: revision,
        analyzedPartnerId: 'partner-a',
        analyzedIsReconnect: false,
        analyzedSessionContext: SessionContext(
          meetingContext: MeetingContext.committedPartner,
          duration: AcquaintanceDuration.monthPlus,
        ),
      );
      await harness.coordinator.awaitSettled();

      expect(harness.analysisCompletedSaves, isEmpty);
      expect(conversation.lastAnalysisSnapshotJson, isNull);
      expect(conversation.sessionContext, same(originalContext));
      expect(harness.history.listRecent(), isEmpty);
      expect(harness.afterPersisted, isEmpty);
    });

    test('snapshot 寫入途中才換對象：回滾分析欄位且不產生 history', () async {
      final originalContext = SessionContext(
        meetingContext: MeetingContext.datingApp,
        duration: AcquaintanceDuration.fewDays,
      );
      final analyzedContext = SessionContext(
        meetingContext: MeetingContext.committedPartner,
        duration: AcquaintanceDuration.monthPlus,
      );
      final conversation = _conversation(partnerId: 'partner-a')
        ..sessionContext = originalContext;
      final harness = _Harness(
        conversation: conversation,
        onPersistAnalysisCompleted: (conv) => conv.partnerId = 'partner-b',
      );
      final revision = conversationContentRevision(conversation);

      await harness.coordinator.persistLatestSnapshot(
        PersistableAnalysis.fromResult(AnalysisResult.fromJson(_resultJson())),
        completionKey: 'run-reassigned-during-save',
        previousAnalyzedCount: 0,
        analyzedMessageCount: 1,
        analyzedContentRevision: revision,
        analyzedPartnerId: 'partner-a',
        analyzedIsReconnect: false,
        analyzedSessionContext: analyzedContext,
      );
      await harness.coordinator.awaitSettled();

      expect(harness.analysisCompletedSaves, [revision]);
      expect(harness.contentChangedSaves, [_conversationId]);
      expect(conversation.partnerId, 'partner-b');
      expect(conversation.lastAnalysisSnapshotJson, isNull);
      expect(conversation.lastEnthusiasmScore, isNull);
      expect(conversation.sessionContext, same(originalContext));
      expect(harness.history.listRecent(), isEmpty);
      expect(harness.afterPersisted, isEmpty);
    });

    test('缺 stage：從未有有效階段時 currentGameStage 維持 null（問號）', () async {
      final recordPort = _RecordingAnalysisRecordPort();
      final harness = _Harness(
        conversation: _conversation(
          partnerId: 'partner-1',
          ownerUserId: 'u-1',
        ),
        recordPort: recordPort,
        recordOwnerUserId: 'u-1',
      );
      final revision = conversationContentRevision(harness.conversation);
      final json = _resultJson()..remove('gameStage');

      await harness.coordinator.persistLatestSnapshot(
        PersistableAnalysis.fromResult(AnalysisResult.fromJson(json)),
        completionKey: 'run-1',
        previousAnalyzedCount: 0,
        analyzedMessageCount: 1,
        analyzedContentRevision: revision,
      );
      await harness.coordinator.awaitSettled();

      expect(harness.conversation.currentGameStage, isNull);
      expect(harness.history.listRecent().single.gameStageLabel, isNull);
      expect(recordPort.savedStageLabels, ['']);
    });
  });
  group('48 小時跟進提醒（P1 安全修正）：關心與停之後不催他回去找她', () {
    Future<_Harness> persist(PersistableAnalysis analysis) async {
      final conversation = _conversation(partnerId: 'p1');
      final harness = _Harness(conversation: conversation);
      await harness.coordinator.persistLatestSnapshot(
        analysis,
        completionKey: 'run_follow_up',
        previousAnalyzedCount: 0,
        analyzedMessageCount: 1,
        analyzedContentRevision: conversationContentRevision(conversation),
      );
      expect(harness.afterPersisted.single.id, _conversationId);
      return harness;
    }

    test('v3 關心（自傷）與停：存好時協調器自己收回這位對象的提醒，畫面只被告知不問、不排', () async {
      for (final decision in ['care', 'stop']) {
        final harness = await persist(_guideV3(decision: decision));
        expect(harness.silencedPartners, ['p1'], reason: decision);
        expect(harness.silencedFollowUps, [true], reason: decision);
      }
    });

    test('v3 先別回、出卡與 v2 結果照舊：不收回', () async {
      for (final analysis in [
        _guideV3(decision: 'hold'),
        _guideV3(),
        PersistableAnalysis.fromResult(AnalysisResult.fromJson(_resultJson())),
      ]) {
        final harness = await persist(analysis);
        expect(harness.silencedPartners, isEmpty);
        expect(harness.silencedFollowUps, [false]);
      }
    });

    _Harness restoring(String decision, {String? partnerId = 'p1'}) {
      final base = _conversation();
      final snapshot = _guideV3Json(decision: decision)
        ..['__vibesync_snapshot_meta_v1'] = {
          'contentRevision': conversationContentRevision(base, messageCount: 1),
          'messageCount': 1,
        };
      return _Harness(
        conversation: _conversation(
          snapshotJson: jsonEncode(snapshot),
          analyzedCount: 1,
          partnerId: partnerId,
        ),
      );
    }

    test('冷啟動還原到關心或停：再收一次這位對象的提醒（主審第 1 輪 finding 1；重複無妨）', () async {
      for (final decision in ['care', 'stop']) {
        final harness = restoring(decision);
        expect(harness.coordinator.restore(repairRecord: false), isNotNull);
        expect(harness.coordinator.restore(repairRecord: false), isNotNull);
        await Future<void>.delayed(Duration.zero);
        expect(harness.silencedPartners, ['p1', 'p1'], reason: decision);
      }
    });

    test('還原到出卡、先別回，或沒綁對象：不叫', () async {
      for (final harness in [
        restoring('send'),
        restoring('hold'),
        restoring('care', partnerId: null),
      ]) {
        expect(harness.coordinator.restore(repairRecord: false), isNotNull);
        await Future<void>.delayed(Duration.zero);
        expect(harness.silencedPartners, isEmpty);
      }
    });
  });

  group('v3 任務卡存檔（Eric 2026-10-17：新流程沒有熱度）', () {
    test('熱度清掉、階段保留、字數基準推進、快照記 runId；紀錄與歷史事件都沒有熱度', () async {
      final conversation =
          _conversation(currentGameStage: 'premise', ownerUserId: 'owner-1')
            ..lastEnthusiasmScore = 70
            ..lastAnalyzedCharCount = 3;
      final port = _CapturingAnalysisRecordPort();
      final harness = _Harness(
        conversation: conversation,
        recordPort: port,
        recordOwnerUserId: 'owner-1',
      );

      await harness.coordinator.persistLatestSnapshot(
        _guideV3(runId: 'run_v3'),
        completionKey: 'run_v3',
        previousAnalyzedCount: 0,
        analyzedMessageCount: 1,
        analyzedContentRevision: conversationContentRevision(conversation),
      );

      expect(conversation.lastEnthusiasmScore, isNull);
      expect(conversation.currentGameStage, 'premise');
      expect(conversation.lastAnalyzedCharCount, 42);
      final snapshot = jsonDecode(conversation.lastAnalysisSnapshotJson!)
          as Map<String, dynamic>;
      expect(
        (snapshot['__vibesync_snapshot_meta_v1'] as Map)['analysisRunId'],
        'run_v3',
      );
      expect(isGuideV3Payload(snapshot), isTrue);
      final save = port.saves.single;
      expect(save.score, isNull);
      expect(save.stage, '', reason: 'v3 紀錄不沿用舊流程的階段');
      final event = harness.history.listByConversation(_conversationId).single;
      expect(event.enthusiasmScore, isNull);
      expect(event.gameStageLabel, isNull);
    });

    test(
        '帶了關係狀態（Bruce 2026-10-19 路線二）：熱度與階段照 v2 的欄位寫進對話與歷史事件；'
        '紀錄只寫階段，列表照舊顯示燈號', () async {
      final conversation =
          _conversation(currentGameStage: 'premise', ownerUserId: 'owner-1')
            ..lastEnthusiasmScore = 40;
      final port = _CapturingAnalysisRecordPort();
      final harness = _Harness(
        conversation: conversation,
        recordPort: port,
        recordOwnerUserId: 'owner-1',
      );

      await harness.coordinator.persistLatestSnapshot(
        _guideV3(runId: 'run_rel', relation: _relationJson),
        completionKey: 'run_rel',
        previousAnalyzedCount: 0,
        analyzedMessageCount: 1,
        analyzedContentRevision: conversationContentRevision(conversation),
      );

      // 原始 72 → 跟 v2 一樣換成 0–90：ceil(72 × 0.9) = 65。
      expect(conversation.lastEnthusiasmScore, 65);
      expect(conversation.currentGameStage, 'narrative');
      final event = harness.history.listByConversation(_conversationId).single;
      expect(event.enthusiasmScore, 65);
      expect(event.gameStageLabel, 'narrative');
      final save = port.saves.single;
      expect(save.score, isNull);
      expect(save.stage, '展現個人魅力');
      // 快照照伺服器的原樣存，重開畫面還原得到關係狀態。
      final snapshot = jsonDecode(conversation.lastAnalysisSnapshotJson!)
          as Map<String, dynamic>;
      expect((snapshot['read'] as Map)['relation'], _relationJson);
    });

    test('帶了關係狀態但階段讀不懂：熱度照寫，階段保留上一個有效的', () async {
      final conversation = _conversation(currentGameStage: 'premise');
      final harness = _Harness(conversation: conversation);

      await harness.coordinator.persistLatestSnapshot(
        _guideV3(relation: {..._relationJson, 'stage': 'unknown'}),
        completionKey: 'run_rel',
        previousAnalyzedCount: 0,
        analyzedMessageCount: 1,
        analyzedContentRevision: conversationContentRevision(conversation),
      );

      expect(conversation.lastEnthusiasmScore, 65);
      expect(conversation.currentGameStage, 'premise');
      final event = harness.history.listByConversation(_conversationId).single;
      expect(event.gameStageLabel, isNull);
    });

    test('restore：關係狀態跟著快照回來', () {
      final base = _conversation();
      final snapshot = _guideV3Json(relation: _relationJson)
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

      final relation = harness.coordinator
          .restore(repairRecord: false)!
          .guideV3!
          .read
          .relation!;
      expect(relation.stage, GameStage.narrative);
      expect(relation.visibleHeat, 65);
      expect(relation.herMove, GuideV3HerMove.seriousQuestion);
    });

    test('自傷關心沒扣費：字數基準不推進', () async {
      final conversation = _conversation()..lastAnalyzedCharCount = 3;
      final harness = _Harness(conversation: conversation);

      await harness.coordinator.persistLatestSnapshot(
        _guideV3(decision: 'care'),
        completionKey: 'run_care',
        previousAnalyzedCount: 0,
        analyzedMessageCount: 1,
        analyzedContentRevision: conversationContentRevision(conversation),
      );

      expect(conversation.lastAnalyzedCharCount, 3);
      expect(conversation.lastEnthusiasmScore, isNull);
    });

    test('沿用上一份快照有出處的對象檔案，新話題與對象卡的記憶不會被洗掉', () async {
      final previous = _resultJson()
        ..['targetProfile'] = {
          'provenanceVersion': 1,
          'interests': ['爬山'],
          'traits': ['慢熟'],
          'notes': <String>[],
        };
      final conversation = _conversation(snapshotJson: jsonEncode(previous));
      final harness = _Harness(conversation: conversation);

      await harness.coordinator.persistLatestSnapshot(
        _guideV3(runId: 'run_v3'),
        completionKey: 'run_v3',
        previousAnalyzedCount: 0,
        analyzedMessageCount: 1,
        analyzedContentRevision: conversationContentRevision(conversation),
      );

      final snapshot = jsonDecode(conversation.lastAnalysisSnapshotJson!)
          as Map<String, dynamic>;
      expect((snapshot['targetProfile'] as Map)['interests'], ['爬山']);
      // 續看補寫時比對用的是同一份，不會一直判成沒存過。
      final hydrated = harness.coordinator.withCarriedPartnerMemory(
        _guideV3(runId: 'run_v3'),
        previousSnapshotJson: conversation.lastAnalysisSnapshotJson,
      );
      expect(
        harness.coordinator.snapshotMatches(
          conversation: conversation,
          snapshotJson: conversation.lastAnalysisSnapshotJson,
          rawResponse: hydrated.rawResponse,
          messageCount: 1,
          analyzedContentRevision: conversationContentRevision(conversation),
        ),
        isTrue,
      );
    });

    test('v3 結果自己帶對象檔案（伺服器的對象記憶）：存的是這一份，不沿用舊的', () async {
      final previous = _resultJson()
        ..['targetProfile'] = {
          'provenanceVersion': 1,
          'interests': ['爬山'],
          'traits': ['慢熟'],
          'notes': <String>[],
        };
      final conversation = _conversation(snapshotJson: jsonEncode(previous));
      final harness = _Harness(conversation: conversation);
      final serverProfile = <String, dynamic>{
        'provenanceVersion': 1,
        'interests': ['潛水'],
        'traits': <String>[],
        'notes': ['週末通常在家'],
        'evidence': {
          'interests': [
            {
              'value': '潛水',
              'sourceMessages': ['我最近每週都去潛水'],
            },
          ],
          'traits': <Map<String, dynamic>>[],
          'notes': [
            {
              'value': '週末通常在家',
              'sourceMessages': ['我週末通常在家'],
            },
          ],
        },
      };
      final analysis = PersistableAnalysis.fromGuideV3(
        GuideV3Result.fromJson(
          _guideV3Json()..['targetProfile'] = serverProfile,
        )!,
        analysisRunId: 'run_v3',
      );
      // 有伺服器那份就不沿用（新存檔、續看補寫、紀錄修復都先過這裡）。
      expect(
        identical(
          harness.coordinator.withCarriedPartnerMemory(
            analysis,
            previousSnapshotJson: jsonEncode(previous),
          ),
          analysis,
        ),
        isTrue,
      );

      await harness.coordinator.persistLatestSnapshot(
        analysis,
        completionKey: 'run_v3',
        previousAnalyzedCount: 0,
        analyzedMessageCount: 1,
        analyzedContentRevision: conversationContentRevision(conversation),
      );

      final snapshot = jsonDecode(conversation.lastAnalysisSnapshotJson!)
          as Map<String, dynamic>;
      expect(snapshot['targetProfile'], serverProfile);
      // 續看補寫時比對用的也是伺服器那份。
      expect(
        harness.coordinator.snapshotMatches(
          conversation: conversation,
          snapshotJson: conversation.lastAnalysisSnapshotJson,
          rawResponse: harness.coordinator
              .withCarriedPartnerMemory(
                analysis,
                previousSnapshotJson: conversation.lastAnalysisSnapshotJson,
              )
              .rawResponse,
          messageCount: 1,
          analyzedContentRevision: conversationContentRevision(conversation),
        ),
        isTrue,
      );
    });

    test('沒有出處的舊對象檔案不沿用', () {
      final previous = _resultJson()
        ..['targetProfile'] = {
          'interests': ['舊標籤'],
        };
      final harness = _Harness(conversation: _conversation());
      final carried = harness.coordinator.withCarriedPartnerMemory(
        _guideV3(),
        previousSnapshotJson: jsonEncode(previous),
      );
      expect(carried.rawResponse!.containsKey('targetProfile'), isFalse);
      // v2 結果不動。
      final v2 = PersistableAnalysis.fromResult(
        AnalysisResult.fromJson(_resultJson()),
      );
      expect(
        identical(
          harness.coordinator.withCarriedPartnerMemory(
            v2,
            previousSnapshotJson: jsonEncode(previous),
          ),
          v2,
        ),
        isTrue,
      );
    });

    test('restore 認得 v3 快照：不補熱度、帶回 runId', () {
      final base = _conversation();
      final snapshot = _guideV3Json()
        ..['__vibesync_snapshot_meta_v1'] = {
          'contentRevision': conversationContentRevision(base, messageCount: 1),
          'messageCount': 1,
          'analysisRunId': 'run_v3',
        };
      final harness = _Harness(
        conversation: _conversation(
          snapshotJson: jsonEncode(snapshot),
          analyzedCount: 1,
        ),
      );

      final outcome = harness.coordinator.restore(repairRecord: false)!;
      expect(outcome.result, isNull);
      expect(outcome.guideV3!.cards.single.messages, ['那家我也想吃吃看']);
      expect(outcome.analysisRunId, 'run_v3');
    });

    test('v3 快照壞掉就不還原（不退回成五種風格）', () {
      final base = _conversation();
      final snapshot = _guideV3Json()
        ..['read'] = {'decision': 'unknown'}
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
      expect(harness.coordinator.restore(repairRecord: false), isNull);
    });
  });
}
