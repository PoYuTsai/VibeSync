// narrow run seam 回歸：AnalysisSessionController 只認 application-owned
// 的 AnalysisRunMetadata（runId／counts／revision），完整 reactive state
// 由 presentation 映射。驗證映射、staleness、live 完成持久化與 hydrate
// 補寫決策在窄 seam 上行為不變。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/application/analysis_persistence_coordinator.dart';
import 'package:vibesync/features/analysis/application/analysis_run_metadata.dart';
import 'package:vibesync/features/analysis/application/analysis_session_controller.dart';
import 'package:vibesync/features/analysis/application/analysis_run_preparer.dart';
import 'package:vibesync/features/analysis/application/ports/analysis_record_port.dart';
import 'package:vibesync/features/analysis/data/notifiers/streaming_analyze_notifier.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_models.dart';
import 'package:vibesync/features/analysis/presentation/helpers/analysis_run_metadata_mapping.dart';
import 'package:vibesync/features/analysis_history/domain/repositories/analysis_history_repository.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/features/conversation/domain/entities/session_context.dart';
import 'package:vibesync/features/conversation/domain/services/conversation_content_revision.dart';

import '../../../../helpers/memory_analysis_history_repository.dart';

const _conversationId = 'run-seam-conv';

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

Conversation _conversation({String? snapshotJson}) {
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
  );
}

class _NeverRecordPort implements AnalysisRecordPort {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('record port must not be hit');
}

class _Harness {
  _Harness({required this.conversation});

  final Conversation conversation;
  final AnalysisHistoryRepository history = MemoryAnalysisHistoryRepository();
  final analysisCompletedSaves = <String>[];
  SessionContext? startedSessionContext;
  var startCalls = 0;

  late final AnalysisPersistenceCoordinator persistence =
      AnalysisPersistenceCoordinator(
    conversationId: _conversationId,
    getConversation: (id) => id == conversation.id ? conversation : null,
    persistAnalysisCompleted: (conv, {required expectedContentRevision}) async {
      analysisCompletedSaves.add(expectedContentRevision);
    },
    persistContentChanged: (_) async {},
    markConversationActive: (_) async {},
    archiveMarkerFor: (_) => null,
    recordPort: _NeverRecordPort(),
    currentRecordOwnerUserId: () => null,
    historyRepository: () => history,
    trackFunnelOnce: (_) async {},
    lastPayloadCharCount: () => null,
    notifyStateChanged: () {},
    invalidateRecordViews: (_) {},
    afterAnalysisPersisted: (_) async {},
  );

  late final AnalysisSessionController session = AnalysisSessionController(
    conversationId: _conversationId,
    startRun: ({
      required messages,
      sessionContext,
      conversationSummary,
      partnerSummary,
      effectiveStyleContext,
      knownContactName,
      previousStage,
      analysisFragmentStartIndex,
      previousAnalyzedCount,
      previousAnalyzedCharCount,
      confirmedOvercharge,
      conversationMessageCount,
      analyzedMessageCount,
      conversationContentRevision,
    }) async {
      startCalls++;
      startedSessionContext = sessionContext;
    },
    retryRun: () => throw UnimplementedError('not used here'),
    ensureServerEntitlementSynced: () async {},
    currentConversation: () => conversation,
    persistence: persistence,
  );
}

