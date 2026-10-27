// ADR #19 r3 分析前預覽 dialog 測試。
//
// 契約：
// - standard 帶：顯示算出的精確則數（Eric 2026-10-18，不再只報 1–10 則）。
// - overcharge 帶（2001~4000 字）：本 dialog 即「>2000 字確認框」，
//   顯示精確「本次將使用 20 則」；額度不足時確認鈕停用（定案 #4 防禦層）。
// - reject 帶由 caller 在呼叫前擋下，dialog 不處理。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/core/constants/app_constants.dart';
import 'package:vibesync/core/services/message_calculator.dart';
import 'package:vibesync/core/services/usage_service.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_tier_helper.dart';
import 'package:vibesync/shared/widgets/analysis_preview_dialog.dart';

MessagePreview _preview(int billableChars) => MessagePreview(
      payloadChars: billableChars,
      billableChars: billableChars,
      band: MessageCalculator.bandForBillableChars(billableChars),
    );

void main() {
  Widget buildTestWidget({
    required MessagePreview preview,
    required UsageData usage,
    VoidCallback? onConfirm,
    VoidCallback? onCancel,
    VoidCallback? onUpgrade,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AnalysisPreviewDialog(
                  preview: preview,
                  usage: usage,
                  onConfirm: onConfirm ?? () {},
                  onCancel: onCancel ?? () {},
                  onUpgrade: onUpgrade,
                ),
              );
            },
            child: const Text('Open Dialog'),
          ),
        ),
      ),
    );
  }

  Future<void> openDialog(WidgetTester tester) async {
    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();
  }

  group('AnalysisPreviewDialog — standard 帶（精確則數）', () {
    testWidgets('shows the exact unit count from the billing mirror',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(
        preview: _preview(100), // ceil(100/40) = 3 則
        usage: UsageData.free(),
      ));
      await openDialog(tester);

      expect(find.text('開始分析前'), findsOneWidget);
      expect(find.text('預計使用'), findsOneWidget);
      expect(find.text('3 則'), findsOneWidget);
      expect(find.text('依對話複雜度 1–10 則'), findsNothing);
    });

    testWidgets('displays monthly and daily usage', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        preview: _preview(50),
        usage: UsageData(
          monthlyUsed: 10,
          monthlyLimit: 30,
          dailyUsed: 5,
          dailyLimit: 15,
          dailyResetAt: DateTime.now().add(const Duration(days: 1)),
        ),
      ));
      await openDialog(tester);

      expect(find.text('本月剩餘'), findsOneWidget);
      expect(find.text('20 / 30 則'), findsOneWidget);
      expect(find.text('今日剩餘'), findsOneWidget);
      expect(find.text('10 / 15 則'), findsOneWidget);
    });

    testWidgets('mentions actual usage shown after analysis', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        preview: _preview(50),
        usage: UsageData.free(),
      ));
      await openDialog(tester);

      expect(
        find.textContaining('分析完成後會顯示實際使用的則數'),
        findsOneWidget,
      );
      // 扣的是額度（則），不寫「次數」（Onboarding 第 3 步）。
      expect(
        find.textContaining('只有送出完整分析才會扣額度。先讀截圖、不做完整分析，不會扣額度。'),
        findsOneWidget,
      );
      expect(find.textContaining('次數'), findsNothing);
      // 「重新分析會用目前整段對話…」說明已拆（2026-08-16 Bruce 回饋）。
      expect(
        find.textContaining('重新分析會用目前整段對話重新判斷'),
        findsNothing,
      );
    });

    testWidgets('warns when monthly quota below required units',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(
        preview: _preview(450), // 10 則
        usage: UsageData(
          monthlyUsed: 25, // 剩 5 < 10
          monthlyLimit: 30,
          dailyUsed: 0,
          dailyLimit: 15,
          dailyResetAt: DateTime.now().add(const Duration(days: 1)),
        ),
      ));
      await openDialog(tester);

      // Onboarding 第 3 步：先講需要幾則、剩幾則，再講每月 1 號早上 8 點恢復，免費
      // 再補也可以升級；不寫「次數」。
      expect(
        find.text('這個月的額度不夠這次用（需要 10 則，剩 5 則）。'
            '每月 1 號早上 8 點恢復；也可以升級取得更多額度。'),
        findsOneWidget,
      );
      final confirmButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, '開始分析'),
      );
      expect(confirmButton.onPressed, isNull);
    });

    testWidgets('warns when daily quota below required units', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        preview: _preview(450), // 10 則
        usage: UsageData(
          monthlyUsed: 0,
          monthlyLimit: 30,
          dailyUsed: 10, // 剩 5 < 10
          dailyLimit: 15,
          dailyResetAt: DateTime.now().add(const Duration(days: 1)),
        ),
      ));
      await openDialog(tester);

      // 台灣早上 8 點恢復：凌晨不夠時當天早上就有，不說「明天」（主審第 1 輪 P3）。
      expect(
        find.text('今天的額度不夠這次用（需要 10 則，剩 5 則）。'
            '每天早上 8 點恢復；也可以升級取得更多額度。'),
        findsOneWidget,
      );
      expect(find.textContaining('明天'), findsNothing);
    });

    testWidgets('confirm button enabled and fires when quota suffices',
        (tester) async {
      bool confirmed = false;
      await tester.pumpWidget(buildTestWidget(
        preview: _preview(100),
        usage: UsageData.free(),
        onConfirm: () => confirmed = true,
      ));
      await openDialog(tester);

      await tester.tap(find.widgetWithText(ElevatedButton, '開始分析'));
      await tester.pumpAndSettle();
      expect(confirmed, isTrue);
    });

    testWidgets('cancel button calls onCancel', (tester) async {
      bool cancelled = false;
      await tester.pumpWidget(buildTestWidget(
        preview: _preview(100),
        usage: UsageData.free(),
        onCancel: () => cancelled = true,
      ));
      await openDialog(tester);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(cancelled, isTrue);
    });
  });

  group('AnalysisPreviewDialog — overcharge 帶（>2000 字確認框）', () {
    testWidgets('shows exact 20-unit charge and dedicated confirm copy',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(
        preview: _preview(2500),
        usage: UsageData(
          monthlyUsed: 0,
          monthlyLimit: 300,
          dailyUsed: 0,
          dailyLimit: 50,
          dailyResetAt: DateTime.now().add(const Duration(days: 1)),
        ),
      ));
      await openDialog(tester);

      expect(find.text('內容較長，確認後才會扣'), findsOneWidget);
      expect(find.text('本次將使用'), findsOneWidget);
      expect(find.text('20 則'), findsOneWidget);
      expect(find.text('約 2500 字'), findsOneWidget);
      expect(find.text('依對話複雜度 1–10 則'), findsNothing);
      expect(
        find.widgetWithText(ElevatedButton, '確認使用 20 則'),
        findsOneWidget,
      );
    });

    testWidgets('explains batch split costs the same', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        preview: _preview(3000),
        usage: UsageData(
          monthlyUsed: 0,
          monthlyLimit: 300,
          dailyUsed: 0,
          dailyLimit: 50,
          dailyResetAt: DateTime.now().add(const Duration(days: 1)),
        ),
      ));
      await openDialog(tester);

      expect(find.textContaining('合計也是 20 則'), findsOneWidget);
    });

    testWidgets('今天剛好剩 20 則 → 夠這次用，可以確認', (tester) async {
      // 邊界：剩下的剛好等於這次要用的。免費每天不到 20 則，所以用 Starter 的上限。
      final starter =
          SubscriptionTierHelper.limitsFor(SubscriptionTierHelper.starter);
      await tester.pumpWidget(buildTestWidget(
        preview: _preview(2500),
        usage: UsageData(
          monthlyUsed: 0,
          monthlyLimit: starter.monthly,
          dailyUsed: starter.daily - MessageCalculator.overchargeUnits,
          dailyLimit: starter.daily,
          dailyResetAt: DateTime.now().add(const Duration(days: 1)),
          tier: SubscriptionTierHelper.starter,
        ),
        onUpgrade: () {},
      ));
      await openDialog(tester);

      final confirmButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, '確認使用 20 則'),
      );
      expect(confirmButton.onPressed, isNotNull);
      expect(find.text('查看升級方案'), findsNothing);
    });

    testWidgets('Free tier 每日上限不到 20 則 → confirm disabled（定案 #4：額度先於確認）',
        (tester) async {
      // 免費每日上限（Eric 2026-10-19 改回 15 則）一天內不夠一次 20 則 → 引導分批
      //（跨日）或升級。
      expect(
        AppConstants.freeDailyLimit,
        lessThan(MessageCalculator.overchargeUnits),
      );
      await tester.pumpWidget(buildTestWidget(
        preview: _preview(2500),
        usage: UsageData.free(),
        onUpgrade: () {},
      ));
      await openDialog(tester);

      expect(
        find.text(
          '今天的額度不夠這次用（需要 ${MessageCalculator.overchargeUnits} 則，'
          '剩 ${AppConstants.freeDailyLimit} 則）。'
          '每天早上 8 點恢復；也可以升級取得更多額度。',
        ),
        findsOneWidget,
      );
      final confirmButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, '確認使用 20 則'),
      );
      expect(confirmButton.onPressed, isNull);
      expect(find.text('查看升級方案'), findsOneWidget);
    });

    testWidgets('upgrade button fires onUpgrade when quota insufficient',
        (tester) async {
      bool upgraded = false;
      await tester.pumpWidget(buildTestWidget(
        preview: _preview(2500),
        usage: UsageData.free(),
        onUpgrade: () => upgraded = true,
      ));
      await openDialog(tester);

      await tester.tap(find.text('查看升級方案'));
      await tester.pumpAndSettle();
      expect(upgraded, isTrue);
    });
  });

  group('AnalysisPreviewDialog — 額度不夠的說法照方案（Eric 2026-10-18）', () {
    const starter = SubscriptionTierHelper.starter;
    const essential = SubscriptionTierHelper.essential;

    /// [tier] 方案，上限照方案常數；[monthlyUsed]／[dailyUsed] 是已用則數。
    UsageData usageFor(String tier, {int monthlyUsed = 0, int dailyUsed = 0}) {
      final limits = SubscriptionTierHelper.limitsFor(tier);
      return UsageData(
        monthlyUsed: monthlyUsed,
        monthlyLimit: limits.monthly,
        dailyUsed: dailyUsed,
        dailyLimit: limits.daily,
        dailyResetAt: DateTime(2026, 10, 19),
        tier: tier,
      );
    }

    testWidgets('Essential 這個月不夠：不叫他升級，只說每月 1 號早上 8 點恢復；鈕寫查看方案',
        (tester) async {
      var upgraded = false;
      await tester.pumpWidget(buildTestWidget(
        preview: _preview(100), // 3 則
        usage: usageFor(
          essential,
          monthlyUsed: SubscriptionTierHelper.limitsFor(essential).monthly,
        ),
        onUpgrade: () => upgraded = true,
      ));
      await openDialog(tester);

      expect(
        find.text('這個月的額度不夠這次用（需要 3 則，剩 0 則）。每月 1 號早上 8 點恢復。'),
        findsOneWidget,
      );
      expect(find.textContaining('升級'), findsNothing);
      await tester.tap(find.text('查看方案'));
      await tester.pumpAndSettle();
      expect(upgraded, isTrue);
    });

    testWidgets('Essential 今天不夠：只說每天早上 8 點恢復', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        preview: _preview(100),
        usage: usageFor(
          essential,
          dailyUsed: SubscriptionTierHelper.limitsFor(essential).daily,
        ),
        onUpgrade: () {},
      ));
      await openDialog(tester);

      expect(
        find.text('今天的額度不夠這次用（需要 3 則，剩 0 則）。每天早上 8 點恢復。'),
        findsOneWidget,
      );
      expect(find.textContaining('升級'), findsNothing);
      expect(find.text('查看方案'), findsOneWidget);
    });

    testWidgets('Starter 還能升級：今天不夠先說恢復時間再叫他升級，鈕寫查看升級方案', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        preview: _preview(100),
        usage: usageFor(
          starter,
          dailyUsed: SubscriptionTierHelper.limitsFor(starter).daily,
        ),
        onUpgrade: () {},
      ));
      await openDialog(tester);

      expect(
        find.text('今天的額度不夠這次用（需要 3 則，剩 0 則）。'
            '每天早上 8 點恢復；也可以升級取得更多額度。'),
        findsOneWidget,
      );
      expect(find.text('查看升級方案'), findsOneWidget);
    });

    testWidgets('Starter 這個月不夠：先說每月 1 號早上 8 點恢復，再說也可以升級', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        preview: _preview(100),
        usage: usageFor(
          starter,
          monthlyUsed: SubscriptionTierHelper.limitsFor(starter).monthly,
        ),
        onUpgrade: () {},
      ));
      await openDialog(tester);

      expect(
        find.text('這個月的額度不夠這次用（需要 3 則，剩 0 則）。'
            '每月 1 號早上 8 點恢復；也可以升級取得更多額度。'),
        findsOneWidget,
      );
      expect(find.text('查看升級方案'), findsOneWidget);
    });
  });

  group('AnalysisQuotaLine（Eric 2026-10-18：額度夠的一般長度不跳框）', () {
    AnalysisQuotaLine? line(int chars, {int monthly = 30, int daily = 15}) =>
        AnalysisQuotaLine.of(
          _preview(chars),
          monthlyRemaining: monthly,
          dailyRemaining: daily,
        );

    test('額度夠、一般長度：這次會用 N 則，剩下本月與今日取少的扣掉 N', () {
      final today = line(100, daily: 11)!;
      expect(today.units, 3);
      expect(today.remainingAfter, 8);
      expect(today.text, '這次會用 3 則，剩 8 則');
      expect(line(40, monthly: 5)!.text, '這次會用 1 則，剩 4 則');
    });

    test('剛好用完也不跳框：剩 0 則', () {
      expect(line(450, daily: 10)!.text, '這次會用 10 則，剩 0 則');
    });

    test('兩個數字都一樣才算同一行（主審 r1 P2：多算、少算、剩的不同都不算）', () {
      expect(line(100, daily: 11), line(100, daily: 11));
      expect(line(100, daily: 11), isNot(line(140, daily: 11)));
      expect(line(100, daily: 11), isNot(line(60, daily: 11)));
      expect(line(100, daily: 11), isNot(line(100, daily: 12)));
    });

    test('額度不夠、超過 2000 字或超過上限：照舊跳確認框', () {
      expect(line(450, daily: 9), isNull);
      expect(line(450, monthly: 9), isNull);
      expect(line(2500, monthly: 300, daily: 50), isNull);
      expect(line(4500, monthly: 300, daily: 50), isNull);
    });
  });

  group('showAnalysisPreviewDialog helper', () {
    testWidgets('returns true when confirmed', (tester) async {
      bool? result;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showAnalysisPreviewDialog(
                  context: context,
                  preview: _preview(100),
                  usage: UsageData.free(),
                );
              },
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('開始分析'));
      await tester.pumpAndSettle();

      expect(result, isTrue);
    });

    testWidgets('returns false when cancelled', (tester) async {
      bool? result;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showAnalysisPreviewDialog(
                  context: context,
                  preview: _preview(100),
                  usage: UsageData.free(),
                );
              },
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(result, isFalse);
    });
  });
}
