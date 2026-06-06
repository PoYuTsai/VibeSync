import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/features/analysis/data/notifiers/streaming_analyze_notifier.dart';
import 'package:vibesync/features/analysis/data/providers/analysis_providers.dart';
import 'package:vibesync/features/analysis/data/services/analysis_service.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_models.dart';
import 'package:vibesync/features/analysis/domain/entities/game_stage.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_recommendation_preview.dart';
import 'package:vibesync/features/analysis/presentation/screens/analysis_screen.dart';
import 'package:vibesync/features/analysis/presentation/widgets/streaming_analysis_loading_widgets.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_providers.dart';
import 'package:vibesync/features/conversation/data/repositories/conversation_repository.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/features/conversation/domain/entities/session_context.dart';
import 'package:vibesync/shared/widgets/coach_action_card.dart';
import 'package:vibesync/shared/widgets/image_picker_widget.dart';

const _conversationId = 'hydration-test';

/// Notifier that starts in a pre-seeded state, simulating a remount of
/// AnalysisScreen onto an already-running provider. Critically, [build] is the
/// override hook for the initial state — no analyze calls are needed to land
/// the screen in the target phase.
class _SeededStreamingAnalyzeNotifier extends StreamingAnalyzeNotifier {
  _SeededStreamingAnalyzeNotifier(this.seed);
  final StreamingAnalysisState seed;

  @override
  StreamingAnalysisState build(String conversationId) => seed;
}

class _MutableStreamingAnalyzeNotifier extends StreamingAnalyzeNotifier {
  _MutableStreamingAnalyzeNotifier(this.seed);
  final StreamingAnalysisState seed;

  @override
  StreamingAnalysisState build(String conversationId) => seed;

  void emit(StreamingAnalysisState next) {
    state = next;
  }
}

/// Records any call to analyzeQuick/analyzeFull so tests can assert the
/// screen did not re-trigger an analyze after hydrating.
class _RecordingAnalysisService extends AnalysisService {
  int recommendationPreviewCalls = 0;
  int fullCalls = 0;

  @override
  Future<AnalysisRecommendationPreview> analyzeQuick({
    required List<Message> messages,
    SessionContext? sessionContext,
    String? conversationSummary,
    String? partnerSummary,
    String? effectiveStyleContext,
    String? knownContactName,
    int? previousAnalyzedCount,
  }) async {
    recommendationPreviewCalls++;
    throw StateError('analyzeQuick must not be called on remount');
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
    fullCalls++;
    throw StateError('analyzeFull must not be called on remount');
  }
}

AnalysisRecommendationPreview _preview({
  String runId = 'run_hydrate',
  int? eta = 17,
}) {
  return AnalysisRecommendationPreview(
    analysisRunId: runId,
    pick: 'resonate',
    nextStep: '先接住情緒再延伸',
    recommendedReply: '聽起來累，要不要週末喝杯咖啡？',
    shortReason: '情緒先接住',
    insufficientContext: false,
    confidence: 'high',
    estimatedFullSeconds: eta,
  );
}

AnalysisResult _full() {
  return const AnalysisResult(
    enthusiasmScore: 72,
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
    dogfoodRawFullRecommendation: FinalRecommendation(
      pick: 'resonate',
      content: 'Full 原始推薦回覆',
      reason: '完整 prompt 原始理由',
      psychology: '完整 prompt 原始判斷',
    ),
    dogfoodOfficialFullRecommendation: FinalRecommendation(
      pick: 'tease',
      content: '正式顯示推薦回覆',
      reason: '正式顯示理由',
      psychology: '正式顯示判斷',
    ),
    dogfoodEntitlementAdjusted: true,
    dogfoodTierUsed: 'free',
    reminder: '記得用你的方式說',
  );
}

