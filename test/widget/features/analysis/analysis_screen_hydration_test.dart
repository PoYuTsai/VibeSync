import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/features/analysis/data/notifiers/two_stage_analyze_notifier.dart';
import 'package:vibesync/features/analysis/data/providers/analysis_providers.dart';
import 'package:vibesync/features/analysis/data/services/analysis_service.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_models.dart';
import 'package:vibesync/features/analysis/domain/entities/game_stage.dart';
import 'package:vibesync/features/analysis/domain/entities/quick_analysis_result.dart';
import 'package:vibesync/features/analysis/presentation/screens/analysis_screen.dart';
import 'package:vibesync/features/analysis/presentation/widgets/two_stage_loading_widgets.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_providers.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/features/conversation/domain/entities/session_context.dart';

const _conversationId = 'hydration-test';

/// Notifier that starts in a pre-seeded state, simulating a remount of
/// AnalysisScreen onto an already-running provider. Critically, [build] is the
/// override hook for the initial state — no analyze calls are needed to land
/// the screen in the target phase.
class _SeededTwoStageNotifier extends TwoStageAnalyzeNotifier {
  _SeededTwoStageNotifier(this.seed);
  final TwoStageAnalysisState seed;

  @override
  TwoStageAnalysisState build(String conversationId) => seed;
}

/// Records any call to analyzeQuick/analyzeFull so tests can assert the
/// screen did not re-trigger an analyze after hydrating.
class _RecordingAnalysisService extends AnalysisService {
  int quickCalls = 0;
  int fullCalls = 0;

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
    quickCalls++;
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

QuickAnalysisResult _quick({
  String runId = 'run_hydrate',
  int? eta = 17,
}) {
  return QuickAnalysisResult(
    analysisRunId: runId,
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
    reminder: '記得用你的方式說',
  );
}

Conversation _conversation() {
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
  );
}

Future<_RecordingAnalysisService> _pumpHydratedAnalysisScreen(
  WidgetTester tester, {
  required TwoStageAnalysisState seed,
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final recorder = _RecordingAnalysisService();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        conversationProvider(_conversationId).overrideWithValue(_conversation()),
        analysisServiceProvider.overrideWithValue(recorder),
        twoStageAnalyzeProvider
            .overrideWith(() => _SeededTwoStageNotifier(seed)),
      ],
      child: const MaterialApp(
        home: AnalysisScreen(conversationId: _conversationId),
      ),
    ),
  );
  // Let initState's post-frame hydration callback land.
  await tester.pump();
  await tester.pump();
  return recorder;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AnalysisScreen hydration on remount (P1)', () {
    testWidgets(
      'quickReady state hydrates → quick summary + full placeholder, no analyze re-fire',
      (tester) async {
        final recorder = await _pumpHydratedAnalysisScreen(
          tester,
          seed: TwoStageAnalysisState(
            phase: TwoStagePhase.quickReady,
            quick: _quick(runId: 'run_qr'),
            analysisRunId: 'run_qr',
          ),
        );

        expect(find.text('聽起來累，要不要週末喝杯咖啡？'), findsOneWidget);
        expect(find.byType(FullAnalysisPlaceholder), findsOneWidget);
        expect(find.byType(FullAnalysisRetryCard), findsNothing);
        expect(recorder.quickCalls, 0,
            reason: 'I-P1-a: must not re-fire analyzeQuick on hydration');
        expect(recorder.fullCalls, 0);
      },
    );

    testWidgets(
      'runningFull state hydrates → quick summary + placeholder visible',
      (tester) async {
        final recorder = await _pumpHydratedAnalysisScreen(
          tester,
          seed: TwoStageAnalysisState(
            phase: TwoStagePhase.runningFull,
            quick: _quick(runId: 'run_rf'),
            analysisRunId: 'run_rf',
          ),
        );

        expect(find.text('聽起來累，要不要週末喝杯咖啡？'), findsOneWidget);
        expect(find.byType(FullAnalysisPlaceholder), findsOneWidget);
        expect(find.byType(FullAnalysisRetryCard), findsNothing);
        expect(recorder.quickCalls, 0);
        expect(recorder.fullCalls, 0);
      },
    );

    testWidgets(
      'fullFailed state hydrates → quick summary + retry card with retry count',
      (tester) async {
        final recorder = await _pumpHydratedAnalysisScreen(
          tester,
          seed: TwoStageAnalysisState(
            phase: TwoStagePhase.fullFailed,
            quick: _quick(runId: 'run_ff'),
            analysisRunId: 'run_ff',
            fullErrorMessage: '完整分析失敗，可以重試。',
            fullErrorCode: 'FULL_FAILED',
            retriesRemaining: 2,
          ),
        );

        expect(find.text('聽起來累，要不要週末喝杯咖啡？'), findsOneWidget);
        expect(find.byType(FullAnalysisRetryCard), findsOneWidget);
        expect(find.byType(FullAnalysisPlaceholder), findsNothing);
        expect(recorder.quickCalls, 0);
        expect(recorder.fullCalls, 0);
      },
    );

    testWidgets(
      'fullReady state hydrates → detailed analysis gate flips, no analyze re-fire',
      (tester) async {
        final recorder = await _pumpHydratedAnalysisScreen(
          tester,
          seed: TwoStageAnalysisState(
            phase: TwoStagePhase.fullReady,
            quick: _quick(runId: 'run_fr'),
            full: _full(),
            analysisRunId: 'run_fr',
          ),
        );

        // The detailed-analysis tree contains widgets (CoachChatCard) that
        // depend on a live Hive box, which is not initialised in this widget
        // test. The hydration we care about is the gate flip:
        //   _quickResult != null && _enthusiasmScore == null → placeholder/retry
        //   _enthusiasmScore != null → detailed-analysis tree (Hive-dependent)
        // Asserting placeholder/retry are absent proves _enthusiasmScore is set
        // and therefore hydration applied the full result. Drain the expected
        // Hive build exception so the test framework does not flag it.
        // ignore: avoid_dynamic_calls
        tester.takeException();
        expect(find.byType(FullAnalysisPlaceholder), findsNothing);
        expect(find.byType(FullAnalysisRetryCard), findsNothing);
        expect(recorder.quickCalls, 0);
        expect(recorder.fullCalls, 0);
      },
    );
  });
}
