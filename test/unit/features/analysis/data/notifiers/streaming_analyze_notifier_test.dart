import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/data/notifiers/streaming_analyze_notifier.dart';
import 'package:vibesync/features/analysis/data/providers/analysis_providers.dart';
import 'package:vibesync/features/analysis/data/services/analysis_service.dart';
import 'package:vibesync/features/analysis/data/services/analyze_stream_client.dart';
import 'package:vibesync/features/analysis/presentation/helpers/analysis_stream_content_display.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_models.dart';
import 'package:vibesync/features/analysis/domain/entities/game_stage.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_recommendation_preview.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';

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
    estimatedReportSeconds: eta,
  );
}

AnalysisResult _analysisResult() {
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

class _FakeAnalyzeStreamClient extends AnalyzeStreamClient {
  _FakeAnalyzeStreamClient()
      : super(displayMapper: const AnalysisStreamContentDisplayMapper());

  AnalysisRecommendationPreview? recommendationPreviewResult;
  Exception? recommendationPreviewError;
  AnalysisResult? streamResult;
  Exception? streamError;
  List<Exception?> streamCallErrors = <Exception?>[];
  Completer<void>? streamStartGate;
  Completer<void>? streamGate;
  List<AnalysisStreamContent> streamContents = const [];
  bool emitRunIdOnlyOnDone = false;

  int streamCallCount = 0;
  String? lastStreamRunId;
  List<Message>? capturedStreamMessages;

  @override
  Stream<AnalysisStreamUpdate> stream(AnalyzeStreamRequest request) async* {
    final callIndex = streamCallCount++;
    lastStreamRunId = request.analysisRunId;
    capturedStreamMessages = List<Message>.from(request.messages);
    if (streamStartGate != null) await streamStartGate!.future;
    yield AnalysisStreamUpdate.started(
      runId: emitRunIdOnlyOnDone ? null : 'stream-run',
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
    if (streamGate != null) await streamGate!.future;
    final callError = callIndex < streamCallErrors.length
        ? streamCallErrors[callIndex]
        : streamError;
    if (callError != null) throw callError;
    if (streamResult != null) {
      yield AnalysisStreamUpdate.done(
        result: streamResult!,
        runId: emitRunIdOnlyOnDone
            ? 'done-only-run'
            : recommendationPreviewResult?.analysisRunId ?? 'stream-run',
      );
    }
  }
}

ProviderContainer _container(AnalyzeStreamClient fake) {
  return ProviderContainer(overrides: [
    analyzeStreamClientProvider.overrideWithValue(fake),
  ]);
}

void main() {
  group('StreamingAnalyzeNotifier — happy path', () {
    test('build returns idle state', () {
      final fake = _FakeAnalyzeStreamClient();
      final container = _container(fake);
      addTearDown(container.dispose);

      final state = container.read(streamingAnalyzeProvider('conv-1'));
      expect(state.phase, StreamingAnalyzePhase.idle);
      expect(state.recommendationPreview, isNull);
      expect(state.result, isNull);
    });

    test('start uses the streaming analysis transport', () async {
      final fake = _FakeAnalyzeStreamClient()
        ..recommendationPreviewResult = _preview(runId: 'run_happy')
        ..streamResult = _analysisResult()
        ..streamGate = Completer<void>();

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
        previousAnalyzedCount: 2,
        conversationMessageCount: 3,
        conversationContentRevision: 'revision-happy',
      );

      // Allow recommendation preview to resolve and the streamingReport transition to land.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final afterQuick = container.read(streamingAnalyzeProvider('conv-1'));
      expect(afterQuick.phase, StreamingAnalyzePhase.streamingReport);
      expect(afterQuick.recommendationPreview?.analysisRunId, 'run_happy');
      expect(afterQuick.analysisRunId, 'run_happy');
      expect(afterQuick.conversationMessageCount, 3);
      expect(afterQuick.previousAnalyzedCount, 2);
      expect(afterQuick.conversationContentRevision, 'revision-happy');

      fake.streamGate!.complete();
      await startFuture;

      final afterFull = container.read(streamingAnalyzeProvider('conv-1'));
      expect(afterFull.phase, StreamingAnalyzePhase.done);
      expect(afterFull.conversationMessageCount, 3);
      expect(afterFull.previousAnalyzedCount, 2);
      expect(afterFull.conversationContentRevision, 'revision-happy');
      expect(afterFull.result?.strategy, '保持沉穩');

      expect(
        phases,
        containsAllInOrder([
          StreamingAnalyzePhase.connecting,
          StreamingAnalyzePhase.streamingReport,
          StreamingAnalyzePhase.done,
        ]),
      );

      expect(fake.streamCallCount, 1);
      expect(fake.capturedStreamMessages?.map((m) => m.content).toList(), [
        'hi',
      ]);
    });

    test('done event preserves a run id not emitted by earlier events',
        () async {
      final fake = _FakeAnalyzeStreamClient()
        ..emitRunIdOnlyOnDone = true
        ..streamResult = _analysisResult();
      final container = _container(fake);
      addTearDown(container.dispose);

      await container.read(streamingAnalyzeProvider('conv-1').notifier).start(
        messages: [_msg('hi')],
      );

      final state = container.read(streamingAnalyzeProvider('conv-1'));
      expect(state.phase, StreamingAnalyzePhase.done);
      expect(state.analysisRunId, 'done-only-run');
    });
  });

  group('StreamingAnalyzeNotifier — failure paths', () {
    test('pre-recommendation transport failure keeps the server run retryable',
        () async {
      final fake = _FakeAnalyzeStreamClient()
        ..recommendationPreviewError = AnalysisException(
          '網路忙線',
          code: 'NETWORK_ERROR',
          suggestedAction: AnalysisErrorAction.retry,
        );

      final container = _container(fake);
      addTearDown(container.dispose);

      final notifier =
          container.read(streamingAnalyzeProvider('conv-1').notifier);

      await notifier.start(
        messages: [_msg('hi')],
        previousAnalyzedCount: 2,
        conversationContentRevision: 'revision-failure',
      );

      final state = container.read(streamingAnalyzeProvider('conv-1'));
      expect(state.phase, StreamingAnalyzePhase.failedAfterRecommendation);
      expect(state.recommendationPreview, isNull);
      expect(state.analysisRunId, 'stream-run');
      expect(state.streamErrorMessage, '網路忙線');
      expect(state.streamErrorCode, 'NETWORK_ERROR');
      expect(state.retriesRemaining, 1);
      expect(fake.streamCallCount, 3);
      expect(state.previousAnalyzedCount, 2);
      expect(state.conversationContentRevision, 'revision-failure');
    });

    test('quota exhaustion failure uses localized streaming error copy',
        () async {
      final fake = _FakeAnalyzeStreamClient()
        ..streamError = DailyLimitExceededException(
          dailyLimit: 15,
          used: 15,
        );

      final container = _container(fake);
      addTearDown(container.dispose);

      final notifier =
          container.read(streamingAnalyzeProvider('conv-1').notifier);

      await notifier.start(
        messages: [_msg('hi')],
        conversationContentRevision: 'revision-quota',
      );

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
        'stream failure preserves recommendation preview and emits failedAfterRecommendation with retries',
        () async {
      final fake = _FakeAnalyzeStreamClient()
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
      expect(state.streamErrorCode, 'STREAM_INTERRUPTED_AFTER_RECOMMENDATION');
      expect(fake.streamCallCount, 1);
    });

    test('retryStream reuses analysisRunId on the streaming transport',
        () async {
      final fake = _FakeAnalyzeStreamClient()
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

      await notifier.start(
        messages: [_msg('hi')],
        previousAnalyzedCount: 1,
        conversationContentRevision: 'revision-retry',
      );
      expect(fake.streamCallCount, 1);

      // Now retry succeeds.
      fake.streamError = null;
      fake.streamResult = _analysisResult();

      await notifier.retryStream();

      expect(fake.streamCallCount, 2);
      expect(fake.lastStreamRunId, 'run_retry');

      final state = container.read(streamingAnalyzeProvider('conv-1'));
      expect(state.phase, StreamingAnalyzePhase.done);
      expect(state.previousAnalyzedCount, 1);
      expect(state.conversationContentRevision, 'revision-retry');
    });

    test(
        'retryStream after unrecoverable stream error keeps retriesRemaining=0',
        () async {
      final fake = _FakeAnalyzeStreamClient()
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
      await notifier.retryStream();

      final state = container.read(streamingAnalyzeProvider('conv-1'));
      expect(state.phase, StreamingAnalyzePhase.failedAfterRecommendation);
      expect(state.retriesRemaining, 0);
      expect(state.streamErrorCode, 'STREAM_RUN_RETRY_UNAVAILABLE');
    });
  });

  group('StreamingAnalyzeNotifier — quota 429 分流（smoke P1 fix 2026-06-11）', () {
    test(
        'monthly quota 429 after preview → quotaExceeded state（不得落 generic retry-exhausted）',
        () async {
      final fake = _FakeAnalyzeStreamClient()
        ..recommendationPreviewResult = _preview(runId: 'run_quota')
        ..streamError = MonthlyLimitExceededException(
          monthlyLimit: 200,
          used: 198,
          remaining: 2,
          quotaNeeded: 5,
        );

      final container = _container(fake);
      addTearDown(container.dispose);

      final notifier =
          container.read(streamingAnalyzeProvider('conv-1').notifier);

      await notifier.start(messages: [_msg('hi')]);

      final state = container.read(streamingAnalyzeProvider('conv-1'));
      expect(state.phase, StreamingAnalyzePhase.failedAfterRecommendation);
      expect(state.quotaExceeded, isNotNull);
      expect(state.quotaExceeded!.isMonthly, isTrue);
      expect(state.quotaExceeded!.remaining, 2);
      expect(state.quotaExceeded!.quotaNeeded, 5);
      expect(state.retriesRemaining, 0);
      expect(state.streamErrorCode, 'MONTHLY_LIMIT_EXCEEDED');
    });

    test(
        'daily quota 429 after content → quotaExceeded daily + retriesRemaining 0'
        '（regression：wait action 過去會給 1 次無意義 retry）', () async {
      final fake = _FakeAnalyzeStreamClient()
        ..streamError = DailyLimitExceededException(
          dailyLimit: 15,
          used: 15,
          remaining: 0,
          quotaNeeded: 3,
        )
        ..streamContents = const [
          AnalysisStreamContent(
            kind: AnalysisStreamContentKind.decision,
            title: 'Decision',
            body: 'partial',
            rawEvent: {'type': 'analysis.decision'},
          ),
        ];

      final container = _container(fake);
      addTearDown(container.dispose);

      final notifier =
          container.read(streamingAnalyzeProvider('conv-1').notifier);

      await notifier.start(messages: [_msg('hi')]);

      final state = container.read(streamingAnalyzeProvider('conv-1'));
      expect(state.phase, StreamingAnalyzePhase.failedAfterRecommendation);
      expect(state.quotaExceeded, isNotNull);
      expect(state.quotaExceeded!.isMonthly, isFalse);
      expect(state.quotaExceeded!.remaining, 0);
      expect(state.quotaExceeded!.quotaNeeded, 3);
      expect(state.retriesRemaining, 0);
    });

    test('retryStream 撞 quota 429 → quotaExceeded state（Bruce 實際觸發路）',
        () async {
      final fake = _FakeAnalyzeStreamClient()
        ..recommendationPreviewResult = _preview(runId: 'run_retry_quota')
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
      expect(
        container.read(streamingAnalyzeProvider('conv-1')).quotaExceeded,
        isNull,
      );

      fake.streamError = MonthlyLimitExceededException(
        monthlyLimit: 200,
        used: 199,
        remaining: 1,
        quotaNeeded: 4,
      );

      await notifier.retryStream();

      final state = container.read(streamingAnalyzeProvider('conv-1'));
      expect(state.phase, StreamingAnalyzePhase.failedAfterRecommendation);
      expect(state.quotaExceeded, isNotNull);
      expect(state.quotaExceeded!.isMonthly, isTrue);
      expect(state.quotaExceeded!.remaining, 1);
      expect(state.retriesRemaining, 0);
    });

    test('成功 retry 後 quotaExceeded 清空（不殘留舊 quota 卡）', () async {
      final fake = _FakeAnalyzeStreamClient()
        ..recommendationPreviewResult = _preview(runId: 'run_quota_clear')
        ..streamError = MonthlyLimitExceededException(
          monthlyLimit: 200,
          used: 198,
          remaining: 2,
          quotaNeeded: 5,
        );

      final container = _container(fake);
      addTearDown(container.dispose);

      final notifier =
          container.read(streamingAnalyzeProvider('conv-1').notifier);

      await notifier.start(messages: [_msg('hi')]);
      expect(
        container.read(streamingAnalyzeProvider('conv-1')).quotaExceeded,
        isNotNull,
      );

      fake.streamError = null;
      fake.streamResult = _analysisResult();

      await notifier.retryStream();

      final state = container.read(streamingAnalyzeProvider('conv-1'));
      expect(state.phase, StreamingAnalyzePhase.done);
      expect(state.quotaExceeded, isNull);
    });

    test(
        'fresh-start quota 429（無 content）維持 failedBeforeRecommendation 並帶 quotaExceeded',
        () async {
      final fake = _FakeAnalyzeStreamClient()
        ..streamError = MonthlyLimitExceededException(
          monthlyLimit: 30,
          used: 30,
          remaining: 0,
          quotaNeeded: 2,
        );

      final container = _container(fake);
      addTearDown(container.dispose);

      final notifier =
          container.read(streamingAnalyzeProvider('conv-1').notifier);

      await notifier.start(messages: [_msg('hi')]);

      final state = container.read(streamingAnalyzeProvider('conv-1'));
      expect(state.phase, StreamingAnalyzePhase.failedBeforeRecommendation);
      expect(state.recommendationPreviewErrorCode, 'MONTHLY_LIMIT_EXCEEDED');
      expect(state.quotaExceeded, isNotNull);
      expect(state.quotaExceeded!.isMonthly, isTrue);
    });

    test('exception 未帶 remaining 時 fallback 用 limit-used 計算', () async {
      final fake = _FakeAnalyzeStreamClient()
        ..recommendationPreviewResult = _preview(runId: 'run_fallback')
        ..streamError = DailyLimitExceededException(
          dailyLimit: 15,
          used: 13,
        );

      final container = _container(fake);
      addTearDown(container.dispose);

      final notifier =
          container.read(streamingAnalyzeProvider('conv-1').notifier);

      await notifier.start(messages: [_msg('hi')]);

      final state = container.read(streamingAnalyzeProvider('conv-1'));
      expect(state.quotaExceeded, isNotNull);
      expect(state.quotaExceeded!.remaining, 2);
      expect(state.quotaExceeded!.quotaNeeded, isNull);
    });
  });

  group('StreamingAnalysisState.copyWith — clearing semantics (P2)', () {
    test('can explicitly clear nullable fields via null', () {
      const state = StreamingAnalysisState(
        phase: StreamingAnalyzePhase.failedAfterRecommendation,
        streamErrorMessage: '舊錯誤',
        streamErrorCode: 'OLD_CODE',
        retriesRemaining: 3,
      );

      final cleared = state.copyWith(
        phase: StreamingAnalyzePhase.streamingReport,
        streamErrorMessage: null,
        streamErrorCode: null,
        retriesRemaining: 0,
      );

      expect(cleared.phase, StreamingAnalyzePhase.streamingReport);
      expect(cleared.streamErrorMessage, isNull);
      expect(cleared.streamErrorCode, isNull);
      expect(cleared.retriesRemaining, 0);
    });

    test('preserves existing values when params are omitted', () {
      const state = StreamingAnalysisState(
        phase: StreamingAnalyzePhase.failedAfterRecommendation,
        streamErrorMessage: 'keep me',
        streamErrorCode: 'KEEP',
        retriesRemaining: 2,
        previousAnalyzedCount: 4,
        conversationContentRevision: 'revision-copy',
      );

      final preserved =
          state.copyWith(phase: StreamingAnalyzePhase.streamingReport);

      expect(preserved.phase, StreamingAnalyzePhase.streamingReport);
      expect(preserved.streamErrorMessage, 'keep me');
      expect(preserved.streamErrorCode, 'KEEP');
      expect(preserved.retriesRemaining, 2);
      expect(preserved.previousAnalyzedCount, 4);
      expect(preserved.conversationContentRevision, 'revision-copy');
    });
  });

  group('StreamingAnalyzeNotifier — retry clears stale error (P2)', () {
    test('retryStream clears streamErrorMessage/code during streamingReport',
        () async {
      final fake = _FakeAnalyzeStreamClient()
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
      expect(failed.streamErrorMessage, 'stale failure');

      // Gate the retry full call so we can observe streamingReport state in flight.
      fake.streamError = null;
      fake.streamResult = _analysisResult();
      fake.streamGate = Completer<void>();

      final retryFuture = notifier.retryStream();

      // Let retryStream push the streamingReport transition.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final midFlight = container.read(streamingAnalyzeProvider('conv-1'));
      expect(midFlight.phase, StreamingAnalyzePhase.streamingReport);
      expect(midFlight.streamErrorMessage, isNull,
          reason: 'I-P2-b: streamingReport must not carry stale error');
      expect(midFlight.streamErrorCode, isNull);
      expect(midFlight.retriesRemaining, 0);

      fake.streamGate!.complete();
      await retryFuture;

      final done = container.read(streamingAnalyzeProvider('conv-1'));
      expect(done.phase, StreamingAnalyzePhase.done);
      expect(done.streamErrorMessage, isNull,
          reason: 'I-P2-c: done must not carry stale error');
      expect(done.streamErrorCode, isNull);
    });

    test('retryStream clears preserved stream content before replay', () async {
      final fake = _FakeAnalyzeStreamClient()
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
      fake.streamResult = _analysisResult();
      fake.streamStartGate = Completer<void>();

      final retryFuture = notifier.retryStream();
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
    test('retryStream() with no args reuses messages cached from start()',
        () async {
      final fake = _FakeAnalyzeStreamClient()
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

      // Reconfigure for retry success and capture the messages the service sees.
      fake.streamError = null;
      fake.streamResult = _analysisResult();
      fake.capturedStreamMessages = null;

      // Caller passes nothing — notifier must reuse cached args from start().
      await notifier.retryStream();

      expect(fake.streamCallCount, 2);
      expect(fake.lastStreamRunId, 'run_cached');
      expect(
        fake.capturedStreamMessages?.map((m) => m.content).toList(),
        ['original-1', 'original-2'],
        reason: 'I-P1-b: retryStream must reuse messages cached from start()',
      );

      final state = container.read(streamingAnalyzeProvider('conv-1'));
      expect(state.phase, StreamingAnalyzePhase.done);
    });

    test('a second start() supersedes the cached retry args', () async {
      final fake = _FakeAnalyzeStreamClient()
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
      fake.streamResult = _analysisResult();
      fake.capturedStreamMessages = null;

      await notifier.retryStream();

      expect(fake.lastStreamRunId, 'run_B');
      expect(
        fake.capturedStreamMessages?.map((m) => m.content).toList(),
        ['second-call'],
        reason: 'I-P1-c: second start() must supersede cached args',
      );
    });

    test('retryStream is no-op when called before start (no cached runId)',
        () async {
      final fake = _FakeAnalyzeStreamClient();
      final container = _container(fake);
      addTearDown(container.dispose);

      final notifier =
          container.read(streamingAnalyzeProvider('conv-1').notifier);

      await notifier.retryStream();

      final state = container.read(streamingAnalyzeProvider('conv-1'));
      expect(state.phase, StreamingAnalyzePhase.idle);
    });
  });

  group('StreamingAnalyzeNotifier — stale guard', () {
    test(
        'a new start() supersedes an in-flight stream; old stream is discarded',
        () async {
      // First start: recommendation preview yields runId A, full is gated and never publishes
      // because a second start() arrives mid-flight.
      final gateA = Completer<void>();
      final fake = _FakeAnalyzeStreamClient()
        ..recommendationPreviewResult = _preview(runId: 'run_A')
        ..streamResult = _analysisResult()
        ..streamGate = gateA;

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
      fake.streamGate = null; // second full resolves immediately
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
      final fake = _FakeAnalyzeStreamClient()
        ..recommendationPreviewResult = _preview(runId: 'run_prelude')
        ..streamResult = _analysisResult()
        ..streamStartGate = Completer<void>();

      final container = _container(fake);
      addTearDown(container.dispose);

      final notifier =
          container.read(streamingAnalyzeProvider('conv-1').notifier);

      final startFuture = notifier.start(
        messages: [_msg('hi')],
        previousAnalyzedCount: 3,
      );

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final waiting = container.read(streamingAnalyzeProvider('conv-1'));
      expect(waiting.phase, StreamingAnalyzePhase.connecting);
      expect(waiting.previousAnalyzedCount, 3);
      expect(waiting.streamProgressLabel, '正在送出完整分析請求');
      expect(waiting.streamProgressDetail, '正在把最新對話與脈絡送到分析端。');

      fake.streamStartGate!.complete();
      await startFuture;

      final done = container.read(streamingAnalyzeProvider('conv-1'));
      expect(done.phase, StreamingAnalyzePhase.done);
      expect(done.previousAnalyzedCount, 3);
    });

    test('accumulates structured content while report stream is running',
        () async {
      final fake = _FakeAnalyzeStreamClient()
        ..recommendationPreviewResult = _preview(runId: 'run_content')
        ..streamResult = _analysisResult()
        ..streamGate = Completer<void>()
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

      fake.streamGate!.complete();
      await startFuture;
    });

    test('content-before-recommendation failure keeps retryable stream state',
        () async {
      final fake = _FakeAnalyzeStreamClient()
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
      final fake = _FakeAnalyzeStreamClient()
        ..streamResult = _analysisResult()
        ..streamStartGate = Completer<void>()
        ..streamGate = Completer<void>();

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

      fake.streamGate!.complete();
      await startFuture;
    });
  });

  group('StreamingAnalyzeNotifier stream recovery', () {
    test('automatically resumes the same run after a recoverable disconnect',
        () async {
      final fake = _FakeAnalyzeStreamClient()
        ..recommendationPreviewResult = _preview(runId: 'stream-run')
        ..streamResult = _analysisResult()
        ..streamCallErrors = <Exception?>[
          AnalysisException(
            '網路連線中斷。',
            code: 'NETWORK_ERROR',
            suggestedAction: AnalysisErrorAction.retry,
          ),
          null,
        ];
      final container = _container(fake);
      addTearDown(container.dispose);

      await container.read(streamingAnalyzeProvider('conv-1').notifier).start(
        messages: [_msg('hi')],
      );

      final state = container.read(streamingAnalyzeProvider('conv-1'));
      expect(state.phase, StreamingAnalyzePhase.done);
      expect(state.result, same(fake.streamResult));
      expect(fake.streamCallCount, 2);
      expect(fake.lastStreamRunId, 'stream-run');
    });

    test('uses the same run when recovery reports that a retry is ready',
        () async {
      final fake = _FakeAnalyzeStreamClient()
        ..recommendationPreviewResult = _preview(runId: 'stream-run')
        ..streamResult = _analysisResult()
        ..streamCallErrors = <Exception?>[
          AnalysisException(
            '網路連線中斷。',
            code: 'NETWORK_ERROR',
            suggestedAction: AnalysisErrorAction.retry,
          ),
          StreamModeException(
            '可以安全接續。',
            code: 'STREAM_RUN_RECOVERY_RETRY_READY',
            recoverable: true,
            retriesRemaining: 2,
            suggestedAction: AnalysisErrorAction.retry,
          ),
          null,
        ];
      final container = _container(fake);
      addTearDown(container.dispose);

      await container.read(streamingAnalyzeProvider('conv-1').notifier).start(
        messages: [_msg('hi')],
      );

      final state = container.read(streamingAnalyzeProvider('conv-1'));
      expect(state.phase, StreamingAnalyzePhase.done);
      expect(fake.streamCallCount, 3);
      expect(fake.lastStreamRunId, 'stream-run');
    });

    test('keeps the run retryable when recovery times out before a preview',
        () async {
      final fake = _FakeAnalyzeStreamClient()
        ..streamError = StreamModeException(
          '原本的分析仍在整理中。',
          code: 'STREAM_RUN_STILL_PROCESSING',
          recoverable: true,
          retriesRemaining: 1,
          suggestedAction: AnalysisErrorAction.retry,
        );
      final container = _container(fake);
      addTearDown(container.dispose);
      final notifier =
          container.read(streamingAnalyzeProvider('conv-1').notifier);

      await notifier.start(messages: [_msg('hi')]);

      final failed = container.read(streamingAnalyzeProvider('conv-1'));
      expect(failed.phase, StreamingAnalyzePhase.failedAfterRecommendation);
      expect(failed.recommendationPreview, isNull);
      expect(failed.analysisRunId, 'stream-run');
      expect(failed.retriesRemaining, 1);

      fake
        ..streamError = null
        ..streamResult = _analysisResult();
      await notifier.retryStream();

      expect(
        container.read(streamingAnalyzeProvider('conv-1')).phase,
        StreamingAnalyzePhase.done,
      );
      expect(fake.lastStreamRunId, 'stream-run');
    });

    test('does not attempt same-run recovery before receiving a run id',
        () async {
      final fake = _FakeAnalyzeStreamClient()
        ..emitRunIdOnlyOnDone = true
        ..streamError = AnalysisException(
          '連線中斷。',
          code: 'NETWORK_ERROR',
          suggestedAction: AnalysisErrorAction.retry,
        );
      final container = _container(fake);
      addTearDown(container.dispose);

      await container.read(streamingAnalyzeProvider('conv-1').notifier).start(
        messages: [_msg('hi')],
      );

      final state = container.read(streamingAnalyzeProvider('conv-1'));
      expect(state.phase, StreamingAnalyzePhase.failedBeforeRecommendation);
      expect(state.analysisRunId, isNull);
      expect(fake.streamCallCount, 1);
    });
  });
}
