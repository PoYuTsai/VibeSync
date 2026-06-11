import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/data/notifiers/streaming_analyze_notifier.dart';
import 'package:vibesync/features/analysis/data/providers/analysis_providers.dart';
import 'package:vibesync/features/analysis/data/services/analysis_service.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_models.dart';
import 'package:vibesync/features/analysis/domain/entities/game_stage.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_recommendation_preview.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/features/conversation/domain/entities/session_context.dart';

Message _msg(String content, {bool fromMe = false}) {
  return Message(
    id: content,
    content: content,
    isFromMe: fromMe,
    timestamp: DateTime(2026, 5, 28, 12, 0, 0),
  );
}

AnalysisRecommendationPreview _preview(
    {String runId = 'run_q1', int? eta = 17}) {
  return AnalysisRecommendationPreview(
    analysisRunId: runId,
    pick: 'resonate',
    nextStep: '先接情緒',
    recommendedReply: '聽起來累，週末放空？',
    shortReason: '接情緒延伸',
    insufficientContext: false,
    confidence: 'high',
    estimatedFullSeconds: eta,
  );
}

AnalysisResult _full() {
  return const AnalysisResult(
    enthusiasmScore: 70,
    strategy: '保持沉穩',
    gameStage: GameStageInfo(
      current: GameStage.premise,
      status: GameStageStatus.normal,
      nextStep: '繼續',
    ),
    psychology: PsychologyAnalysis(
      subtext: '有興趣',
      qualificationSignal: true,
    ),
    topicDepth: TopicDepth(
      current: TopicDepthLevel.personal,
      suggestion: '可深入',
    ),
    replies: {
      'extend': 'a',
      'resonate': 'b',
      'tease': 'c',
      'humor': 'd',
      'coldRead': 'e',
    },
    replyOptions: {},
    recommendation: FinalRecommendation(
      pick: 'tease',
      content: 'c',
      reason: 'r',
      psychology: 'p',
    ),
    reminder: '記得用你的方式說',
  );
}

class _FakeAnalysisService extends AnalysisService {
  _FakeAnalysisService();

  AnalysisRecommendationPreview? recommendationPreviewResult;
  Exception? recommendationPreviewError;
  AnalysisResult? fullResult;
  Exception? fullError;
  Exception? streamError;
  Completer<void>? streamStartGate;
  Completer<void>? fullGate;
  List<AnalysisStreamContent> streamContents = const [];

  int streamCallCount = 0;
  int recommendationPreviewCallCount = 0;
  int fullCallCount = 0;
  String? lastStreamRunId;
  String? lastFullRunId;
  List<Message>? capturedStreamMessages;
  List<Message>? capturedFullMessages;

  @override
  Future<AnalysisRecommendationPreview> analyzeQuick({
    required List<Message> messages,
    SessionContext? sessionContext,
    String? conversationSummary,
    String? partnerSummary,
    String? effectiveStyleContext,
    String? knownContactName,
    int? previousAnalyzedCount,
    int? previousAnalyzedCharCount,
    OverchargeConfirmationPayload? confirmedOvercharge,
  }) async {
    recommendationPreviewCallCount++;
    if (recommendationPreviewError != null) throw recommendationPreviewError!;
    return recommendationPreviewResult!;
  }

  @override
  Future<AnalysisResult> analyzeFull({
    required String analysisRunId,
    required List<Message> messages,
    SessionContext? sessionContext,
    String? conversationSummary,
    String? partnerSummary,
    String? effectiveStyleContext,
    String? knownContactName,
    int? previousAnalyzedCount,
    int? previousAnalyzedCharCount,
  }) async {
    fullCallCount++;
    lastFullRunId = analysisRunId;
    capturedFullMessages = List<Message>.from(messages);
    if (fullGate != null) await fullGate!.future;
    if (fullError != null) throw fullError!;
    return fullResult!;
  }

