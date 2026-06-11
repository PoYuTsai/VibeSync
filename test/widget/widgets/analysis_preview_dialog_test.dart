// ADR #19 r3 分析前預覽 dialog 測試。
//
// 契約：
// - standard 帶：靜態區間文案「依對話複雜度 1–10 則」，不報精確值。
// - overcharge 帶（2001~4000 字）：本 dialog 即「>2000 字確認框」，
//   顯示精確「本次將使用 20 則」；額度不足時確認鈕停用（定案 #4 防禦層）。
// - reject 帶由 caller 在呼叫前擋下，dialog 不處理。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/core/services/message_calculator.dart';
import 'package:vibesync/core/services/usage_service.dart';
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

  group('AnalysisPreviewDialog — standard 帶（靜態區間）', () {
    testWidgets('shows static range copy, never an exact unit count',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(
        preview: _preview(100), // 3 則，但 UI 不報精確值
        usage: UsageData.free(),
      ));
      await openDialog(tester);

      expect(find.text('開始分析前'), findsOneWidget);
      expect(find.text('預計使用'), findsOneWidget);
      expect(find.text('依對話複雜度 1–10 則'), findsOneWidget);
      expect(find.text('3 則'), findsNothing);
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
      expect(
        find.text('重新分析會用目前整段對話重新判斷；舊訊息只作為背景，不重複扣額度，這次只計算新增內容。'),
        findsOneWidget,
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

      expect(find.text('這個月的分析次數不夠了，升級後再繼續。'), findsOneWidget);
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

      expect(find.text('今天的分析次數不夠了，明天再來或先升級方案。'), findsOneWidget);
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

    testWidgets(
        'Free tier daily 15 < 20 → confirm disabled（定案 #4：額度先於確認）',
        (tester) async {
      // Free 日上限 15 永遠不夠 20 則 → 自然引導分批（跨日）或升級。
      await tester.pumpWidget(buildTestWidget(
        preview: _preview(2500),
        usage: UsageData.free(),
        onUpgrade: () {},
      ));
      await openDialog(tester);

      expect(find.text('今天的分析次數不夠了，明天再來或先升級方案。'), findsOneWidget);
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