void main() {
  test('start：把實際送出的 context 凍結到 Conversation，供同片段重跑沿用', () async {
    final conversation = _conversation()
      ..sessionContext = SessionContext(
        meetingContext: MeetingContext.datingApp,
        duration: AcquaintanceDuration.justMet,
      );
    final sentContext = SessionContext(
      meetingContext: MeetingContext.committedPartner,
      duration: AcquaintanceDuration.monthPlus,
      goal: UserGoal.maintainHeat,
    );
    final harness = _Harness(conversation: conversation);
    final preparation = AnalysisRunPreparation(
      requestMessages: conversation.messages,
      conversationSummary: null,
      partnerSummary: null,
      effectiveStyleContext: null,
      knownContactName: null,
      sessionContext: sentContext,
      previousStage: null,
      analysisFragmentStartIndex: 0,
      analyzedMessageCount: 1,
      contentRevision: conversationContentRevision(conversation),
    );

    await harness.session.start(
      conversation: conversation,
      preparation: preparation,
      waitForCompletion: true,
      shouldProceed: () => true,
    );

    expect(harness.startCalls, 1);
    expect(harness.startedSessionContext, same(sentContext));
    expect(conversation.sessionContext, same(sentContext));
  });

  test('start：畫面已失效時不送出，也不改寫 Conversation context', () async {
    final originalContext = SessionContext(
      meetingContext: MeetingContext.datingApp,
      duration: AcquaintanceDuration.justMet,
    );
    final conversation = _conversation()..sessionContext = originalContext;
    final harness = _Harness(conversation: conversation);
    final preparation = AnalysisRunPreparation(
      requestMessages: conversation.messages,
      conversationSummary: null,
      partnerSummary: null,
      effectiveStyleContext: null,
      knownContactName: null,
      sessionContext: SessionContext(
        meetingContext: MeetingContext.committedPartner,
        duration: AcquaintanceDuration.monthPlus,
      ),
      previousStage: null,
      analysisFragmentStartIndex: 0,
      analyzedMessageCount: 1,
      contentRevision: conversationContentRevision(conversation),
    );

    await harness.session.start(
      conversation: conversation,
      preparation: preparation,
      waitForCompletion: true,
      shouldProceed: () => false,
    );

    expect(harness.startCalls, 0);
    expect(conversation.sessionContext, same(originalContext));
  });

  test('presentation 映射：reactive state → 最小 run metadata（只帶四個欄位）', () {
    const state = StreamingAnalysisState(
      phase: StreamingAnalyzePhase.done,
      analysisRunId: 'run-77',
      previousAnalyzedCount: 3,
      conversationMessageCount: 9,
      conversationContentRevision: 'rev-abc',
      streamErrorMessage: '這些 UI 欄位不得進 application',
      retriesRemaining: 2,
    );

    final run = state.toRunMetadata();
    expect(run.runId, 'run-77');
    expect(run.previousAnalyzedCount, 3);
    expect(run.conversationMessageCount, 9);
    expect(run.contentRevision, 'rev-abc');
  });

  group('staleness（narrow seam）', () {
    test('contentRevision 相符不 stale、不符 stale', () {
      final harness = _Harness(conversation: _conversation());
      final revision = conversationContentRevision(harness.conversation);

      expect(
        harness.session.isResultStaleForCurrentConversation(
          AnalysisRunMetadata(contentRevision: revision),
        ),
        isFalse,
      );
      expect(
        harness.session.isResultStaleForCurrentConversation(
          const AnalysisRunMetadata(contentRevision: 'edited-away'),
        ),
        isTrue,
      );
    });

    test('舊 run 無修訂時退回訊息數比對', () {
      final harness = _Harness(conversation: _conversation());

      expect(
        harness.session.isResultStaleForCurrentConversation(
          const AnalysisRunMetadata(conversationMessageCount: 1),
        ),
        isFalse,
      );
      expect(
        harness.session.isResultStaleForCurrentConversation(
          const AnalysisRunMetadata(conversationMessageCount: 3),
        ),
        isTrue,
      );
    });
  });

  test('persistCompletedRun：以 metadata 的 revision 排程 canonical 持久化', () async {
    final harness = _Harness(conversation: _conversation());
    final revision = conversationContentRevision(harness.conversation);

    harness.session.persistCompletedRun(
      AnalysisRunMetadata(
        runId: 'run-1',
        previousAnalyzedCount: 0,
        contentRevision: revision,
      ),
      AnalysisResult.fromJson(_resultJson()),
      analyzedMessageCount: 1,
      allowArchivedRecordRefresh: false,
    );
    await harness.persistence.awaitSettled();

    expect(harness.analysisCompletedSaves, [revision]);
  });

  group('persistHydratedResultIfNeeded（narrow seam）', () {
    test('尚未持久化：排程持久化並回 true', () async {
      final harness = _Harness(conversation: _conversation());
      final revision = conversationContentRevision(harness.conversation);

      final persisted = harness.session.persistHydratedResultIfNeeded(
        AnalysisRunMetadata(runId: 'run-1', contentRevision: revision),
        AnalysisResult.fromJson(_resultJson()),
        expectedAnalyzedCount: 1,
        conversation: harness.conversation,
      );
      await harness.persistence.awaitSettled();

      expect(persisted, isTrue);
      expect(harness.analysisCompletedSaves, [revision]);
    });

    test('listener 已寫過同一份 snapshot：dedup 命中，只補紀錄修復並回 false', () async {
      final base = _conversation();
      final revision = conversationContentRevision(base, messageCount: 1);
      final snapshot = _resultJson()
        ..['__vibesync_snapshot_meta_v1'] = {
          'contentRevision': revision,
          'messageCount': 1,
        };
      final harness = _Harness(
        conversation: _conversation(snapshotJson: jsonEncode(snapshot)),
      );

      final persisted = harness.session.persistHydratedResultIfNeeded(
        AnalysisRunMetadata(runId: 'run-1', contentRevision: revision),
        AnalysisResult.fromJson(_resultJson()),
        expectedAnalyzedCount: 1,
        conversation: harness.conversation,
      );
      await harness.persistence.awaitSettled();

      expect(persisted, isFalse);
      expect(harness.analysisCompletedSaves, isEmpty);
      // 修復已排程；owner 缺席 → 標記待修復（不碰 record port）。
      expect(harness.persistence.recordNeedsRepair, isTrue);
    });
  });
}
