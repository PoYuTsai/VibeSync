// test/widget/features/report/my_report_screen_test.dart
//
// 決策 A 守門（regression guard）：報告頁的「對象作戰板」section 全 tier 可見，
// 與上方報告 Free gating 互不影響。
// - Free + 1 對象 → 鎖卡（既有 gating）與作戰板 section 必須同時 render。
// - 付費 + 有數據 → 三張圖與作戰板 section 必須同時 render。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/report/data/providers/report_providers.dart';
import 'package:vibesync/features/report/domain/entities/report_models.dart';
import 'package:vibesync/features/report/presentation/screens/my_report_screen.dart';
import 'package:vibesync/features/report/presentation/widgets/conversation_comparison_chart.dart';
import 'package:vibesync/features/report/presentation/widgets/heat_trend_chart.dart';
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

Future<void> _pumpReportScreen(
  WidgetTester tester, {
  required SubscriptionState subscription,
  required ReportData report,
  required List<Partner> partners,
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        subscriptionProvider
            .overrideWith((ref) => _SeededSubscriptionNotifier(subscription)),
        reportDataProvider.overrideWithValue(report),
        partnerListProvider.overrideWithValue(partners),
        conversationsByPartnerProvider
            .overrideWith((ref, id) => const []),
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
    expect(find.byType(StageDistributionChart), findsOneWidget);
    expect(find.text('對象作戰板'), findsOneWidget);
    expect(find.text('Vivi'), findsWidgets);
  });
}
