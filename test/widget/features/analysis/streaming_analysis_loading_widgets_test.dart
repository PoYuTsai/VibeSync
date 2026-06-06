import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/presentation/widgets/streaming_analysis_loading_widgets.dart';

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
      // AnimatedSwitcher cross-fades; both old + new may briefly exist.
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

  group('FullAnalysisPlaceholder', () {
    testWidgets('renders ETA range derived from server seconds',
        (tester) async {
      await tester.pumpWidget(_wrap(const FullAnalysisPlaceholder(
        estimatedFullSeconds: 17,
      )));

      expect(find.textContaining('預估 15-20 秒'), findsOneWidget);
      expect(find.text('五大回覆風格整理中...'), findsOneWidget);
      expect(find.text('互動雷達整理中...'), findsOneWidget);
      expect(find.text('深層策略整理中...'), findsOneWidget);
      expect(find.text(kFullPlaceholderClosing), findsOneWidget);
    });

    testWidgets('falls back to 15-20 when server omits estimatedFullSeconds',
        (tester) async {
      await tester.pumpWidget(_wrap(const FullAnalysisPlaceholder()));

      expect(find.textContaining('預估 15-20 秒'), findsOneWidget);
    });

    testWidgets('formatEtaRange returns server-based range, never negative',
        (tester) async {
      expect(FullAnalysisPlaceholder.formatEtaRange(17), '15-20');
      expect(FullAnalysisPlaceholder.formatEtaRange(null), '15-20');
      expect(FullAnalysisPlaceholder.formatEtaRange(0), '15-20');
      expect(FullAnalysisPlaceholder.formatEtaRange(3), '1-6');
    });
  });

  group('FullAnalysisRetryCard', () {
    testWidgets('shows retry button enabled with remaining count',
        (tester) async {
      var tapped = 0;
      await tester.pumpWidget(_wrap(FullAnalysisRetryCard(
        retriesRemaining: 2,
        errorMessage: '完整分析暫時失敗，可以重試。',
        onRetry: () => tapped++,
      )));

      expect(find.text('完整分析暫時失敗，可以重試。'), findsOneWidget);
      expect(find.text('重試完整分析（剩 2 次）'), findsOneWidget);

      await tester.tap(find.text('重試完整分析（剩 2 次）'));
      expect(tapped, 1);
    });

    testWidgets('disables retry and shows exhausted copy when 0 left',
        (tester) async {
      var tapped = 0;
      await tester.pumpWidget(_wrap(FullAnalysisRetryCard(
        retriesRemaining: 0,
        errorMessage: '不該顯示',
        onRetry: () => tapped++,
      )));

      expect(find.text(kRetryExhaustedMessage), findsOneWidget);
      expect(find.text('不該顯示'), findsNothing);

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);

      // Even if we tap, callback must not fire because disabled.
      await tester.tap(find.byType(FilledButton), warnIfMissed: false);
      expect(tapped, 0);
    });
  });
}
