// test/widget/features/report/my_report_screen_test.dart
//
// 決策 A 守門（regression guard）：報告頁的「對象作戰板」section 全 tier 可見，
// 與上方報告 Free gating 互不影響。
// - Free + 1 對象 → 鎖卡（既有 gating）與作戰板 section 必須同時 render。
// - 付費 + 有數據 → 三張圖與作戰板 section 必須同時 render。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis_history/domain/entities/analysis_history_event.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/report/data/providers/report_providers.dart';
import 'package:vibesync/features/report/domain/entities/report_models.dart';
import 'package:vibesync/features/report/presentation/screens/my_report_screen.dart';
import 'package:vibesync/features/report/presentation/widgets/conversation_comparison_chart.dart';
import 'package:vibesync/features/report/presentation/widgets/heat_trend_chart.dart';
import 'package:vibesync/features/report/presentation/widgets/practice_temperature_chart.dart';
import 'package:vibesync/features/report/presentation/widgets/stage_distribution_chart.dart';
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_tier_helper.dart';
import 'package:vibesync/features/user_profile/data/providers/user_profile_providers.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';

/// Seeded subscription notifier，同 analysis_screen_hydration_test 的
/// seeded-notifier idiom：constructor body 在 super() 的同步初始化之後執行，
/// 直接覆寫 state；後續 async 初始化在測試環境（無 Supabase user）全為 no-op。
class _SeededSubscriptionNotifier extends SubscriptionNotifier {
  _SeededSubscriptionNotifier(SubscriptionState seed) {
    state = seed;
  }
}

/// AboutMeCard 依賴的 profile controller — 固定回傳 null（empty state），
/// 避免 widget test 碰到未初始化的 Supabase auth stream。
class _NullUserProfileController extends UserProfileController {
  @override
  Future<UserProfile?> build() async => null;
}

Partner _partner(String id, String name) => Partner(
      id: id,
      name: name,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      ownerUserId: 'u-1',
    );

const _emptyReport = ReportData(
  trendPoints: [],
  averageScore: 0,
  scoreDelta: 0,
  comparisons: [],
  stageDistributions: [],
  totalConversations: 0,
);

ReportData _paidReport() => ReportData(
      trendPoints: [
        HeatTrendPoint(
          date: DateTime(2026, 6, 1),
          score: 60,
          conversationName: 'Vivi',
        ),
        HeatTrendPoint(
          date: DateTime(2026, 6, 2),
          score: 72,
          conversationName: 'Vivi',
        ),
      ],
      averageScore: 66,
      scoreDelta: 12,
      comparisons: const [ConversationComparison(name: 'Vivi', score: 72)],
      stageDistributions: const [
        StageDistribution(stageName: '建立男女感', count: 2),
      ],
      totalConversations: 2,
    );

AnalysisHistoryEvent _historyEvent(
  String id,
  String conversationId,
  String name,
  int score,
  DateTime createdAt,
) =>
    AnalysisHistoryEvent.analyze(
      id: id,
      createdAt: createdAt,
      conversationId: conversationId,
      subjectName: name,
      enthusiasmScore: score,
      gameStageLabel: 'premise',
    );

