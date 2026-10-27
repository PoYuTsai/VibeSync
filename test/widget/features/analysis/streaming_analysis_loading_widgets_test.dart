import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/presentation/helpers/analysis_quota_hints.dart';
import 'package:vibesync/features/analysis/presentation/widgets/streaming_analysis_loading_widgets.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_tier_helper.dart';

Widget _wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

void main() {
  group('StreamingAnalysisLoader', () {
    testWidgets('renders the first phrase immediately', (tester) async {
      await tester.pumpWidget(_wrap(const StreamingAnalysisLoader(
        phrases: ['一', '二', '三'],
        interval: Duration(milliseconds: 100),
      )));

      expect(find.text('一'), findsOneWidget);
      expect(find.text('二'), findsNothing);

      // Tear down so the Timer.periodic doesn't outlive the test binding.
      await tester.pumpWidget(_wrap(const SizedBox.shrink()));
    });

    testWidgets('cycles through phrases on a timer', (tester) async {
      await tester.pumpWidget(_wrap(const StreamingAnalysisLoader(
        phrases: ['一', '二', '三'],
        interval: Duration(milliseconds: 100),
      )));

      expect(find.text('一'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 100));
      // 純 Text 直接換字（2026-08 殘影拆除後無過場動畫）。
      expect(find.text('二'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('三'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('一'), findsOneWidget); // wraps

      await tester.pumpWidget(_wrap(const SizedBox.shrink()));
    });

    testWidgets('does not start timer when only one phrase given',
        (tester) async {
      await tester.pumpWidget(_wrap(const StreamingAnalysisLoader(
        phrases: ['唯一'],
        interval: Duration(milliseconds: 100),
      )));

      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('唯一'), findsOneWidget);

      await tester.pumpWidget(_wrap(const SizedBox.shrink()));
    });
  });

  group('StreamingAnalysisRetryCard', () {
    testWidgets('shows retry button enabled with remaining count',
        (tester) async {
      var tapped = 0;
      await tester.pumpWidget(_wrap(StreamingAnalysisRetryCard(
        retriesRemaining: 2,
        errorMessage: '完整分析暫時失敗，可以重試。',
        onRetry: () => tapped++,
      )));

      expect(find.text('完整分析暫時失敗，可以重試。'), findsOneWidget);
      expect(find.text('重試完整分析（剩 2 次）'), findsOneWidget);

      await tester.tap(find.text('重試完整分析（剩 2 次）'));
      expect(tapped, 1);
    });

    testWidgets('0 left：顯示原因，「重新分析」呼叫 onReanalyze 而不是 onRetry', (tester) async {
      var retried = 0;
      var reanalyzed = 0;
      await tester.pumpWidget(_wrap(StreamingAnalysisRetryCard(
        retriesRemaining: 0,
        errorMessage: '你剛剛更新了本次片段，這份完整分析先不套用，請重新分析。',
        onRetry: () => retried++,
        onReanalyze: () => reanalyzed++,
      )));

      expect(
        find.text('你剛剛更新了本次片段，這份完整分析先不套用，請重新分析。'),
        findsOneWidget,
      );
      expect(find.text(kRetryExhaustedMessage), findsNothing);
      expect(find.text('無法再重試'), findsNothing);

      await tester.tap(find.text('重新分析'));
      expect(reanalyzed, 1);
      expect(retried, 0);
    });

    testWidgets('0 left 且沒有原因：退回預設文案', (tester) async {
      await tester.pumpWidget(_wrap(StreamingAnalysisRetryCard(
        retriesRemaining: 0,
        errorMessage: '  ',
        onReanalyze: () {},
      )));

      expect(find.text(kRetryExhaustedMessage), findsOneWidget);
      expect(find.text('重新分析'), findsOneWidget);
    });

    testWidgets('0 left 但 onReanalyze 是 null（例如辨識中）：按鈕停用', (tester) async {
      var retried = 0;
      await tester.pumpWidget(_wrap(StreamingAnalysisRetryCard(
        retriesRemaining: 0,
        onRetry: () => retried++,
      )));

      expect(find.text('重新分析'), findsOneWidget);
      expect(find.text('無法再重試'), findsNothing);
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);

      await tester.tap(find.byType(FilledButton), warnIfMissed: false);
      expect(retried, 0);
    });
  });

  group('QuotaExceededUpgradeCard（smoke P1 fix 2026-06-11）', () {
    testWidgets('monthly：顯示剩餘/需要則數 + 恢復時間 + 升級文案 + 查看方案，絕不出現「無法再重試」',
        (tester) async {
      var viewed = 0;
      await tester.pumpWidget(_wrap(QuotaExceededUpgradeCard(
        isMonthly: true,
        tier: SubscriptionTierHelper.free,
        remaining: 2,
        quotaNeeded: 5,
        onViewPlans: () => viewed++,
      )));

      expect(
        // Onboarding 第 3 步：先講每月 1 號早上 8 點恢復，再說也可以升級。
        find.text(
            '本月額度剩 2 則，這次分析需要 5 則。每月 1 號早上 8 點恢復；也可以升級至 Starter 或 Essential。'),
        findsOneWidget,
      );
      expect(find.text(kRetryExhaustedMessage), findsNothing);
      expect(find.text('無法再重試'), findsNothing);

      await tester.tap(find.text('查看方案'));
      expect(viewed, 1);
    });

    testWidgets('daily：每天早上 8 點恢復 + 升級文案', (tester) async {
      await tester.pumpWidget(_wrap(QuotaExceededUpgradeCard(
        isMonthly: false,
        tier: SubscriptionTierHelper.free,
        remaining: 0,
        quotaNeeded: 3,
        onViewPlans: () {},
      )));

      expect(
        find.text('今日額度剩 0 則，這次分析需要 3 則。每天早上 8 點恢復；也可以升級取得更多額度。'),
        findsOneWidget,
      );
      expect(find.text('查看方案'), findsOneWidget);
    });

    testWidgets('缺 remaining/quotaNeeded 時 fallback 文案不出現 null',
        (tester) async {
      await tester.pumpWidget(_wrap(QuotaExceededUpgradeCard(
        isMonthly: true,
        tier: SubscriptionTierHelper.free,
        remaining: null,
        quotaNeeded: null,
        onViewPlans: () {},
      )));

      expect(
        find.text('本月額度不足，每月 1 號早上 8 點恢復；也可以升級至 Starter 或 Essential。'),
        findsOneWidget,
      );
      expect(find.textContaining('null'), findsNothing);
    });

    testWidgets('額度用完（Eric 2026-10-18）：免費用戶多一行 Starter 的量；沒要求就不出',
        (tester) async {
      await tester.pumpWidget(_wrap(QuotaExceededUpgradeCard(
        isMonthly: false,
        tier: SubscriptionTierHelper.free,
        remaining: 0,
        quotaNeeded: 3,
        onViewPlans: () {},
        showStarterCapacity: true,
      )));
      expect(find.text(starterCapacityLine()), findsOneWidget);
      expect(find.text('查看方案'), findsOneWidget);

      await tester.pumpWidget(_wrap(QuotaExceededUpgradeCard(
        isMonthly: false,
        tier: SubscriptionTierHelper.free,
        remaining: 0,
        quotaNeeded: 3,
        onViewPlans: () {},
      )));
      expect(find.text(starterCapacityLine()), findsNothing);
    });
  });

  group('QuotaExceededUpgradeCard：說法照目前方案（Eric 2026-10-18）', () {
    Future<void> pumpCard(
      WidgetTester tester, {
      required String tier,
      required bool isMonthly,
      int? remaining,
      int? quotaNeeded,
    }) =>
        tester.pumpWidget(_wrap(QuotaExceededUpgradeCard(
          isMonthly: isMonthly,
          tier: tier,
          remaining: remaining,
          quotaNeeded: quotaNeeded,
          onViewPlans: () {},
        )));

    testWidgets('Essential 這個月不夠：不叫他升級，只說每月 1 號早上 8 點恢復', (tester) async {
      await pumpCard(
        tester,
        tier: SubscriptionTierHelper.essential,
        isMonthly: true,
        remaining: 2,
        quotaNeeded: 5,
      );
      expect(
        find.text('本月額度剩 2 則，這次分析需要 5 則。每月 1 號早上 8 點恢復。'),
        findsOneWidget,
      );
      expect(find.textContaining('升級'), findsNothing);

      await pumpCard(
        tester,
        tier: SubscriptionTierHelper.essential,
        isMonthly: true,
      );
      expect(find.text('本月額度不足，每月 1 號早上 8 點恢復。'), findsOneWidget);
      expect(find.textContaining('升級'), findsNothing);
    });

    testWidgets('Essential 今天不夠：只說每天早上 8 點恢復', (tester) async {
      await pumpCard(
        tester,
        tier: SubscriptionTierHelper.essential,
        isMonthly: false,
        remaining: 0,
        quotaNeeded: 3,
      );
      expect(
        find.text('今日額度剩 0 則，這次分析需要 3 則。每天早上 8 點恢復。'),
        findsOneWidget,
      );
      expect(find.textContaining('升級'), findsNothing);

      await pumpCard(
        tester,
        tier: SubscriptionTierHelper.essential,
        isMonthly: false,
      );
      expect(find.text('今日額度不足，每天早上 8 點恢復。'), findsOneWidget);
      expect(find.textContaining('升級'), findsNothing);
      // 查看方案照舊在（付費頁大標也只說什麼時候恢復）。
      expect(find.text('查看方案'), findsOneWidget);
    });

    testWidgets('Starter 這個月不夠：先說恢復時間，只叫他升級 Essential，不叫他升級到 Starter',
        (tester) async {
      await pumpCard(
        tester,
        tier: SubscriptionTierHelper.starter,
        isMonthly: true,
        remaining: 2,
        quotaNeeded: 5,
      );
      expect(
        find.text('本月額度剩 2 則，這次分析需要 5 則。每月 1 號早上 8 點恢復；也可以升級至 Essential。'),
        findsOneWidget,
      );

      await pumpCard(
        tester,
        tier: SubscriptionTierHelper.starter,
        isMonthly: true,
      );
      expect(
          find.text('本月額度不足，每月 1 號早上 8 點恢復；也可以升級至 Essential。'), findsOneWidget);
    });

    testWidgets('Starter 今天不夠：每天早上 8 點恢復，也可以升級', (tester) async {
      await pumpCard(
        tester,
        tier: SubscriptionTierHelper.starter,
        isMonthly: false,
        remaining: 1,
        quotaNeeded: 3,
      );
      expect(
        find.text('今日額度剩 1 則，這次分析需要 3 則。每天早上 8 點恢復；也可以升級取得更多額度。'),
        findsOneWidget,
      );
    });
  });
}
