import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/core/services/message_calculator.dart';
import 'package:vibesync/core/services/usage_service.dart';
import 'package:vibesync/shared/widgets/analysis_preview_dialog.dart';

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

  group('AnalysisPreviewDialog', () {
    testWidgets('displays title and message count', (tester) async {
      final preview = const MessagePreview(
        messageCount: 5,
        charCount: 100,
        exceedsLimit: false,
      );
      final usage = UsageData.free();

      await tester.pumpWidget(buildTestWidget(
        preview: preview,
        usage: usage,
      ));
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('確認分析'), findsOneWidget);
      expect(find.text('本次分析'), findsOneWidget);
      expect(find.text('5 則訊息'), findsOneWidget);
    });

    testWidgets('displays monthly and daily usage', (tester) async {
      final preview = const MessagePreview(
        messageCount: 3,
        charCount: 50,
        exceedsLimit: false,
      );
      final usage = UsageData(
        monthlyUsed: 10,
        monthlyLimit: 30,
        dailyUsed: 5,
        dailyLimit: 15,
        dailyResetAt: DateTime.now().add(const Duration(days: 1)),
      );

      await tester.pumpWidget(buildTestWidget(
        preview: preview,
        usage: usage,
      ));
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('月額度'), findsOneWidget);
      expect(find.text('剩餘 20 / 30 則'), findsOneWidget);
      expect(find.text('今日額度'), findsOneWidget);
      expect(find.text('剩餘 10 / 15 則'), findsOneWidget);
    });

    testWidgets('shows after analysis preview when can proceed', (tester) async {
      final preview = const MessagePreview(
        messageCount: 5,
        charCount: 100,
        exceedsLimit: false,
      );
      final usage = UsageData(
        monthlyUsed: 10,
        monthlyLimit: 30,
        dailyUsed: 5,
        dailyLimit: 15,
        dailyResetAt: DateTime.now().add(const Duration(days: 1)),
      );

      await tester.pumpWidget(buildTestWidget(
        preview: preview,
        usage: usage,
      ));
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // After analysis: monthly 20-5=15, daily 10-5=5
      expect(find.text('分析後剩餘: 月 15 則 / 日 5 則'), findsOneWidget);
    });

    testWidgets('shows warning when content exceeds limit', (tester) async {
      final preview = const MessagePreview(
        messageCount: 30,
        charCount: 6000,
        exceedsLimit: true,
      );
      final usage = UsageData.free();

      await tester.pumpWidget(buildTestWidget(
        preview: preview,
        usage: usage,
      ));
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('內容過長，請分批分析 (上限 5,000 字)'), findsOneWidget);
    });

    testWidgets('shows warning when monthly limit exceeded', (tester) async {
      final preview = const MessagePreview(
        messageCount: 10,
        charCount: 200,
        exceedsLimit: false,
      );
      final usage = UsageData(
        monthlyUsed: 25,
        monthlyLimit: 30,
        dailyUsed: 0,
        dailyLimit: 15,
        dailyResetAt: DateTime.now().add(const Duration(days: 1)),
      );

      await tester.pumpWidget(buildTestWidget(
        preview: preview,
        usage: usage,
      ));
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('月額度不足，請升級方案'), findsOneWidget);
    });

    testWidgets('shows warning when daily limit exceeded', (tester) async {
      final preview = const MessagePreview(
        messageCount: 10,
        charCount: 200,
        exceedsLimit: false,
      );
      final usage = UsageData(
        monthlyUsed: 0,
        monthlyLimit: 30,
        dailyUsed: 10,
        dailyLimit: 15,
        dailyResetAt: DateTime.now().add(const Duration(days: 1)),
      );

      await tester.pumpWidget(buildTestWidget(
        preview: preview,
        usage: usage,
      ));
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('今日額度已用完，明天再試'), findsOneWidget);
    });

    testWidgets('confirm button enabled when can proceed', (tester) async {
      final preview = const MessagePreview(
        messageCount: 5,
        charCount: 100,
        exceedsLimit: false,
      );
      final usage = UsageData.free();
      bool confirmed = false;

      await tester.pumpWidget(buildTestWidget(
        preview: preview,
        usage: usage,
        onConfirm: () => confirmed = true,
      ));
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      final confirmButton = find.widgetWithText(ElevatedButton, '確認分析');
      expect(confirmButton, findsOneWidget);

      await tester.tap(confirmButton);
      await tester.pumpAndSettle();

      expect(confirmed, isTrue);
    });

    testWidgets('confirm button disabled when cannot proceed', (tester) async {
      final preview = const MessagePreview(
        messageCount: 50,
        charCount: 6000,
        exceedsLimit: true,
      );
      final usage = UsageData.free();

      await tester.pumpWidget(buildTestWidget(
        preview: preview,
        usage: usage,
      ));
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      final confirmButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, '確認分析'),
      );
      expect(confirmButton.onPressed, isNull);
    });

    testWidgets('cancel button calls onCancel', (tester) async {
      final preview = const MessagePreview(
        messageCount: 5,
        charCount: 100,
        exceedsLimit: false,
      );
      final usage = UsageData.free();
      bool cancelled = false;

      await tester.pumpWidget(buildTestWidget(
        preview: preview,
        usage: usage,
        onCancel: () => cancelled = true,
      ));
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(cancelled, isTrue);
    });

    testWidgets('shows upgrade button when cannot proceed and onUpgrade provided', (tester) async {
      final preview = const MessagePreview(
        messageCount: 50,
        charCount: 200,
        exceedsLimit: false,
      );
      final usage = UsageData(
        monthlyUsed: 30,
        monthlyLimit: 30,
        dailyUsed: 0,
        dailyLimit: 15,
        dailyResetAt: DateTime.now().add(const Duration(days: 1)),
      );
      bool upgraded = false;

      await tester.pumpWidget(buildTestWidget(
        preview: preview,
        usage: usage,
        onUpgrade: () => upgraded = true,
      ));
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('升級方案'), findsOneWidget);
      await tester.tap(find.text('升級方案'));
      await tester.pumpAndSettle();

      expect(upgraded, isTrue);
    });

    testWidgets('hides upgrade button when onUpgrade not provided', (tester) async {
      final preview = const MessagePreview(
        messageCount: 50,
        charCount: 200,
        exceedsLimit: false,
      );
      final usage = UsageData(
        monthlyUsed: 30,
        monthlyLimit: 30,
        dailyUsed: 0,
        dailyLimit: 15,
        dailyResetAt: DateTime.now().add(const Duration(days: 1)),
      );

      await tester.pumpWidget(buildTestWidget(
        preview: preview,
        usage: usage,
        // onUpgrade not provided
      ));
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('升級方案'), findsNothing);
    });
  });

  group('showAnalysisPreviewDialog helper', () {
    testWidgets('returns true when confirmed', (tester) async {
      bool? result;
      final preview = const MessagePreview(
        messageCount: 5,
        charCount: 100,
        exceedsLimit: false,
      );
      final usage = UsageData.free();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showAnalysisPreviewDialog(
                  context: context,
                  preview: preview,
                  usage: usage,
                );
              },
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('確認分析'));
      await tester.pumpAndSettle();

      expect(result, isTrue);
    });

    testWidgets('returns false when cancelled', (tester) async {
      bool? result;
      final preview = const MessagePreview(
        messageCount: 5,
        charCount: 100,
        exceedsLimit: false,
      );
      final usage = UsageData.free();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showAnalysisPreviewDialog(
                  context: context,
                  preview: preview,
                  usage: usage,
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
