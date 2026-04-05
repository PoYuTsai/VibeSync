import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/presentation/widgets/analysis_error_widget.dart';

void main() {
  Widget buildTestWidget({
    required AnalysisErrorType errorType,
    String? message,
    bool retryable = true,
    VoidCallback? onRetry,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: AnalysisErrorWidget(
            errorType: errorType,
            message: message,
            retryable: retryable,
            onRetry: onRetry,
          ),
        ),
      ),
    );
  }

  group('AnalysisErrorWidget', () {
    testWidgets('displays network error correctly', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        errorType: AnalysisErrorType.network,
      ));

      expect(find.text('網路連線失敗'), findsOneWidget);
      expect(find.text('請檢查網路連線後再試一次'), findsOneWidget);
      expect(find.byIcon(Icons.wifi_off), findsOneWidget);
    });

    testWidgets('displays timeout error correctly', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        errorType: AnalysisErrorType.timeout,
      ));

      expect(find.text('請求逾時'), findsOneWidget);
      expect(find.text('AI 回應時間過長，請稍後再試'), findsOneWidget);
      expect(find.byIcon(Icons.timer_off), findsOneWidget);
    });

    testWidgets('displays server error correctly', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        errorType: AnalysisErrorType.serverError,
      ));

      expect(find.text('AI 服務暫時無法使用'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    });

    testWidgets('displays rate limited error correctly', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        errorType: AnalysisErrorType.rateLimited,
      ));

      expect(find.text('服務繁忙'), findsOneWidget);
      expect(find.text('請求過於頻繁，請稍後再試'), findsOneWidget);
      expect(find.byIcon(Icons.hourglass_empty), findsOneWidget);
    });

    testWidgets('displays unsafe input error correctly', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        errorType: AnalysisErrorType.unsafeInput,
        retryable: false,
      ));

      expect(find.text('無法處理此內容'), findsOneWidget);
      expect(find.text('偵測到不適當的內容，無法提供建議'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber), findsOneWidget);
    });

    testWidgets('shows custom message when provided', (tester) async {
      const customMessage = '自訂錯誤訊息';
      await tester.pumpWidget(buildTestWidget(
        errorType: AnalysisErrorType.unknown,
        message: customMessage,
      ));

      expect(find.text(customMessage), findsOneWidget);
    });

    testWidgets('shows retry button when retryable', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        errorType: AnalysisErrorType.network,
        retryable: true,
        onRetry: () {},
      ));

      expect(find.text('重試'), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });

    testWidgets('hides retry button when not retryable', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        errorType: AnalysisErrorType.unsafeInput,
        retryable: false,
      ));

      expect(find.text('重試'), findsNothing);
    });

    testWidgets('calls onRetry when retry button tapped', (tester) async {
      var retryCount = 0;
      await tester.pumpWidget(buildTestWidget(
        errorType: AnalysisErrorType.network,
        retryable: true,
        onRetry: () => retryCount++,
      ));

      await tester.tap(find.text('重試'));
      await tester.pump();

      expect(retryCount, 1);
    });
  });

  group('AnalysisErrorWidget.fromCode', () {
    testWidgets('parses RATE_LIMITED code', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AnalysisErrorWidget.fromCode('RATE_LIMITED'),
            ),
          ),
        ),
      );

      expect(find.text('服務繁忙'), findsOneWidget);
      expect(find.text('重試'), findsOneWidget);
    });

    testWidgets('parses SERVER_ERROR code', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AnalysisErrorWidget.fromCode('SERVER_ERROR'),
            ),
          ),
        ),
      );

      expect(find.text('AI 服務暫時無法使用'), findsOneWidget);
    });

    testWidgets('parses UNSAFE_INPUT code', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AnalysisErrorWidget.fromCode('UNSAFE_INPUT'),
            ),
          ),
        ),
      );

      expect(find.text('無法處理此內容'), findsOneWidget);
      // UNSAFE_INPUT is not retryable
      expect(find.text('重試'), findsNothing);
    });

    testWidgets('handles unknown code', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AnalysisErrorWidget.fromCode('UNKNOWN_CODE'),
            ),
          ),
        ),
      );

      expect(find.text('發生錯誤'), findsOneWidget);
    });
  });
}
