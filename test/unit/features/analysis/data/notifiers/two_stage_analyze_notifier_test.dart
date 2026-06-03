import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/data/notifiers/two_stage_analyze_notifier.dart';
import 'package:vibesync/features/analysis/data/providers/analysis_providers.dart';
import 'package:vibesync/features/analysis/data/services/analysis_service.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_models.dart';
import 'package:vibesync/features/analysis/domain/entities/game_stage.dart';
import 'package:vibesync/features/analysis/domain/entities/quick_analysis_result.dart';
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

QuickAnalysisResult _quick({String runId = 'run_q1', int? eta = 17}) {
  return QuickAnalysisResult(
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

  QuickAnalysisResult? quickResult;
  Exception? quickError;
  AnalysisResult? fullResult;
  Exception? fullError;
  Exception? streamError;
  Completer<void>? fullGate;

  int streamCallCount = 0;
  int quickCallCount = 0;
  int fullCallCount = 0;
  String? lastFullRunId;
  List<Message>? capturedStreamMessages;
  List<Message>? capturedFullMessages;

  @override
  Future<QuickAnalysisResult> analyzeQuick({
    required List<Message> messages,
    SessionContext? sessionContext,
    String? conversationSummary,
    String? partnerSummary,
    String? effectiveStyleContext,
    String? knownContactName,
    int? previousAnalyzedCount,
  }) async {
    quickCallCount++;
    if (quickError != null) throw quickError!;
    return quickResult!;
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
    required List<Message> messages,
    SessionContext? sessionContext,
    String? conversationSummary,
    String? partnerSummary,
    String? effectiveStyleContext,
    String? knownContactName,
    int? previousAnalyzedCount,
  }) async* {
    streamCallCount++;
    capturedStreamMessages = List<Message>.from(messages);
    yield const AnalysisStreamUpdate.started(
      runId: 'stream-run',
      label: 'starting stream',
    );
    if (quickError != null) throw quickError!;
    if (quickResult != null) {
      yield AnalysisStreamUpdate.recommendation(
        quick: quickResult!,
        runId: quickResult!.analysisRunId,
      );
    }
    if (fullGate != null) await fullGate!.future;
    if (streamError != null) throw streamError!;
    if (fullError != null) throw fullError!;
    if (fullResult != null) {
      yield AnalysisStreamUpdate.done(
        result: fullResult!,
        runId: quickResult?.analysisRunId ?? 'stream-run',
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
  group('TwoStageAnalyzeNotifier — happy path', () {
    test('build returns idle state', () {
      final fake = _FakeAnalysisService();
      final container = _container(fake);
      addTearDown(container.dispose);

      final state = container.read(twoStageAnalyzeProvider('conv-1'));
      expect(state.phase, TwoStagePhase.idle);
      expect(state.quick, isNull);
      expect(state.full, isNull);
    });

    test('start streams full analysis without calling quick API', () async {
      final fake = _FakeAnalysisService()
        ..quickResult = _quick(runId: 'run_happy')
        ..fullResult = _full()
        ..fullGate = Completer<void>();

      final container = _container(fake);
      addTearDown(container.dispose);

      final phases = <TwoStagePhase>[];
      container.listen(twoStageAnalyzeProvider('conv-1'), (prev, next) {
        phases.add(next.phase);
      });

      final notifier =
          container.read(twoStageAnalyzeProvider('conv-1').notifier);

      final startFuture = notifier.start(
        messages: [_msg('hi')],
        conversationMessageCount: 3,
      );

      // Allow quick to resolve and the runningFull transition to land.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final afterQuick = container.read(twoStageAnalyzeProvider('conv-1'));
      expect(afterQuick.phase, TwoStagePhase.runningFull);
      expect(afterQuick.quick?.analysisRunId, 'run_happy');
      expect(afterQuick.analysisRunId, 'run_happy');
      expect(afterQuick.conversationMessageCount, 3);

      fake.fullGate!.complete();
      await startFuture;

      final afterFull = container.read(twoStageAnalyzeProvider('conv-1'));
      expect(afterFull.phase, TwoStagePhase.fullReady);
      expect(afterFull.conversationMessageCount, 3);
      expect(afterFull.full?.strategy, '保持沉穩');

      expect(
        phases,
        containsAllInOrder([
          TwoStagePhase.runningQuick,
          TwoStagePhase.runningFull,
          TwoStagePhase.fullReady,
        ]),
      );

      expect(fake.streamCallCount, 1);
      expect(fake.quickCallCount, 0);
      expect(fake.fullCallCount, 0);
      expect(fake.capturedStreamMessages?.map((m) => m.content).toList(), [
        'hi',
      ]);
    });
  });

  group('TwoStageAnalyzeNotifier — failure paths', () {
    test('quick failure: runningQuick → quickFailed, no full call', () async {
      final fake = _FakeAnalysisService()
        ..quickError = AnalysisException(
          '網路忙線',
          code: 'NETWORK_ERROR',
        );

      final container = _container(fake);
      addTearDown(container.dispose);

      final notifier =
          container.read(twoStageAnalyzeProvider('conv-1').notifier);

      await notifier.start(messages: [_msg('hi')]);

      final state = container.read(twoStageAnalyzeProvider('conv-1'));
      expect(state.phase, TwoStagePhase.quickFailed);
      expect(state.quick, isNull);
      expect(state.quickErrorMessage, '網路忙線');
      expect(state.quickErrorCode, 'NETWORK_ERROR');
      expect(fake.fullCallCount, 0);
    });

    test('full failure preserves quick and emits fullFailed with retries',
        () async {
      final fake = _FakeAnalysisService()
        ..quickResult = _quick(runId: 'run_keep')
        ..fullError = FullModeException(
          '完整分析失敗，可以重試。',
          code: 'FULL_FAILED',
          retriesRemaining: 2,
        );

      final container = _container(fake);
      addTearDown(container.dispose);

      final notifier =
          container.read(twoStageAnalyzeProvider('conv-1').notifier);

      await notifier.start(messages: [_msg('hi')]);

      final state = container.read(twoStageAnalyzeProvider('conv-1'));
      expect(state.phase, TwoStagePhase.fullFailed);
      expect(state.quick?.analysisRunId, 'run_keep'); // quick preserved
      expect(state.analysisRunId, 'run_keep');
      expect(state.retriesRemaining, 2);
      expect(state.fullErrorCode, 'FULL_FAILED');
      expect(fake.streamCallCount, 1);
      expect(fake.quickCallCount, 0);
      expect(fake.fullCallCount, 0);
    });

    test('retryFull reuses analysisRunId; does not call analyzeQuick',
        () async {
      final fake = _FakeAnalysisService()
        ..quickResult = _quick(runId: 'run_retry')
        ..fullError = FullModeException(
          'transient',
          code: 'FULL_FAILED',
          retriesRemaining: 2,
        );

      final container = _container(fake);
      addTearDown(container.dispose);

      final notifier =
          container.read(twoStageAnalyzeProvider('conv-1').notifier);

      await notifier.start(messages: [_msg('hi')]);
      expect(fake.streamCallCount, 1);
      expect(fake.quickCallCount, 0);
      expect(fake.fullCallCount, 0);

      // Now retry succeeds.
      fake.fullError = null;
      fake.fullResult = _full();

      await notifier.retryFull();

      expect(fake.quickCallCount, 0); // unchanged
      expect(fake.fullCallCount, 1);
      expect(fake.lastFullRunId, 'run_retry');

      final state = container.read(twoStageAnalyzeProvider('conv-1'));
      expect(state.phase, TwoStagePhase.fullReady);
    });

    test('retryFull after RUN_RETRY_EXHAUSTED keeps retriesRemaining=0',
        () async {
      final fake = _FakeAnalysisService()
        ..quickResult = _quick()
        ..fullError = FullModeException(
          '完整分析已達重試上限，請重新分析。',
          code: 'RUN_RETRY_EXHAUSTED',
          retriesRemaining: 0,
        );

      final container = _container(fake);
      addTearDown(container.dispose);

      final notifier =
          container.read(twoStageAnalyzeProvider('conv-1').notifier);

      await notifier.start(messages: [_msg('hi')]);
      await notifier.retryFull();

      final state = container.read(twoStageAnalyzeProvider('conv-1'));
      expect(state.phase, TwoStagePhase.fullFailed);
      expect(state.retriesRemaining, 0);
      expect(state.fullErrorCode, 'RUN_RETRY_EXHAUSTED');
    });
  });

  group('TwoStageAnalysisState.copyWith — clearing semantics (P2)', () {
    test('can explicitly clear nullable fields via null', () {
      const state = TwoStageAnalysisState(
        phase: TwoStagePhase.fullFailed,
        fullErrorMessage: '舊錯誤',
        fullErrorCode: 'OLD_CODE',
        retriesRemaining: 3,
      );

      final cleared = state.copyWith(
        phase: TwoStagePhase.runningFull,
        fullErrorMessage: null,
        fullErrorCode: null,
        retriesRemaining: 0,
      );

      expect(cleared.phase, TwoStagePhase.runningFull);
      expect(cleared.fullErrorMessage, isNull);
      expect(cleared.fullErrorCode, isNull);
      expect(cleared.retriesRemaining, 0);
    });

    test('preserves existing values when params are omitted', () {
      const state = TwoStageAnalysisState(
        phase: TwoStagePhase.fullFailed,
        fullErrorMessage: 'keep me',
        fullErrorCode: 'KEEP',
        retriesRemaining: 2,
      );

      final preserved = state.copyWith(phase: TwoStagePhase.runningFull);

      expect(preserved.phase, TwoStagePhase.runningFull);
      expect(preserved.fullErrorMessage, 'keep me');
      expect(preserved.fullErrorCode, 'KEEP');
      expect(preserved.retriesRemaining, 2);
    });
  });

  group('TwoStageAnalyzeNotifier — retry clears stale error (P2)', () {
    test('retryFull clears fullErrorMessage/code during runningFull', () async {
      final fake = _FakeAnalysisService()
        ..quickResult = _quick(runId: 'run_clear')
        ..fullError = FullModeException(
          'stale failure',
          code: 'FULL_FAILED',
          retriesRemaining: 2,
        );

      final container = _container(fake);
      addTearDown(container.dispose);

      final notifier =
          container.read(twoStageAnalyzeProvider('conv-1').notifier);

      await notifier.start(messages: [_msg('hi')]);
      final failed = container.read(twoStageAnalyzeProvider('conv-1'));
      expect(failed.phase, TwoStagePhase.fullFailed);
      expect(failed.fullErrorMessage, 'stale failure');

      // Gate the retry full call so we can observe runningFull state in flight.
      fake.fullError = null;
      fake.fullResult = _full();
      fake.fullGate = Completer<void>();

      final retryFuture = notifier.retryFull();

      // Let retryFull push the runningFull transition.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final midFlight = container.read(twoStageAnalyzeProvider('conv-1'));
      expect(midFlight.phase, TwoStagePhase.runningFull);
      expect(midFlight.fullErrorMessage, isNull,
          reason: 'I-P2-b: runningFull must not carry stale error');
      expect(midFlight.fullErrorCode, isNull);
      expect(midFlight.retriesRemaining, 0);

      fake.fullGate!.complete();
      await retryFuture;

      final done = container.read(twoStageAnalyzeProvider('conv-1'));
      expect(done.phase, TwoStagePhase.fullReady);
      expect(done.fullErrorMessage, isNull,
          reason: 'I-P2-c: fullReady must not carry stale error');
      expect(done.fullErrorCode, isNull);
    });
  });

  group('TwoStageAnalyzeNotifier — retry args caching (P1)', () {
    test('retryFull() with no args reuses messages cached from start()',
        () async {
      final fake = _FakeAnalysisService()
        ..quickResult = _quick(runId: 'run_cached')
        ..fullError = FullModeException(
          'transient',
          code: 'FULL_FAILED',
          retriesRemaining: 2,
        );

      final container = _container(fake);
      addTearDown(container.dispose);

      final notifier =
          container.read(twoStageAnalyzeProvider('conv-1').notifier);

      final original = [_msg('original-1'), _msg('original-2')];
      await notifier.start(messages: original);
      expect(fake.streamCallCount, 1);
      expect(fake.quickCallCount, 0);
      expect(fake.fullCallCount, 0);

      // Reconfigure for retry success and capture the messages the service sees.
      fake.fullError = null;
      fake.fullResult = _full();
      fake.capturedFullMessages = null;

      // Caller passes nothing — notifier must reuse cached args from start().
      await notifier.retryFull();

      expect(fake.fullCallCount, 1);
      expect(fake.lastFullRunId, 'run_cached');
      expect(
        fake.capturedFullMessages?.map((m) => m.content).toList(),
        ['original-1', 'original-2'],
        reason: 'I-P1-b: retryFull must reuse messages cached from start()',
      );

      final state = container.read(twoStageAnalyzeProvider('conv-1'));
      expect(state.phase, TwoStagePhase.fullReady);
    });

    test('a second start() supersedes the cached retry args', () async {
      final fake = _FakeAnalysisService()
        ..quickResult = _quick(runId: 'run_A')
        ..fullError = FullModeException(
          'fail-A',
          code: 'FULL_FAILED',
          retriesRemaining: 2,
        );

      final container = _container(fake);
      addTearDown(container.dispose);

      final notifier =
          container.read(twoStageAnalyzeProvider('conv-1').notifier);

      await notifier.start(messages: [_msg('first-call')]);

      // Reconfigure for second start with different runId + different messages.
      fake.quickResult = _quick(runId: 'run_B');
      // keep fullError so this run also lands in fullFailed
      await notifier.start(messages: [_msg('second-call')]);

      fake.fullError = null;
      fake.fullResult = _full();
      fake.capturedFullMessages = null;

      await notifier.retryFull();

      expect(fake.lastFullRunId, 'run_B');
      expect(
        fake.capturedFullMessages?.map((m) => m.content).toList(),
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
          container.read(twoStageAnalyzeProvider('conv-1').notifier);

      await notifier.retryFull();

      expect(fake.fullCallCount, 0);
      final state = container.read(twoStageAnalyzeProvider('conv-1'));
      expect(state.phase, TwoStagePhase.idle);
    });
  });

  group('TwoStageAnalyzeNotifier — stale guard', () {
    test('a new start() supersedes an in-flight full; old full is discarded',
        () async {
      // First start: quick yields runId A, full is gated and never publishes
      // because a second start() arrives mid-flight.
      final gateA = Completer<void>();
      final fake = _FakeAnalysisService()
        ..quickResult = _quick(runId: 'run_A')
        ..fullResult = _full()
        ..fullGate = gateA;

      final container = _container(fake);
      addTearDown(container.dispose);

      final notifier =
          container.read(twoStageAnalyzeProvider('conv-1').notifier);

      final firstStart = notifier.start(messages: [_msg('a')]);

      // let quick complete + full begin
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      // Reconfigure fake for second start (new runId).
      fake.quickResult = _quick(runId: 'run_B');
      fake.fullGate = null; // second full resolves immediately
      final secondStart = notifier.start(messages: [_msg('b')]);

      await secondStart;

      // Now release the first full call — it should NOT overwrite state.
      gateA.complete();
      await firstStart;

      final state = container.read(twoStageAnalyzeProvider('conv-1'));
      expect(state.phase, TwoStagePhase.fullReady);
      expect(state.analysisRunId, 'run_B');
      expect(state.quick?.analysisRunId, 'run_B');
    });
  });
}