  @override
  Stream<AnalysisStreamUpdate> analyzeStream({
    String? analysisRunId,
    required List<Message> messages,
    SessionContext? sessionContext,
    String? conversationSummary,
    String? partnerSummary,
    String? effectiveStyleContext,
    String? knownContactName,
    int? previousAnalyzedCount,
    int? previousAnalyzedCharCount,
    OverchargeConfirmationPayload? confirmedOvercharge,
  }) async* {
    streamCallCount++;
    lastStreamRunId = analysisRunId;
    capturedStreamMessages = List<Message>.from(messages);
    if (streamStartGate != null) await streamStartGate!.future;
    yield const AnalysisStreamUpdate.started(
      runId: 'stream-run',
      label: 'starting stream',
    );
    for (final content in streamContents) {
      yield AnalysisStreamUpdate.content(
        content: content,
        runId: 'stream-run',
        label: content.title,
        detail: content.body,
      );
    }
    if (recommendationPreviewError != null) throw recommendationPreviewError!;
    if (recommendationPreviewResult != null) {
      yield AnalysisStreamUpdate.recommendation(
        recommendationPreview: recommendationPreviewResult!,
        runId: recommendationPreviewResult!.analysisRunId,
      );
    }
    if (fullGate != null) await fullGate!.future;
    if (streamError != null) throw streamError!;
    if (fullError != null) throw fullError!;
    if (fullResult != null) {
      yield AnalysisStreamUpdate.done(
        result: fullResult!,
        runId: recommendationPreviewResult?.analysisRunId ?? 'stream-run',
      );
    }
  }
}

ProviderContainer _container(AnalysisService fake) {
  return ProviderContainer(overrides: [
    analysisServiceProvider.overrideWithValue(fake),
  ]);
}