/// Full result variant that carries a `rawResponse` so the P2 dedup signal
/// `conv.lastAnalysisSnapshotJson == jsonEncode(result.rawResponse)` is
/// exercisable. The fields below mirror what the Edge `analyze-chat` shape
/// returns for the persistence path.
AnalysisResult _fullWithRawResponse(Map<String, dynamic> rawResponse) {
  final base = _full();
  return AnalysisResult(
    enthusiasmScore: base.enthusiasmScore,
    strategy: base.strategy,
    gameStage: base.gameStage,
    psychology: base.psychology,
    topicDepth: base.topicDepth,
    replies: base.replies,
    replyOptions: base.replyOptions,
    recommendation: base.recommendation,
    dogfoodRawFullRecommendation: base.dogfoodRawFullRecommendation,
    dogfoodOfficialFullRecommendation: base.dogfoodOfficialFullRecommendation,
    dogfoodEntitlementAdjusted: base.dogfoodEntitlementAdjusted,
    dogfoodTierUsed: base.dogfoodTierUsed,
    reminder: base.reminder,
    rawResponse: rawResponse,
  );
}

Map<String, dynamic> _fullRawResponse() {
  return <String, dynamic>{
    'enthusiasm': {'score': 72},
    'strategy': '保持沉穩',
    'gameStage': {
      'current': 'premise',
      'status': 'normal',
      'nextStep': '繼續',
    },
    'psychology': {
      'subtext': '有興趣',
      'qualificationSignal': true,
    },
    'topicDepth': {
      'current': 'personal',
      'suggestion': '可深入',
    },
    'replies': {
      'extend': 'a',
      'resonate': 'b',
      'tease': 'c',
      'humor': 'd',
      'coldRead': 'e',
    },
    'recommendation': {
      'pick': 'tease',
      'content': 'c',
      'reason': 'r',
      'psychology': 'p',
    },
    'reminder': '記得用你的方式說',
    // Intentionally omit 'usage' so _syncSubscriptionUsageFromResult early-
    // returns and the test doesn't have to wire a subscriptionProvider stub.
  };
}

Conversation _conversation({
  String? lastAnalysisSnapshotJson,
  int? lastAnalyzedMessageCount,
  int? lastEnthusiasmScore,
  List<Message>? extraMessages,
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
      ...?extraMessages,
    ],
    createdAt: DateTime(2026, 5, 28, 12),
    updatedAt: DateTime(2026, 5, 28, 12),
    lastAnalysisSnapshotJson: lastAnalysisSnapshotJson,
    lastAnalyzedMessageCount: lastAnalyzedMessageCount,
    lastEnthusiasmScore: lastEnthusiasmScore,
  );
}

/// Stub repository so `_restorePersistedAnalysis()` and
/// `_persistLatestAnalysisSnapshot()` flow through a controllable source.
/// Records `updateConversation` calls so P2 idempotency tests can assert
/// whether persist actually ran on hydrate.
class _StubConversationRepository extends ConversationRepository {
  _StubConversationRepository(this._conversation);

  Conversation _conversation;
  int updateCalls = 0;
  Conversation? lastSaved;

  @override
  Conversation? getConversation(String id) {
    if (id != _conversation.id) return null;
    return _conversation;
  }

  @override
  Future<void> updateConversation(Conversation c) async {
    updateCalls++;
    lastSaved = c;
    _conversation = c;
  }
}

/// Old-run analysis snapshot used to seed `lastAnalysisSnapshotJson` so
/// `_restorePersistedAnalysis()` populates `_enthusiasmScore` etc. The
/// numbers/labels intentionally differ from `_full()` so a stale value
/// would be visually distinguishable from a freshly hydrated full result.
Map<String, dynamic> _staleSnapshotJson() {
  return <String, dynamic>{
    'enthusiasm': {'score': 33},
    'strategy': '舊策略：保守',
    'gameStage': {
      'current': 'opening',
      'status': 'normal',
      'nextStep': '舊 next step',
    },
    'psychology': {
      'subtext': '舊推論',
      'qualificationSignal': false,
    },
    'topicDepth': {
      'current': 'small_talk',
      'suggestion': '舊 suggestion',
    },
    'replies': {
      'extend': '舊 extend',
      'resonate': '舊 resonate',
      'tease': '舊 tease',
      'humor': '舊 humor',
      'coldRead': '舊 coldRead',
    },
    'recommendation': {
      'pick': 'extend',
      'content': '舊建議內容',
      'reason': '舊理由',
      'psychology': '舊心理',
    },
    'reminder': '舊提醒',
  };
}

