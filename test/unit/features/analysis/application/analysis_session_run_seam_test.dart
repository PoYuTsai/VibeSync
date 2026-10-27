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
import 'package:vibesync/features/analysis/domain/entities/persistable_analysis.dart';
import 'package:vibesync/features/analysis/domain/entities/previous_round_context.dart';
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

Conversation _conversation({String? snapshotJson, String? partnerId}) {
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
    partnerId: partnerId,
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
  String? startedPartnerId;
  bool? startedReconnectContext;
  PreviousRoundContext? startedPreviousRound;
  List<Message>? startedMessages;
  int? startedFragmentStart;
  int? startedPreviousAnalyzedCount;
  int? startedPreviousAnalyzedCharCount;
  int? startedNextCharBaseline;
  int? startedAnalyzedMessageCount;
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
    afterAnalysisPersisted: (_, {required silenceFollowUp}) async {},
    silenceFollowUp: (_) async {},
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
      nextCharBaseline,
      confirmedOvercharge,
      conversationMessageCount,
      analyzedMessageCount,
      conversationContentRevision,
      conversationPartnerId,
      isReconnectContext,
      previousRound,
    }) async {
      startCalls++;
      startedMessages = messages;
      startedFragmentStart = analysisFragmentStartIndex;
      startedPreviousAnalyzedCount = previousAnalyzedCount;
      startedPreviousAnalyzedCharCount = previousAnalyzedCharCount;
      startedNextCharBaseline = nextCharBaseline;
      startedAnalyzedMessageCount = analyzedMessageCount;
      startedPreviousRound = previousRound;
      startedSessionContext = sessionContext;
      startedPartnerId = conversationPartnerId;
      startedReconnectContext = isReconnectContext;
    },
    retryRun: () => throw UnimplementedError('not used here'),
    ensureServerEntitlementSynced: () async {},
    currentConversation: () => conversation,
    persistence: persistence,
  );
}

