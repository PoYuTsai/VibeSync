import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis_history/domain/entities/analysis_history_event.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_providers.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/report/data/providers/report_providers.dart';
import 'package:vibesync/features/report/domain/entities/report_models.dart';
import 'package:vibesync/features/report/presentation/screens/my_report_screen.dart';
import 'package:vibesync/features/report/presentation/widgets/heat_trend_chart.dart';
import 'package:vibesync/features/report/presentation/widgets/practice_temperature_chart.dart';
import 'package:vibesync/features/report/presentation/widgets/report_subject_selector.dart';
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_tier_helper.dart';
import 'package:vibesync/features/user_profile/data/providers/user_profile_providers.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';

class _PaidSubscription extends SubscriptionNotifier {
  _PaidSubscription() {
    state = const SubscriptionState(tier: SubscriptionTierHelper.starter);
  }
}

class _NullProfile extends UserProfileController {
  @override
  Future<UserProfile?> build() async => null;
}

const _emptyReport = ReportData(
  trendPoints: [],
  averageScore: 0,
  scoreDelta: 0,
  comparisons: [],
  stageDistributions: [],
  totalConversations: 0,
);

const _legacyConversationReport = ReportData(
  trendPoints: [],
  averageScore: 63,
  scoreDelta: 6,
  comparisons: [ConversationComparison(name: '小雲', score: 63)],
  stageDistributions: [StageDistribution(stageName: '升溫', count: 1)],
  totalConversations: 1,
);