Future<_RecordingAnalysisService> _pumpHydratedAnalysisScreen(
  WidgetTester tester, {
  required StreamingAnalysisState seed,
}) async {
  return (await _pumpHydratedAnalysisScreenWithRepo(
    tester,
    seed: seed,
    conversation: _conversation(),
  ))
      .recorder;
}

class _HydrationHarness {
  _HydrationHarness({required this.recorder, required this.repo});
  final _RecordingAnalysisService recorder;
  final _StubConversationRepository repo;
}

class _MutableHydrationHarness extends _HydrationHarness {
  _MutableHydrationHarness({
    required super.recorder,
    required super.repo,
    required this.notifier,
  });

  final _MutableStreamingAnalyzeNotifier notifier;
}

Future<_HydrationHarness> _pumpHydratedAnalysisScreenWithRepo(
  WidgetTester tester, {
  required StreamingAnalysisState seed,
  required Conversation conversation,
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final recorder = _RecordingAnalysisService();
  final repo = _StubConversationRepository(conversation);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        conversationRepositoryProvider.overrideWithValue(repo),
        conversationProvider(_conversationId).overrideWithValue(conversation),
        analysisServiceProvider.overrideWithValue(recorder),
        streamingAnalyzeProvider
            .overrideWith(() => _SeededStreamingAnalyzeNotifier(seed)),
      ],
      child: const MaterialApp(
        home: AnalysisScreen(conversationId: _conversationId),
      ),
    ),
  );
  // Let initState's post-frame hydration callback land.
  await tester.pump();
  await tester.pump();
  return _HydrationHarness(recorder: recorder, repo: repo);
}