void main() {
  test('start：送出 context 但成功前不污染 Conversation', () async {
    final originalContext = SessionContext(
      meetingContext: MeetingContext.datingApp,
      duration: AcquaintanceDuration.justMet,
    );
    final conversation = _conversation()..sessionContext = originalContext;
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
      conversationPartnerId: null,
      isReconnectContext: true,
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
    expect(harness.startedPartnerId, isNull);
    expect(harness.startedReconnectContext, isTrue);
    expect(conversation.sessionContext, same(originalContext));
  });

  test('start：上一輪脈絡原樣交給串流 run（Eric 2026-10-18）', () async {
    final conversation = _conversation(partnerId: 'partner-a');
    final harness = _Harness(conversation: conversation);
    const previousRound = PreviousRoundContext(
      decision: 'send',
      light: 'green',
      judgment: '她在反問你',
      messages: [PreviousRoundMessage(isFromMe: false, content: '你呢')],
    );
    final preparation = AnalysisRunPreparation(
      requestMessages: conversation.messages,
      conversationSummary: null,
      partnerSummary: null,
      effectiveStyleContext: null,
      knownContactName: null,
      sessionContext: null,
      conversationPartnerId: 'partner-a',
      isReconnectContext: false,
      previousStage: null,
      analysisFragmentStartIndex: 0,
      analyzedMessageCount: 1,
      contentRevision: conversationContentRevision(conversation),
      previousRound: previousRound,
    );

    await harness.session.start(
      conversation: conversation,
      preparation: preparation,
      waitForCompletion: true,
      shouldProceed: () => true,
    );

    expect(harness.startCalls, 1);
    expect(harness.startedPreviousRound, same(previousRound));
  });

  // Onboarding 第 15 步：只分析最後 2,000 字送的是尾段，兩個基準是對整段算的，都不帶；
  // 成功後的字數基準照整段存。
  group('只分析最後 2,000 字：送尾段時的基準（Onboarding 第 15 步）', () {
    /// 上次分析到第 1 則（字數基準 5），之後又來了兩則。
    Conversation analyzedBefore() => Conversation(
          id: _conversationId,
          name: '小雲',
          messages: [
            for (var i = 1; i <= 3; i++)
              Message(
                id: 'm$i',
                content: '第 $i 則',
                isFromMe: false,
                timestamp: DateTime(2026, 10, 27, 12, i),
              ),
          ],
          createdAt: DateTime(2026, 10, 27),
          updatedAt: DateTime(2026, 10, 27),
          lastAnalyzedMessageCount: 1,
          lastAnalyzedCharCount: 5,
        );

    AnalysisRunPreparation preparationOf(
      Conversation conversation, {
      required List<Message> requestMessages,
      int? fullRequestCharBaseline,
    }) =>
        AnalysisRunPreparation(
          requestMessages: requestMessages,
          conversationSummary: null,
          partnerSummary: null,
          effectiveStyleContext: null,
          knownContactName: null,
          sessionContext: null,
          conversationPartnerId: null,
          isReconnectContext: false,
          analysisFragmentStartIndex: 0,
          analyzedMessageCount: conversation.messages.length,
          contentRevision: conversationContentRevision(conversation),
          fullRequestCharBaseline: fullRequestCharBaseline,
        );

    test('一般分析：照舊帶上次的則數與字數基準，成功後的基準照送出的算', () async {
      final conversation = analyzedBefore();
      final harness = _Harness(conversation: conversation);

      await harness.session.start(
        conversation: conversation,
        preparation: preparationOf(
          conversation,
          requestMessages: conversation.messages,
        ),
        waitForCompletion: true,
        shouldProceed: () => true,
      );

      expect(harness.startCalls, 1);
      expect(harness.startedPreviousAnalyzedCount, 1);
      expect(harness.startedPreviousAnalyzedCharCount, 5);
      expect(harness.startedNextCharBaseline, isNull);
    });

    test('只送尾段：兩個基準都不帶（伺服器把尾段整段當新內容算），成功後的字數基準照整段存', () async {
      final conversation = analyzedBefore();
      final harness = _Harness(conversation: conversation);
      final tail = conversation.messages.sublist(1);

      await harness.session.start(
        conversation: conversation,
        preparation: preparationOf(
          conversation,
          requestMessages: tail,
          fullRequestCharBaseline: 15,
        ),
        waitForCompletion: true,
        shouldProceed: () => true,
      );

      expect(harness.startCalls, 1);
      expect(harness.startedMessages, tail);
      expect(harness.startedFragmentStart, 0);
      expect(harness.startedPreviousAnalyzedCount, isNull);
      expect(harness.startedPreviousAnalyzedCharCount, isNull);
      expect(harness.startedNextCharBaseline, 15);
      // 訊息數基準照實際送出範圍的結尾（整段最後一則）。
      expect(harness.startedAnalyzedMessageCount, 3);
    });
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
      conversationPartnerId: null,
      isReconnectContext: true,
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

  test('start：等待權益期間若對話已換對象，不送出舊對象脈絡', () async {
    final conversation = _conversation(partnerId: 'partner-b');
    final harness = _Harness(conversation: conversation);
    final preparation = AnalysisRunPreparation(
      requestMessages: conversation.messages,
      conversationSummary: null,
      partnerSummary: 'partner-a context',
      effectiveStyleContext: null,
      knownContactName: null,
      sessionContext: null,
      conversationPartnerId: 'partner-a',
      isReconnectContext: false,
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

    expect(harness.startCalls, 0);
  });

  test('presentation 映射：reactive state → 最小 run metadata', () {
    final sentContext = SessionContext(
      meetingContext: MeetingContext.committedPartner,
      duration: AcquaintanceDuration.monthPlus,
    );
    final state = StreamingAnalysisState(
      phase: StreamingAnalyzePhase.done,
      analysisRunId: 'run-77',
      previousAnalyzedCount: 3,
      conversationMessageCount: 9,
      conversationContentRevision: 'rev-abc',
      conversationPartnerId: 'partner-1',
      isReconnectContext: true,
      analyzedSessionContext: sentContext,
      streamErrorMessage: '這些 UI 欄位不得進 application',
      retriesRemaining: 2,
    );

    final run = state.toRunMetadata();
    expect(run.runId, 'run-77');
    expect(run.previousAnalyzedCount, 3);
    expect(run.conversationMessageCount, 9);
    expect(run.contentRevision, 'rev-abc');
    expect(run.conversationPartnerId, 'partner-1');
    expect(run.isReconnectContext, isTrue);
    expect(run.analyzedSessionContext, same(sentContext));
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

    test('分析中途 Conversation 重新分配到另一對象 → stale', () {
      final conversation = _conversation(partnerId: 'partner-a');
      final harness = _Harness(conversation: conversation);
      final revision = conversationContentRevision(conversation);
      final run = AnalysisRunMetadata(
        contentRevision: revision,
        conversationPartnerId: 'partner-a',
        isReconnectContext: false,
      );

      expect(harness.session.isResultStaleForCurrentConversation(run), isFalse);
      conversation.partnerId = 'partner-b';
      expect(harness.session.isResultStaleForCurrentConversation(run), isTrue);
    });
  });

  test('persistCompletedRun：以 metadata 的 revision 排程 canonical 持久化', () async {
    final originalContext = SessionContext(
      meetingContext: MeetingContext.inPerson,
      duration: AcquaintanceDuration.justMet,
    );
    final harness = _Harness(
      conversation: _conversation()..sessionContext = originalContext,
    );
    final revision = conversationContentRevision(harness.conversation);
    final sentContext = SessionContext(
      meetingContext: MeetingContext.datingApp,
      duration: AcquaintanceDuration.fewWeeks,
    );

    harness.session.persistCompletedRun(
      AnalysisRunMetadata(
        runId: 'run-1',
        previousAnalyzedCount: 0,
        contentRevision: revision,
        isReconnectContext: false,
        analyzedSessionContext: sentContext,
      ),
      PersistableAnalysis.fromResult(AnalysisResult.fromJson(_resultJson())),
      analyzedMessageCount: 1,
      allowArchivedRecordRefresh: false,
    );
    await harness.persistence.awaitSettled();

    expect(harness.analysisCompletedSaves, [revision]);
    expect(harness.conversation.sessionContext, same(originalContext));
    final snapshot = jsonDecode(
      harness.conversation.lastAnalysisSnapshotJson!,
    ) as Map<String, dynamic>;
    final meta =
        snapshot['__vibesync_snapshot_meta_v1'] as Map<String, dynamic>;
    final frozen = meta['sessionContext'] as Map<String, dynamic>;
    expect(frozen['meetingContext'], 'datingApp');
    expect(frozen['duration'], 'fewWeeks');
  });

  group('persistHydratedResultIfNeeded（narrow seam）', () {
    test('尚未持久化：排程持久化並回 true', () async {
      final harness = _Harness(conversation: _conversation());
      final revision = conversationContentRevision(harness.conversation);

      final persisted = harness.session.persistHydratedResultIfNeeded(
        AnalysisRunMetadata(runId: 'run-1', contentRevision: revision),
        PersistableAnalysis.fromResult(AnalysisResult.fromJson(_resultJson())),
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
        PersistableAnalysis.fromResult(AnalysisResult.fromJson(_resultJson())),
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
