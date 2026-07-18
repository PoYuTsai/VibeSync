import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis_history/domain/entities/analysis_history_event.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/report/data/providers/report_providers.dart';
import 'package:vibesync/features/report/domain/entities/report_models.dart';
import 'package:vibesync/features/report/presentation/screens/my_report_screen.dart';
import 'package:vibesync/features/report/presentation/widgets/heat_trend_chart.dart';
import 'package:vibesync/features/report/presentation/widgets/practice_temperature_chart.dart';
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
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        subscriptionProvider.overrideWith((ref) => _PaidSubscription()),
        reportDataProvider.overrideWithValue(report),
        analysisHistoryEventsProvider.overrideWithValue(events),
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
    expect(chart.averageScore, 55);
    expect(chart.scoreDelta, 26);
    expect(chart.sampleCount, 2);
    expect(find.text('近期平均 55'), findsOneWidget);
    expect(find.text('小雲'), findsWidgets);
    expect(find.text('還沒有分析數據'), findsNothing);
  });

  testWidgets('舊用戶沒有事件時不把缺資料顯示成平均 0', (tester) async {
    await _pump(tester, const [], report: _legacyConversationReport);

    expect(find.text('等待趨勢資料'), findsOneWidget);
    expect(find.text('全部平均 0'), findsNothing);
    expect(find.text('再多分析幾次，就能比較對方每次互動的投入度'), findsOneWidget);
  });
}