Future<_MutableHydrationHarness> _pumpMutableAnalysisScreenWithRepo(
  WidgetTester tester, {
  required StreamingAnalysisState seed,
  required Conversation conversation,
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final recorder = _RecordingAnalysisService();
  final repo = _StubConversationRepository(conversation);
  late final _MutableStreamingAnalyzeNotifier notifier;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        conversationRepositoryProvider.overrideWithValue(repo),
        conversationProvider(_conversationId).overrideWithValue(conversation),
        analysisServiceProvider.overrideWithValue(recorder),
        streamingAnalyzeProvider.overrideWith(() {
          notifier = _MutableStreamingAnalyzeNotifier(seed);
          return notifier;
        }),
      ],
      child: const MaterialApp(
        home: AnalysisScreen(conversationId: _conversationId),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return _MutableHydrationHarness(
    recorder: recorder,
    repo: repo,
    notifier: notifier,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AnalysisScreen hydration on remount (P1)', () {
    testWidgets(
      'recommendationReady state hydrates → streaming loader, no analyze re-fire',
      (tester) async {
        final recorder = await _pumpHydratedAnalysisScreen(
          tester,
          seed: StreamingAnalysisState(
            phase: StreamingAnalyzePhase.recommendationReady,
            recommendationPreview: _preview(runId: 'run_qr'),
            analysisRunId: 'run_qr',
          ),
        );

        expect(find.text('聽起來累，要不要週末喝杯咖啡？'), findsNothing);
        expect(find.byType(StreamingAnalysisLoader), findsOneWidget);
        expect(find.byType(CoachActionCard), findsNothing);
        expect(find.byType(FullAnalysisPlaceholder), findsNothing);
        expect(find.byType(FullAnalysisRetryCard), findsNothing);
        expect(find.byType(ImagePickerWidget), findsNothing,
            reason:
                'A hydrated full-streaming run must not re-open the pre-analysis upload card.');
        expect(recorder.recommendationPreviewCalls, 0,
            reason: 'I-P1-a: must not re-fire analyzeQuick on hydration');
        expect(recorder.fullCalls, 0);
      },
    );

    testWidgets(
      'streamingReport state hydrates → streaming loader visible',
      (tester) async {
        final recorder = await _pumpHydratedAnalysisScreen(
          tester,
          seed: StreamingAnalysisState(
            phase: StreamingAnalyzePhase.streamingReport,
            recommendationPreview: _preview(runId: 'run_rf'),
            analysisRunId: 'run_rf',
          ),
        );

        expect(find.text('聽起來累，要不要週末喝杯咖啡？'), findsNothing);
        expect(find.byType(StreamingAnalysisLoader), findsOneWidget);
        expect(find.byType(CoachActionCard), findsNothing);
        expect(find.byType(FullAnalysisPlaceholder), findsNothing);
        expect(find.byType(FullAnalysisRetryCard), findsNothing);
        expect(find.byType(ImagePickerWidget), findsNothing,
            reason:
                'Running full analysis should show streaming progress, not the upload/start-analysis card.');
        expect(find.text('建立這段對話'), findsNothing);
        expect(find.text('貼上或輸入新的一則訊息...'), findsNothing,
            reason:
                'Manual composer should collapse while full analysis is streaming so it does not cover the result area.');
        expect(recorder.recommendationPreviewCalls, 0);
        expect(recorder.fullCalls, 0);
      },
    );

    testWidgets(
      'failedAfterRecommendation state hydrates → retry card with retry count',
      (tester) async {
        final recorder = await _pumpHydratedAnalysisScreen(
          tester,
          seed: StreamingAnalysisState(
            phase: StreamingAnalyzePhase.failedAfterRecommendation,
            recommendationPreview: _preview(runId: 'run_ff'),
            analysisRunId: 'run_ff',
            fullErrorMessage: '完整分析失敗，可以重試。',
            fullErrorCode: 'FULL_FAILED',
            retriesRemaining: 2,
          ),
        );

        expect(find.text('聽起來累，要不要週末喝杯咖啡？'), findsNothing);
        expect(find.byType(CoachActionCard), findsNothing);
        expect(find.byType(FullAnalysisRetryCard), findsOneWidget);
        expect(find.byType(FullAnalysisPlaceholder), findsNothing);
        expect(find.byType(ImagePickerWidget), findsNothing,
            reason:
                'Full retry state should not insert the upload/start-analysis card above retry.');
        expect(recorder.recommendationPreviewCalls, 0);
        expect(recorder.fullCalls, 0);
      },
    );

    testWidgets(
      'done state hydrates → detailed analysis gate flips, no analyze re-fire',
      (tester) async {
        final recorder = await _pumpHydratedAnalysisScreen(
          tester,
          seed: StreamingAnalysisState(
            phase: StreamingAnalyzePhase.done,
            recommendationPreview: _preview(runId: 'run_fr'),
            full: _full(),
            analysisRunId: 'run_fr',
          ),
        );

        // The detailed-analysis tree contains widgets (CoachChatCard) that
        // depend on a live Hive box, which is not initialised in this widget
        // test. Drain the expected Hive build exception so the test framework
        // does not flag it.
        // ignore: avoid_dynamic_calls
        tester.takeException();
        expect(find.text('1 快速建議（先回來的版本）'), findsNothing);
        expect(find.text('2 完整分析後建議'), findsNothing);
        expect(find.text('聽起來累，要不要週末喝杯咖啡？'), findsNothing);
        expect(find.text('Core / Full 回覆對照'), findsNothing);
        expect(find.text('Core 先行'), findsNothing);
        expect(find.text('Full 原始判斷'), findsNothing);
        expect(find.text('完整分析推薦回覆'), findsNothing);
        expect(find.text('AI 推薦回覆'), findsOneWidget);
        expect(find.byType(FullAnalysisPlaceholder), findsNothing);
        expect(find.byType(FullAnalysisRetryCard), findsNothing);
        expect(recorder.recommendationPreviewCalls, 0);
        expect(recorder.fullCalls, 0);
      },
    );

    testWidgets(
      'live streamingReport to done does not render rollback preview/Core comparison',
      (tester) async {
        final recommendationPreview = _preview(runId: 'run_live_compare');
        final raw = _fullRawResponse();
        final conv = _conversation();

        final harness = await _pumpMutableAnalysisScreenWithRepo(
          tester,
          seed: StreamingAnalysisState(
            phase: StreamingAnalyzePhase.streamingReport,
            recommendationPreview: recommendationPreview,
            analysisRunId: recommendationPreview.analysisRunId,
            conversationMessageCount: conv.messages.length,
          ),
          conversation: conv,
        );

        expect(find.byType(StreamingAnalysisLoader), findsOneWidget);
        expect(find.byType(FullAnalysisPlaceholder), findsNothing);

        harness.notifier.emit(
          StreamingAnalysisState(
            phase: StreamingAnalyzePhase.done,
            recommendationPreview: recommendationPreview,
            full: _fullWithRawResponse(raw),
            analysisRunId: recommendationPreview.analysisRunId,
            conversationMessageCount: conv.messages.length,
          ),
        );
        await tester.pump();

        // Drain the expected Hive build exception from the detailed tree.
        // ignore: avoid_dynamic_calls
        tester.takeException();

        expect(find.text('2 完整分析後建議'), findsNothing);
        expect(find.text('Core / Full 回覆對照'), findsNothing);
        expect(find.text('Core 先行'), findsNothing);
        expect(find.text('Full 原始判斷'), findsNothing);
        expect(find.text(recommendationPreview.recommendedReply), findsNothing);
        expect(find.text('AI 推薦回覆'), findsOneWidget);
        expect(find.byType(FullAnalysisPlaceholder), findsNothing);
        expect(harness.recorder.recommendationPreviewCalls, 0);
        expect(harness.recorder.fullCalls, 0);
      },
    );
  });

  // Codex round-2 P1: when a conversation already has a persisted detailed
  // analysis (`lastAnalysisSnapshotJson`), `_restorePersistedAnalysis()` seeds
  // `_enthusiasmScore` and the rest of the detailed-analysis local mirrors in
  // initState. If hydration of a *partial* streaming phase (recommendationReady /
  // streamingReport / failedAfterRecommendation / failedBeforeRecommendation) doesn't clear those mirrors, the
  // build tree keeps showing the stale detailed analysis on top of (or instead
  // of) the live streaming loader / retry state. I-P1-c.
  group(
    'AnalysisScreen hydration with stale persisted snapshot (Codex round-2 P1)',
    () {
      testWidgets(
        'recommendationReady hydrate over stale snapshot → streaming loader, no stale detailed analysis',
        (tester) async {
          final convWithStaleSnapshot = _conversation(
            lastAnalysisSnapshotJson: jsonEncode(_staleSnapshotJson()),
            lastAnalyzedMessageCount: 1,
            lastEnthusiasmScore: 33,
          );

          final harness = await _pumpHydratedAnalysisScreenWithRepo(
            tester,
            seed: StreamingAnalysisState(
              phase: StreamingAnalyzePhase.recommendationReady,
              recommendationPreview: _preview(runId: 'run_qr_stale'),
              analysisRunId: 'run_qr_stale',
            ),
            conversation: convWithStaleSnapshot,
          );

          expect(find.text('聽起來累，要不要週末喝杯咖啡？'), findsNothing);
          expect(find.byType(StreamingAnalysisLoader), findsOneWidget);
          expect(find.byType(CoachActionCard), findsNothing);
          expect(find.byType(FullAnalysisPlaceholder), findsNothing,
              reason:
                  'I-P1-c: stale _enthusiasmScore from persisted snapshot must be cleared so the render tree flips to streaming.');
          expect(find.byType(FullAnalysisRetryCard), findsNothing);
          // Stale detailed copy must not bleed through.
          expect(find.text('舊建議內容'), findsNothing);
          expect(find.text('舊策略：保守'), findsNothing);
          expect(harness.recorder.recommendationPreviewCalls, 0);
          expect(harness.recorder.fullCalls, 0);
        },
      );

      testWidgets(
        'streamingReport hydrate over stale snapshot → streaming loader, no stale detailed analysis',
        (tester) async {
          final convWithStaleSnapshot = _conversation(
            lastAnalysisSnapshotJson: jsonEncode(_staleSnapshotJson()),
            lastAnalyzedMessageCount: 1,
            lastEnthusiasmScore: 33,
          );

          final harness = await _pumpHydratedAnalysisScreenWithRepo(
            tester,
            seed: StreamingAnalysisState(
              phase: StreamingAnalyzePhase.streamingReport,
              recommendationPreview: _preview(runId: 'run_rf_stale'),
              analysisRunId: 'run_rf_stale',
            ),
            conversation: convWithStaleSnapshot,
          );

          expect(find.text('聽起來累，要不要週末喝杯咖啡？'), findsNothing);
          expect(find.byType(StreamingAnalysisLoader), findsOneWidget);
          expect(find.byType(CoachActionCard), findsNothing);
          expect(find.byType(FullAnalysisPlaceholder), findsNothing);
          expect(find.byType(FullAnalysisRetryCard), findsNothing);
          expect(find.text('舊建議內容'), findsNothing);
          expect(harness.recorder.recommendationPreviewCalls, 0);
          expect(harness.recorder.fullCalls, 0);
        },
      );

      testWidgets(
        'failedAfterRecommendation hydrate over stale snapshot → retry card, no stale detailed analysis',
        (tester) async {
          final convWithStaleSnapshot = _conversation(
            lastAnalysisSnapshotJson: jsonEncode(_staleSnapshotJson()),
            lastAnalyzedMessageCount: 1,
            lastEnthusiasmScore: 33,
          );

          final harness = await _pumpHydratedAnalysisScreenWithRepo(
            tester,
            seed: StreamingAnalysisState(
              phase: StreamingAnalyzePhase.failedAfterRecommendation,
              recommendationPreview: _preview(runId: 'run_ff_stale'),
              analysisRunId: 'run_ff_stale',
              fullErrorMessage: '完整分析失敗，可以重試。',
              fullErrorCode: 'FULL_FAILED',
              retriesRemaining: 2,
            ),
            conversation: convWithStaleSnapshot,
          );

          expect(find.text('聽起來累，要不要週末喝杯咖啡？'), findsNothing);
          expect(find.byType(CoachActionCard), findsNothing);
          expect(find.byType(FullAnalysisRetryCard), findsOneWidget);
          expect(find.byType(FullAnalysisPlaceholder), findsNothing);
          expect(find.text('舊建議內容'), findsNothing);
          expect(harness.recorder.recommendationPreviewCalls, 0);
          expect(harness.recorder.fullCalls, 0);
        },
      );
    },
  );

  // Codex round-2 P2: if full completes while the user is off-screen, the
  // `_onStreamingAnalyzeStateChanged` listener never fires for done. Until the
  // P2 fix, `_hydrateStreamingAnalyzeState(done)` applied the result but
  // intentionally skipped `_persistLatestAnalysisSnapshot` +
  // `_syncSubscriptionUsageFromResult` on the theory that the live listener
  // already ran them — false for off-screen completion. I-P2-e/f.
  group(
    'AnalysisScreen done hydrate persists when listener missed it (Codex round-2 P2)',
    () {
      testWidgets(
        'off-screen completion (no matching snapshot) → hydrate persists + updates conv snapshot',
        (tester) async {
          final raw = _fullRawResponse();
          // No prior snapshot, listener never ran for this run.
          final conv = _conversation();

          final harness = await _pumpHydratedAnalysisScreenWithRepo(
            tester,
            seed: StreamingAnalysisState(
              phase: StreamingAnalyzePhase.done,
              recommendationPreview: _preview(runId: 'run_off_screen'),
              full: _fullWithRawResponse(raw),
              analysisRunId: 'run_off_screen',
            ),
            conversation: conv,
          );

          // Drain expected Hive build error from the detailed-analysis tree —
          // same workaround as the existing done hydration test.
          // ignore: avoid_dynamic_calls
          tester.takeException();
          // Let the fire-and-forget save() future land.
          await tester.pump(const Duration(milliseconds: 1));

          expect(harness.repo.updateCalls, 1,
              reason:
                  'I-P2-e: off-screen done completion must persist the snapshot on hydrate; listener missed it.');
          expect(harness.repo.lastSaved?.lastAnalysisSnapshotJson,
              jsonEncode(raw));
          expect(harness.repo.lastSaved?.lastAnalyzedMessageCount,
              conv.messages.length);
          expect(harness.repo.lastSaved?.lastEnthusiasmScore, 72);
        },
      );

      testWidgets(
        'listener already persisted matching snapshot → hydrate must not double-write',
        (tester) async {
          final raw = _fullRawResponse();
          // Listener already ran during the original recommendationReady→done
          // transition, persisted the snapshot, then user navigated away and
          // came back. Snapshot equality must short-circuit hydrate persist.
          final conv = _conversation(
            lastAnalysisSnapshotJson: jsonEncode(raw),
            lastAnalyzedMessageCount: 1,
            lastEnthusiasmScore: 72,
          );

          final harness = await _pumpHydratedAnalysisScreenWithRepo(
            tester,
            seed: StreamingAnalysisState(
              phase: StreamingAnalyzePhase.done,
              recommendationPreview: _preview(runId: 'run_already_persisted'),
              full: _fullWithRawResponse(raw),
              analysisRunId: 'run_already_persisted',
            ),
            conversation: conv,
          );

          // ignore: avoid_dynamic_calls
          tester.takeException();
          await tester.pump(const Duration(milliseconds: 1));

          expect(harness.repo.updateCalls, 0,
              reason:
                  'I-P2-f: when conv snapshot already matches result, hydrate must skip persist to avoid double-write.');
        },
      );

      testWidgets(
        'stale snapshot from a prior run does not count as matching → hydrate still persists',
        (tester) async {
          final raw = _fullRawResponse();
          // Snapshot exists but it's from a different (older) run.
          final conv = _conversation(
            lastAnalysisSnapshotJson: jsonEncode(_staleSnapshotJson()),
            lastAnalyzedMessageCount: 1,
            lastEnthusiasmScore: 33,
          );

          final harness = await _pumpHydratedAnalysisScreenWithRepo(
            tester,
            seed: StreamingAnalysisState(
              phase: StreamingAnalyzePhase.done,
              recommendationPreview: _preview(runId: 'run_after_stale'),
              full: _fullWithRawResponse(raw),
              analysisRunId: 'run_after_stale',
            ),
            conversation: conv,
          );

          // ignore: avoid_dynamic_calls
          tester.takeException();
          await tester.pump(const Duration(milliseconds: 1));

          expect(harness.repo.updateCalls, 1,
              reason:
                  'I-P2-e: stale snapshot from a prior run must not be treated as matching; persist must run.');
          expect(harness.repo.lastSaved?.lastAnalysisSnapshotJson,
              jsonEncode(raw));
        },
      );
    },
  );

  group('AnalysisScreen streaming stale result guard for newly added messages',
      () {
    testWidgets(
      'done for an older message count shows stale-result retry and skips stale persist',
      (tester) async {
        final raw = _fullRawResponse();
        final conversationWithNewMessage = _conversation(
          lastAnalysisSnapshotJson: jsonEncode(_staleSnapshotJson()),
          lastAnalyzedMessageCount: 1,
          lastEnthusiasmScore: 33,
          extraMessages: [
            Message(
              id: 'm2',
              content: '我剛剛回她了',
              isFromMe: true,
              timestamp: DateTime(2026, 5, 28, 12, 1),
            ),
          ],
        );

        final harness = await _pumpHydratedAnalysisScreenWithRepo(
          tester,
          seed: StreamingAnalysisState(
            phase: StreamingAnalyzePhase.done,
            recommendationPreview: _preview(runId: 'run_stale_message_count'),
            full: _fullWithRawResponse(raw),
            analysisRunId: 'run_stale_message_count',
            conversationMessageCount: 1,
          ),
          conversation: conversationWithNewMessage,
        );

        expect(find.byType(CoachActionCard), findsNothing);
        expect(find.byType(FullAnalysisRetryCard), findsOneWidget,
            reason:
                'Older full result must not render as the current detailed report after the user adds messages.');
        expect(find.byType(FullAnalysisPlaceholder), findsNothing);
        expect(harness.repo.updateCalls, 0,
            reason:
                'Stale full result must not persist or advance analyzed count.');
        expect(harness.recorder.recommendationPreviewCalls, 0);
        expect(harness.recorder.fullCalls, 0);
      },
    );
  });
}