Future<void> _pumpReportScreen(
  WidgetTester tester, {
  required SubscriptionState subscription,
  required ReportData report,
  required List<Partner> partners,
  List<AnalysisHistoryEvent> historyEvents = const [],
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        subscriptionProvider
            .overrideWith((ref) => _SeededSubscriptionNotifier(subscription)),
        reportDataProvider.overrideWithValue(report),
        analysisHistoryEventsProvider.overrideWithValue(historyEvents),
        partnerListProvider.overrideWithValue(partners),
        conversationsByPartnerProvider.overrideWith((ref, id) => const []),
        userProfileControllerProvider
            .overrideWith(_NullUserProfileController.new),
      ],
      child: const MaterialApp(
        home: Scaffold(body: MyReportScreen()),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('決策 A：Free + 1 對象 → 鎖卡與對象作戰板同時 render', (tester) async {
    await _pumpReportScreen(
      tester,
      subscription: const SubscriptionState(
        tier: SubscriptionTierHelper.free,
      ),
      report: _emptyReport,
      partners: [_partner('p1', 'Vivi')],
    );

    // 既有 Free gating：鎖卡仍在。
    expect(find.text('我的報告會在 Starter 解鎖'), findsOneWidget);
    // 決策 A：作戰板 section 不受 gating 影響，必須一起出現。
    expect(find.text('對象作戰板'), findsOneWidget);
    expect(find.text('Vivi'), findsOneWidget);
    expect(find.text('尚未分析'), findsOneWidget);
    // 報告三張圖在 Free 下不該出現。
    expect(find.byType(HeatTrendChart), findsNothing);
  });

  testWidgets('決策 A：付費 + 有數據 → 三張圖與對象作戰板同時 render', (tester) async {
    await _pumpReportScreen(
      tester,
      subscription: const SubscriptionState(
        tier: SubscriptionTierHelper.starter,
      ),
      report: _paidReport(),
      partners: [_partner('p1', 'Vivi')],
    );

    expect(find.text('我的報告會在 Starter 解鎖'), findsNothing);
    expect(find.byType(HeatTrendChart), findsOneWidget);
    expect(find.byType(ConversationComparisonChart), findsOneWidget);
    expect(find.text('最近一次投入度比較'), findsOneWidget);
    expect(find.byType(StageDistributionChart), findsOneWidget);
    expect(find.text('對象作戰板'), findsOneWidget);
    expect(find.text('Vivi'), findsWidgets);
  });

  group('案2：對象選擇器＋單對象熱度序列', () {
    final events = [
      _historyEvent('a1', 'c-1', '小雲', 50, DateTime(2026, 6, 1)),
      _historyEvent('a2', 'c-1', '小雲', 70, DateTime(2026, 6, 8)),
      _historyEvent('b1', 'c-2', '安安', 40, DateTime(2026, 6, 9)),
      _historyEvent('b2', 'c-2', '安安', 66, DateTime(2026, 6, 10)),
    ];

    testWidgets('chip 列 render、預設選最近分析過的對象（安安）', (tester) async {
      await _pumpReportScreen(
        tester,
        subscription: const SubscriptionState(
          tier: SubscriptionTierHelper.starter,
        ),
        report: _paidReport(),
        partners: [_partner('p1', 'Vivi')],
        historyEvents: events,
      );

      expect(find.text('安安'), findsWidgets);
      expect(find.text('小雲'), findsWidgets);
      // 預設選最近事件的對象 c-2（安安）→ 圖上是安安的 2 點序列
      final chart = tester.widget<HeatTrendChart>(find.byType(HeatTrendChart));
      expect(chart.trendPoints.map((p) => p.score), [40, 66]);
    });

    testWidgets('點另一個 chip → 熱度卡切到那位對象的序列', (tester) async {
      await _pumpReportScreen(
        tester,
        subscription: const SubscriptionState(
          tier: SubscriptionTierHelper.starter,
        ),
        report: _paidReport(),
        partners: [_partner('p1', 'Vivi')],
        historyEvents: events,
      );

      await tester.tap(find.text('小雲').first);
      await tester.pumpAndSettle(); // LineChart 資料切換動畫有限時長，必收斂

      final chart = tester.widget<HeatTrendChart>(find.byType(HeatTrendChart));
      expect(chart.trendPoints.map((p) => p.score), [50, 70]);
    });

    testWidgets('所選對象事件 <2 筆 → 引導文案、不畫圖', (tester) async {
      await _pumpReportScreen(
        tester,
        subscription: const SubscriptionState(
          tier: SubscriptionTierHelper.starter,
        ),
        report: _paidReport(),
        partners: [_partner('p1', 'Vivi')],
        historyEvents: [
          _historyEvent('a1', 'c-1', '小雲', 50, DateTime(2026, 6, 1)),
        ],
      );

      expect(
        find.text('再多分析幾次，就能比較對方每次互動的投入度'),
        findsOneWidget,
      );
    });

    testWidgets('完全沒有事件（舊用戶未回填）→ 引導文案、既有其他區塊照常', (tester) async {
      await _pumpReportScreen(
        tester,
        subscription: const SubscriptionState(
          tier: SubscriptionTierHelper.starter,
        ),
        report: _paidReport(),
        partners: [_partner('p1', 'Vivi')],
        historyEvents: const [],
      );

      expect(
        find.text('再多分析幾次，就能比較對方每次互動的投入度'),
        findsOneWidget,
      );
      expect(find.byType(ConversationComparisonChart), findsOneWidget);
      expect(find.byType(StageDistributionChart), findsOneWidget);
    });

    testWidgets('practice 事件 ≥2 → 練習溫度卡出現在報告區', (tester) async {
      await _pumpReportScreen(
        tester,
        subscription: const SubscriptionState(
          tier: SubscriptionTierHelper.starter,
        ),
        report: _paidReport(),
        partners: [_partner('p1', 'Vivi')],
        historyEvents: [
          AnalysisHistoryEvent.practice(
            id: 'p1',
            createdAt: DateTime(2026, 6, 1),
            profileId: 'practice_girl_001',
            roundIndex: 1,
            temperatureScore: 28,
          ),
          AnalysisHistoryEvent.practice(
            id: 'p2',
            createdAt: DateTime(2026, 6, 4),
            profileId: 'practice_girl_002',
            roundIndex: 1,
            temperatureScore: 45,
          ),
        ],
      );

      expect(find.byType(PracticeTemperatureChart), findsOneWidget);
      expect(find.text('練習溫度成長'), findsOneWidget);
    });
  });
}