void main() {
  group('StreamingAnalyzeNotifier — happy path', () {
    test('build returns idle state', () {
      final fake = _FakeAnalysisService();
      final container = _container(fake);
      addTearDown(container.dispose);

      final state = container.read(streamingAnalyzeProvider('conv-1'));
      expect(state.phase, StreamingAnalyzePhase.idle);
      expect(state.recommendationPreview, isNull);
      expect(state.full, isNull);
    });

    test('start streams full analysis without calling legacy quick API',
        () async {
      final fake = _FakeAnalysisService()
        ..recommendationPreviewResult = _preview(runId: 'run_happy')
        ..fullResult = _full()
        ..fullGate = Completer<void>();

      final container = _container(fake);
      addTearDown(container.dispose);

      final phases = <StreamingAnalyzePhase>[];
      container.listen(streamingAnalyzeProvider('conv-1'), (prev, next) {
        phases.add(next.phase);
      });

      final notifier =
          container.read(streamingAnalyzeProvider('conv-1').notifier);

      final startFuture = notifier.start(
        messages: [_msg('hi')],
        conversationMessageCount: 3,
      );

      // Allow recommendation preview to resolve and the streamingReport transition to land.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final afterQuick = container.read(streamingAnalyzeProvider('conv-1'));
      expect(afterQuick.phase, StreamingAnalyzePhase.streamingReport);
      expect(afterQuick.recommendationPreview?.analysisRunId, 'run_happy');
      expect(afterQuick.analysisRunId, 'run_happy');
      expect(afterQuick.conversationMessageCount, 3);

      fake.fullGate!.complete();
      await startFuture;

      final afterFull = container.read(streamingAnalyzeProvider('conv-1'));
      expect(afterFull.phase, StreamingAnalyzePhase.done);
      expect(afterFull.conversationMessageCount, 3);
      expect(afterFull.full?.strategy, '保持沉穩');

      expect(
        phases,
        containsAllInOrder([
          StreamingAnalyzePhase.connecting,
          StreamingAnalyzePhase.streamingReport,
          StreamingAnalyzePhase.done,
        ]),
      );

      expect(fake.streamCallCount, 1);
      expect(fake.recommendationPreviewCallCount, 0);
      expect(fake.fullCallCount, 0);
      expect(fake.capturedStreamMessages?.map((m) => m.content).toList(), [
        'hi',
      ]);
    });
  });

  group('StreamingAnalyzeNotifier — failure paths', () {
    test(
        'pre-recommendation failure: connecting → failedBeforeRecommendation, no full call',
        () async {
      final fake = _FakeAnalysisService()
        ..recommendationPreviewError = AnalysisException(
          '網路忙線',
          code: 'NETWORK_ERROR',
        );

      final container = _container(fake);
      addTearDown(container.dispose);

      final notifier =
          container.read(streamingAnalyzeProvider('conv-1').notifier);

      await notifier.start(messages: [_msg('hi')]);

      final state = container.read(streamingAnalyzeProvider('conv-1'));
      expect(state.phase, StreamingAnalyzePhase.failedBeforeRecommendation);
      expect(state.recommendationPreview, isNull);
      expect(state.recommendationPreviewErrorMessage, '網路忙線');
      expect(state.recommendationPreviewErrorCode, 'NETWORK_ERROR');
      expect(fake.fullCallCount, 0);
    });

    test('quota exhaustion failure uses localized streaming error copy',
        () async {
      final fake = _FakeAnalysisService()
        ..streamError = DailyLimitExceededException(
          dailyLimit: 15,
          used: 15,
        );

      final container = _container(fake);
      addTearDown(container.dispose);

      final notifier =
          container.read(streamingAnalyzeProvider('conv-1').notifier);

      await notifier.start(messages: [_msg('hi')]);

      final state = container.read(streamingAnalyzeProvider('conv-1'));
      expect(state.phase, StreamingAnalyzePhase.failedBeforeRecommendation);
      expect(
        state.recommendationPreviewErrorMessage,
        contains('今日額度已用完'),
      );
      expect(
        state.recommendationPreviewErrorMessage,
        isNot(contains('Daily limit exceeded')),
      );
      expect(state.recommendationPreviewErrorCode, 'DAILY_LIMIT_EXCEEDED');
    });

    test(
        'full failure preserves recommendation preview and emits failedAfterRecommendation with retries',
        () async {
      final fake = _FakeAnalysisService()
        ..recommendationPreviewResult = _preview(runId: 'run_keep')
        ..streamError = StreamModeException(
          '完整分析失敗，可以重試。',
          code: 'STREAM_INTERRUPTED_AFTER_RECOMMENDATION',
          recoverable: true,
          retriesRemaining: 2,
          suggestedAction: AnalysisErrorAction.retry,
        );

      final container = _container(fake);
      addTearDown(container.dispose);

      final notifier =
          container.read(streamingAnalyzeProvider('conv-1').notifier);

      await notifier.start(messages: [_msg('hi')]);

      final state = container.read(streamingAnalyzeProvider('conv-1'));
      expect(state.phase, StreamingAnalyzePhase.failedAfterRecommendation);
      expect(state.recommendationPreview?.analysisRunId,
          'run_keep'); // recommendation preview preserved
      expect(state.analysisRunId, 'run_keep');
      expect(state.retriesRemaining, 2);
      expect(state.fullErrorCode, 'STREAM_INTERRUPTED_AFTER_RECOMMENDATION');
      expect(fake.streamCallCount, 1);
      expect(fake.recommendationPreviewCallCount, 0);
      expect(fake.fullCallCount, 0);
    });

    test('retryFull reuses analysisRunId; does not call analyzeQuick',
        () async {
      final fake = _FakeAnalysisService()
        ..recommendationPreviewResult = _preview(runId: 'run_retry')
        ..streamError = StreamModeException(
          'transient',
          code: 'STREAM_INTERRUPTED_AFTER_RECOMMENDATION',
          recoverable: true,
          retriesRemaining: 2,
          suggestedAction: AnalysisErrorAction.retry,
        );

      final container = _container(fake);
      addTearDown(container.dispose);

      final notifier =
          container.read(streamingAnalyzeProvider('conv-1').notifier);

      await notifier.start(messages: [_msg('hi')]);
      expect(fake.streamCallCount, 1);
      expect(fake.recommendationPreviewCallCount, 0);
      expect(fake.fullCallCount, 0);

      // Now retry succeeds.
      fake.streamError = null;
      fake.fullResult = _full();

      await notifier.retryFull();

      expect(fake.recommendationPreviewCallCount, 0); // unchanged
      expect(fake.streamCallCount, 2);
      expect(fake.fullCallCount, 0);
      expect(fake.lastStreamRunId, 'run_retry');

      final state = container.read(streamingAnalyzeProvider('conv-1'));
      expect(state.phase, StreamingAnalyzePhase.done);
    });

    test('retryFull after unrecoverable stream error keeps retriesRemaining=0',
        () async {
      final fake = _FakeAnalysisService()
        ..recommendationPreviewResult = _preview()
        ..streamError = StreamModeException(
          '完整分析已達重試上限，請重新分析。',
          code: 'STREAM_RUN_RETRY_UNAVAILABLE',
          recoverable: false,
          retriesRemaining: 0,
          suggestedAction: AnalysisErrorAction.wait,
        );

      final container = _container(fake);
      addTearDown(container.dispose);

      final notifier =
          container.read(streamingAnalyzeProvider('conv-1').notifier);

      await notifier.start(messages: [_msg('hi')]);
      await notifier.retryFull();

      final state = container.read(streamingAnalyzeProvider('conv-1'));
      expect(state.phase, StreamingAnalyzePhase.failedAfterRecommendation);
      expect(state.retriesRemaining, 0);
      expect(state.fullErrorCode, 'STREAM_RUN_RETRY_UNAVAILABLE');
    });
  });

  group('StreamingAnalysisState.copyWith — clearing semantics (P2)', () {
    test('can explicitly clear nullable fields via null', () {
      const state = StreamingAnalysisState(
        phase: StreamingAnalyzePhase.failedAfterRecommendation,
        fullErrorMessage: '舊錯誤',
        fullErrorCode: 'OLD_CODE',
        retriesRemaining: 3,
      );

      final cleared = state.copyWith(
        phase: StreamingAnalyzePhase.streamingReport,
        fullErrorMessage: null,
        fullErrorCode: null,
        retriesRemaining: 0,
      );

      expect(cleared.phase, StreamingAnalyzePhase.streamingReport);
      expect(cleared.fullErrorMessage, isNull);
      expect(cleared.fullErrorCode, isNull);
      expect(cleared.retriesRemaining, 0);
    });

    test('preserves existing values when params are omitted', () {
      const state = StreamingAnalysisState(
        phase: StreamingAnalyzePhase.failedAfterRecommendation,
        fullErrorMessage: 'keep me',
        fullErrorCode: 'KEEP',
        retriesRemaining: 2,
      );

      final preserved =
          state.copyWith(phase: StreamingAnalyzePhase.streamingReport);

      expect(preserved.phase, StreamingAnalyzePhase.streamingReport);
      expect(preserved.fullErrorMessage, 'keep me');
      expect(preserved.fullErrorCode, 'KEEP');
      expect(preserved.retriesRemaining, 2);
    });
  });

  group('StreamingAnalyzeNotifier — retry clears stale error (P2)', () {
    test('retryFull clears fullErrorMessage/code during streamingReport',
        () async {
      final fake = _FakeAnalysisService()
        ..recommendationPreviewResult = _preview(runId: 'run_clear')
        ..streamError = StreamModeException(
          'stale failure',
          code: 'STREAM_INTERRUPTED_AFTER_RECOMMENDATION',
          recoverable: true,
          retriesRemaining: 2,
          suggestedAction: AnalysisErrorAction.retry,
        );

      final container = _container(fake);
      addTearDown(container.dispose);

      final notifier =
          container.read(streamingAnalyzeProvider('conv-1').notifier);

      await notifier.start(messages: [_msg('hi')]);
      final failed = container.read(streamingAnalyzeProvider('conv-1'));
      expect(failed.phase, StreamingAnalyzePhase.failedAfterRecommendation);
      expect(failed.fullErrorMessage, 'stale failure');

      // Gate the retry full call so we can observe streamingReport state in flight.
      fake.streamError = null;
      fake.fullResult = _full();
      fake.fullGate = Completer<void>();

      final retryFuture = notifier.retryFull();

      // Let retryFull push the streamingReport transition.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final midFlight = container.read(streamingAnalyzeProvider('conv-1'));
      expect(midFlight.phase, StreamingAnalyzePhase.streamingReport);
      expect(midFlight.fullErrorMessage, isNull,
          reason: 'I-P2-b: streamingReport must not carry stale error');
      expect(midFlight.fullErrorCode, isNull);
      expect(midFlight.retriesRemaining, 0);

      fake.fullGate!.complete();
      await retryFuture;

      final done = container.read(streamingAnalyzeProvider('conv-1'));
      expect(done.phase, StreamingAnalyzePhase.done);
      expect(done.fullErrorMessage, isNull,
          reason: 'I-P2-c: done must not carry stale error');
      expect(done.fullErrorCode, isNull);
    });

    test('retryFull clears preserved stream content before replay', () async {
      final fake = _FakeAnalysisService()
        ..streamError = StreamModeException(
          'stream reset',
          code: 'STREAM_INTERRUPTED_AFTER_CONTENT',
          recoverable: true,
          retriesRemaining: 1,
          suggestedAction: AnalysisErrorAction.retry,
        )
        ..streamContents = const [
          AnalysisStreamContent(
            kind: AnalysisStreamContentKind.decision,
            title: 'Decision',
            body: 'A useful partial decision.',
            rawEvent: {'type': 'analysis.decision'},
          ),
        ];

      final container = _container(fake);
      addTearDown(container.dispose);

      final notifier =
          container.read(streamingAnalyzeProvider('conv-1').notifier);

      await notifier.start(messages: [_msg('hi')]);

      final failed = container.read(streamingAnalyzeProvider('conv-1'));
      expect(failed.phase, StreamingAnalyzePhase.failedAfterRecommendation);
      expect(failed.streamContents, hasLength(1));

      fake.streamError = null;
      fake.fullResult = _full();
      fake.streamStartGate = Completer<void>();

      final retryFuture = notifier.retryFull();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final running = container.read(streamingAnalyzeProvider('conv-1'));
      expect(running.phase, StreamingAnalyzePhase.streamingReport);
      expect(running.streamContents, isEmpty);

      fake.streamStartGate!.complete();
      await retryFuture;
    });
  });

  group('StreamingAnalyzeNotifier — retry args caching (P1)', () {
    test('retryFull() with no args reuses messages cached from start()',
        () async {
      final fake = _FakeAnalysisService()
        ..recommendationPreviewResult = _preview(runId: 'run_cached')
        ..streamError = StreamModeException(
          'transient',
          code: 'STREAM_INTERRUPTED_AFTER_RECOMMENDATION',
          recoverable: true,
          retriesRemaining: 2,
          suggestedAction: AnalysisErrorAction.retry,
        );

      final container = _container(fake);
      addTearDown(container.dispose);

      final notifier =
          container.read(streamingAnalyzeProvider('conv-1').notifier);

      final original = [_msg('original-1'), _msg('original-2')];
      await notifier.start(messages: original);
      expect(fake.streamCallCount, 1);
      expect(fake.recommendationPreviewCallCount, 0);
      expect(fake.fullCallCount, 0);

      // Reconfigure for retry success and capture the messages the service sees.
      fake.streamError = null;
      fake.fullResult = _full();
      fake.capturedStreamMessages = null;

      // Caller passes nothing — notifier must reuse cached args from start().
      await notifier.retryFull();

      expect(fake.streamCallCount, 2);
      expect(fake.fullCallCount, 0);
      expect(fake.lastStreamRunId, 'run_cached');
      expect(
        fake.capturedStreamMessages?.map((m) => m.content).toList(),
        ['original-1', 'original-2'],
        reason: 'I-P1-b: retryFull must reuse messages cached from start()',
      );

      final state = container.read(streamingAnalyzeProvider('conv-1'));
      expect(state.phase, StreamingAnalyzePhase.done);
    });

    test('a second start() supersedes the cached retry args', () async {
      final fake = _FakeAnalysisService()
        ..recommendationPreviewResult = _preview(runId: 'run_A')
        ..streamError = StreamModeException(
          'fail-A',
          code: 'STREAM_INTERRUPTED_AFTER_RECOMMENDATION',
          recoverable: true,
          retriesRemaining: 2,
          suggestedAction: AnalysisErrorAction.retry,
        );

      final container = _container(fake);
      addTearDown(container.dispose);

      final notifier =
          container.read(streamingAnalyzeProvider('conv-1').notifier);

      await notifier.start(messages: [_msg('first-call')]);

      // Reconfigure for second start with different runId + different messages.
      fake.recommendationPreviewResult = _preview(runId: 'run_B');
      // keep streamError so this run also lands in failedAfterRecommendation
      await notifier.start(messages: [_msg('second-call')]);

      fake.streamError = null;
      fake.fullResult = _full();
      fake.capturedStreamMessages = null;

      await notifier.retryFull();

      expect(fake.lastStreamRunId, 'run_B');
      expect(
        fake.capturedStreamMessages?.map((m) => m.content).toList(),
        ['second-call'],
        reason: 'I-P1-c: second start() must supersede cached args',
      );
    });

    test('retryFull is no-op when called before start (no cached runId)',
        () async {
      final fake = _FakeAnalysisService();
      final container = _container(fake);
      addTearDown(container.dispose);

      final notifier =
          container.read(streamingAnalyzeProvider('conv-1').notifier);

      await notifier.retryFull();

      expect(fake.fullCallCount, 0);
      final state = container.read(streamingAnalyzeProvider('conv-1'));
      expect(state.phase, StreamingAnalyzePhase.idle);
    });
  });

  group('StreamingAnalyzeNotifier — stale guard', () {
    test('a new start() supersedes an in-flight full; old full is discarded',
        () async {
      // First start: recommendation preview yields runId A, full is gated and never publishes
      // because a second start() arrives mid-flight.
      final gateA = Completer<void>();
      final fake = _FakeAnalysisService()
        ..recommendationPreviewResult = _preview(runId: 'run_A')
        ..fullResult = _full()
        ..fullGate = gateA;

      final container = _container(fake);
      addTearDown(container.dispose);

      final notifier =
          container.read(streamingAnalyzeProvider('conv-1').notifier);

      final firstStart = notifier.start(messages: [_msg('a')]);

      // let recommendation preview complete + full begin
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      // Reconfigure fake for second start (new runId).
      fake.recommendationPreviewResult = _preview(runId: 'run_B');
      fake.fullGate = null; // second full resolves immediately
      final secondStart = notifier.start(messages: [_msg('b')]);

      await secondStart;

      // Now release the first full call — it should NOT overwrite state.
      gateA.complete();
      await firstStart;

      final state = container.read(streamingAnalyzeProvider('conv-1'));
      expect(state.phase, StreamingAnalyzePhase.done);
      expect(state.analysisRunId, 'run_B');
      expect(state.recommendationPreview?.analysisRunId, 'run_B');
    });
  });

  group('StreamingAnalyzeNotifier streaming local prelude progress', () {
    test('updates local progress while waiting for first server event',
        () async {
      final fake = _FakeAnalysisService()
        ..recommendationPreviewResult = _preview(runId: 'run_prelude')
        ..fullResult = _full()
        ..streamStartGate = Completer<void>();

      final container = _container(fake);
      addTearDown(container.dispose);

      final notifier =
          container.read(streamingAnalyzeProvider('conv-1').notifier);

      final startFuture = notifier.start(messages: [_msg('hi')]);

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final waiting = container.read(streamingAnalyzeProvider('conv-1'));
      expect(waiting.phase, StreamingAnalyzePhase.connecting);
      expect(waiting.streamProgressLabel, '正在送出完整分析請求');
      expect(waiting.streamProgressDetail, '正在把最新對話與脈絡送到分析端。');

      fake.streamStartGate!.complete();
      await startFuture;

      final done = container.read(streamingAnalyzeProvider('conv-1'));
      expect(done.phase, StreamingAnalyzePhase.done);
    });

    test('accumulates structured content while full stream is running',
        () async {
      final fake = _FakeAnalysisService()
        ..recommendationPreviewResult = _preview(runId: 'run_content')
        ..fullResult = _full()
        ..fullGate = Completer<void>()
        ..streamContents = const [
          AnalysisStreamContent(
            kind: AnalysisStreamContentKind.decision,
            title: '下一步策略',
            body: '先承接情緒，再把回覆壓短。',
            rawEvent: {'type': 'analysis.decision'},
          ),
        ];

      final container = _container(fake);
      addTearDown(container.dispose);

      final notifier =
          container.read(streamingAnalyzeProvider('conv-1').notifier);

      final startFuture = notifier.start(messages: [_msg('hi')]);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final running = container.read(streamingAnalyzeProvider('conv-1'));
      expect(running.phase, StreamingAnalyzePhase.streamingReport);
      expect(running.streamContents, hasLength(1));
      expect(running.streamContents.single.title, '下一步策略');
      expect(running.streamContents.single.body, '先承接情緒，再把回覆壓短。');

      fake.fullGate!.complete();
      await startFuture;
    });

    test('content-before-recommendation failure keeps retryable full state',
        () async {
      final fake = _FakeAnalysisService()
        ..streamError = StreamModeException(
          'stream reset',
          code: 'STREAM_INTERRUPTED_AFTER_CONTENT',
          recoverable: true,
          retriesRemaining: 1,
          suggestedAction: AnalysisErrorAction.retry,
        )
        ..streamContents = const [
          AnalysisStreamContent(
            kind: AnalysisStreamContentKind.decision,
            title: '下一步策略',
            body: '先承接情緒，再把回覆壓短。',
            rawEvent: {'type': 'analysis.decision'},
          ),
        ];

      final container = _container(fake);
      addTearDown(container.dispose);

      final notifier =
          container.read(streamingAnalyzeProvider('conv-1').notifier);

      await notifier.start(messages: [_msg('hi')]);

      final failed = container.read(streamingAnalyzeProvider('conv-1'));
      expect(failed.phase, StreamingAnalyzePhase.failedAfterRecommendation);
      expect(failed.recommendationPreview, isNull);
      expect(failed.streamContents, hasLength(1));
      expect(failed.retriesRemaining, 1);
    });

    test('server progress takes over and is not overwritten locally', () async {
      final fake = _FakeAnalysisService()
        ..fullResult = _full()
        ..streamStartGate = Completer<void>()
        ..fullGate = Completer<void>();

      final container = _container(fake);
      addTearDown(container.dispose);

      final notifier =
          container.read(streamingAnalyzeProvider('conv-1').notifier);

      final startFuture = notifier.start(messages: [_msg('hi')]);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      fake.streamStartGate!.complete();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final afterServerEvent =
          container.read(streamingAnalyzeProvider('conv-1'));
      expect(afterServerEvent.streamProgressLabel, 'starting stream');

      await Future<void>.delayed(const Duration(milliseconds: 3200));
      final stillServerEvent =
          container.read(streamingAnalyzeProvider('conv-1'));
      expect(stillServerEvent.streamProgressLabel, 'starting stream');

      fake.fullGate!.complete();
      await startFuture;
    });
  });
}
