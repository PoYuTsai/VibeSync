import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/presentation/widgets/analysis_usage_summary_line.dart';

Widget _wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

void main() {
  group('AnalysisUsageSummaryLine（smoke P2 fix 2026-06-11）', () {
    testWidgets('顯示「本次分析使用 N 則・剩餘 M 則」', (tester) async {
      await tester.pumpWidget(_wrap(const AnalysisUsageSummaryLine(
        usage: {
          'messagesUsed': 5,
          'monthlyRemaining': 25,
          'isTestAccount': false,
        },
      )));

      expect(find.text('本次分析使用 5 則・剩餘 25 則'), findsOneWidget);
    });

    testWidgets('messagesUsed = 0（recognizeOnly / 未扣費）不顯示', (tester) async {
      await tester.pumpWidget(_wrap(const AnalysisUsageSummaryLine(
        usage: {'messagesUsed': 0, 'monthlyRemaining': 30},
      )));

      expect(find.byType(Text), findsNothing);
    });

    testWidgets('usage 缺失不顯示', (tester) async {
      await tester.pumpWidget(_wrap(const AnalysisUsageSummaryLine(
        usage: null,
      )));

      expect(find.byType(Text), findsNothing);
    });

    testWidgets('測試帳號不顯示（與 SnackBar 行為一致）', (tester) async {
      await tester.pumpWidget(_wrap(const AnalysisUsageSummaryLine(
        usage: {
          'messagesUsed': 5,
          'monthlyRemaining': 999999,
          'isTestAccount': true,
        },
      )));

      expect(find.byType(Text), findsNothing);
    });

    testWidgets('缺 monthlyRemaining 時只顯示使用則數，不出現 null', (tester) async {
      await tester.pumpWidget(_wrap(const AnalysisUsageSummaryLine(
        usage: {'messagesUsed': 3},
      )));

      expect(find.text('本次分析使用 3 則'), findsOneWidget);
      expect(find.textContaining('null'), findsNothing);
      expect(find.textContaining('剩餘'), findsNothing);
    });

    test('summaryText 對非 Map 輸入回 null', () {
      expect(AnalysisUsageSummaryLine.summaryText('not a map'), isNull);
      expect(AnalysisUsageSummaryLine.summaryText(null), isNull);
    });
  });
}