Future<void> _pump(
  WidgetTester tester,
  List<AnalysisHistoryEvent> events, {
  ReportData report = _emptyReport,
  List<Conversation> conversations = const [],
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        subscriptionProvider.overrideWith((ref) => _PaidSubscription()),
        reportDataProvider.overrideWithValue(report),
        analysisHistoryEventsProvider.overrideWithValue(events),
        conversationsProvider.overrideWithValue(conversations),
        partnerListProvider.overrideWithValue(const []),
        userProfileControllerProvider.overrideWith(_NullProfile.new),
      ],
      child: const MaterialApp(home: Scaffold(body: MyReportScreen())),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('只有練習歷史也會顯示報告，不被 Conversation 空清單吃掉', (tester) async {
    await _pump(tester, [
      AnalysisHistoryEvent.practice(
        id: 'p1',
        createdAt: DateTime(2026, 7, 1),
        profileId: 'practice_girl_001',
        roundIndex: 1,
        temperatureScore: 38,
      ),
      AnalysisHistoryEvent.practice(
        id: 'p2',
        createdAt: DateTime(2026, 7, 3),
        profileId: 'practice_girl_001',
        roundIndex: 2,
        temperatureScore: 55,
      ),
    ]);

    expect(find.text('把互動變化看懂'), findsOneWidget);
    expect(find.byType(PracticeTemperatureChart), findsOneWidget);
    expect(find.text('還沒有分析數據'), findsNothing);
    expect(find.byType(HeatTrendChart), findsNothing);
  });

  testWidgets('只有 analyze 歷史也能進入單一對象趨勢', (tester) async {
    await _pump(tester, [
      AnalysisHistoryEvent.analyze(
        id: 'a1',
        createdAt: DateTime(2026, 7, 1),
        conversationId: 'c1',
        subjectName: '小雲',
        enthusiasmScore: 42,
        gameStageLabel: 'opening',
      ),
      AnalysisHistoryEvent.analyze(
        id: 'a2',
        createdAt: DateTime(2026, 7, 3),
        conversationId: 'c1',
        subjectName: '小雲',
        enthusiasmScore: 68,
        gameStageLabel: 'premise',
      ),
    ]);

    final chart = tester.widget<HeatTrendChart>(find.byType(HeatTrendChart));
    expect(chart.trendPoints.map((p) => p.score), [42, 68]);
    // 平均、較上次、筆數由 chart 從同一份點列自己算。
    expect(find.text('這 2 次平均 55 / 90'), findsOneWidget);
    expect(find.text('較上次 +26'), findsOneWidget);
    expect(find.text('最近 2 筆分析'), findsOneWidget);
    expect(find.text('小雲'), findsOneWidget);
    expect(find.byType(ReportSubjectSelector), findsNothing);
    expect(find.text('還沒有分析數據'), findsNothing);
  });

  testWidgets('對象只用新版分析過：不叫他再多分析幾次', (tester) async {
    await _pump(tester, [
      AnalysisHistoryEvent.analyze(
        id: 'a1',
        createdAt: DateTime(2026, 10, 18),
        conversationId: 'c1',
        subjectName: '小雲',
      ),
    ]);

    expect(find.text('新版分析看的是每次的燈號，不算投入度分數。'), findsOneWidget);
    expect(find.text('再多分析幾次，就能比較對方每次互動的投入度'), findsNothing);
    // 沒有點時不放「只有舊版紀錄」的補充。
    expect(find.text('新版分析不算投入度分數，這裡只有舊版分析的紀錄。'), findsNothing);
  });

  testWidgets('舊版有一筆、之後改用新版：不說再分析 1 次就有趨勢', (tester) async {
    await _pump(tester, [
      AnalysisHistoryEvent.analyze(
        id: 'a1',
        createdAt: DateTime(2026, 10, 1),
        conversationId: 'c1',
        subjectName: '小雲',
        enthusiasmScore: 61,
        gameStageLabel: 'premise',
      ),
      AnalysisHistoryEvent.analyze(
        id: 'a2',
        createdAt: DateTime(2026, 10, 18),
        conversationId: 'c1',
        subjectName: '小雲',
      ),
    ]);

    final chart = tester.widget<HeatTrendChart>(find.byType(HeatTrendChart));
    expect(chart.trendPoints.map((p) => p.score), [61]);
    expect(find.text('再分析 1 次就能形成趨勢'), findsNothing);
    expect(find.text('新版分析不算投入度分數，這裡只有舊版分析的紀錄。'), findsOneWidget);
  });

  testWidgets('多個舊點、其中一段用 v3 重跑（沿用舊日期）：留舊點、加補充', (tester) async {
    Conversation conversation(String id, {String? snapshotJson}) =>
        Conversation(
          id: id,
          name: '小雲',
          messages: const [],
          createdAt: DateTime(2026, 9, 1),
          updatedAt: DateTime(2026, 10, 18),
          partnerId: 'p1',
          lastAnalysisSnapshotJson: snapshotJson,
        );

    await _pump(
      tester,
      [
        // c1 10/1 的事件被 v3 重跑覆寫：日期留著、分數變空。
        AnalysisHistoryEvent.analyze(
          id: 'a1',
          createdAt: DateTime(2026, 10, 1),
          conversationId: 'c1',
          subjectName: '小雲',
        ),
        AnalysisHistoryEvent.analyze(
          id: 'a2',
          createdAt: DateTime(2026, 10, 2),
          conversationId: 'c2',
          subjectName: '小雲',
          enthusiasmScore: 70,
          gameStageLabel: 'premise',
        ),
        AnalysisHistoryEvent.analyze(
          id: 'a3',
          createdAt: DateTime(2026, 10, 5),
          conversationId: 'c2',
          subjectName: '小雲',
          enthusiasmScore: 65,
          gameStageLabel: 'premise',
        ),
      ],
      conversations: [
        conversation(
          'c1',
          snapshotJson: jsonEncode({
            'guideVersion': 'v3.5',
            'read': {'light': 'green', 'decision': 'send'},
            'cards': const [],
          }),
        ),
        conversation('c2'),
      ],
    );

    final chart = tester.widget<HeatTrendChart>(find.byType(HeatTrendChart));
    expect(chart.trendPoints.map((p) => p.score), [70, 65]);
    expect(find.text('再分析 1 次就能形成趨勢'), findsNothing);
    expect(find.text('新版分析不算投入度分數，這裡只有舊版分析的紀錄。'), findsOneWidget);
  });

  testWidgets('新版之後又有舊版分數（舊 App）：照舊顯示提示', (tester) async {
    await _pump(tester, [
      AnalysisHistoryEvent.analyze(
        id: 'a1',
        createdAt: DateTime(2026, 10, 1),
        conversationId: 'c1',
        subjectName: '小雲',
      ),
      AnalysisHistoryEvent.analyze(
        id: 'a2',
        createdAt: DateTime(2026, 10, 18),
        conversationId: 'c1',
        subjectName: '小雲',
        enthusiasmScore: 61,
        gameStageLabel: 'premise',
      ),
    ]);

    expect(find.text('再分析 1 次就能形成趨勢'), findsOneWidget);
    expect(find.text('新版分析不算投入度分數，這裡只有舊版分析的紀錄。'), findsNothing);
  });

  testWidgets('舊用戶沒有事件時不把缺資料顯示成平均 0', (tester) async {
    await _pump(tester, const [], report: _legacyConversationReport);

    expect(find.textContaining('次平均'), findsNothing);
    expect(find.textContaining('較上次'), findsNothing);
    expect(find.text('再多分析幾次，就能比較對方每次互動的投入度'), findsOneWidget);
  });
}
