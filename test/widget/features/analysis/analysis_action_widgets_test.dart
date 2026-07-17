import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/presentation/widgets/analysis_action_widgets.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(
      floatingActionButton: child,
    ),
  );
}

void main() {
  group('buildAnalysisFloatingOverlay', () {
    test('stream hint replaces the start action while analysis is running', () {
      final overlay = buildAnalysisFloatingOverlay(
        showStartAction: true,
        isAnalyzing: true,
        analysisCompleted: false,
        onStart: () {},
      );

      expect(overlay, isA<AnalysisScrollHint>());
      expect(overlay, isNot(isA<FloatingAnalysisActionButton>()));
    });

    test('idle pending analysis keeps the start action', () {
      final overlay = buildAnalysisFloatingOverlay(
        showStartAction: true,
        isAnalyzing: false,
        analysisCompleted: false,
        onStart: () {},
      );

      expect(overlay, isA<FloatingAnalysisActionButton>());
    });
  });

  group('FloatingAnalysisActionButton', () {
    testWidgets('uses a labelled 52px extended action', (tester) async {
      await tester.pumpWidget(
        _wrap(FloatingAnalysisActionButton(onPressed: () {})),
      );
      await tester.pump(const Duration(milliseconds: 240));

      expect(
        find.byKey(FloatingAnalysisActionButton.buttonKey),
        findsOneWidget,
      );
      expect(find.text('開始分析'), findsOneWidget);
      expect(find.byIcon(Icons.auto_awesome_rounded), findsOneWidget);
      expect(
        find.bySemanticsLabel('使用目前對話開始分析'),
        findsOneWidget,
      );
      expect(
        tester
            .getSize(find.byKey(FloatingAnalysisActionButton.buttonKey))
            .height,
        52,
      );
    });

    testWidgets('runs the analyze callback once when tapped', (tester) async {
      var tapCount = 0;
      await tester.pumpWidget(
        _wrap(FloatingAnalysisActionButton(onPressed: () => tapCount++)),
      );
      await tester.pump(const Duration(milliseconds: 240));

      await tester.tap(find.byKey(FloatingAnalysisActionButton.buttonKey));
      await tester.pump();

      expect(tapCount, 1);
    });

    testWidgets('keeps disabled state non-interactive', (tester) async {
      await tester.pumpWidget(
        _wrap(const FloatingAnalysisActionButton(onPressed: null)),
      );
      await tester.pump(const Duration(milliseconds: 240));

      final button = tester.widget<FilledButton>(
        find.byKey(FloatingAnalysisActionButton.buttonKey),
      );
      expect(button.onPressed, isNull);
    });
  });

  group('AnalysisScrollHint', () {
    testWidgets('moves downward then disappears after about two seconds',
        (tester) async {
      await tester.pumpWidget(
        _wrap(const AnalysisScrollHint(duration: Duration(seconds: 2))),
      );

      expect(find.byKey(AnalysisScrollHint.hintKey), findsOneWidget);
      expect(find.text('往下滑'), findsOneWidget);
      expect(
        find.bySemanticsLabel('分析內容會在下方陸續出現，請往下滑'),
        findsOneWidget,
      );
      final initialY =
          tester.getTopLeft(find.byKey(AnalysisScrollHint.hintKey)).dy;

      await tester.pump(const Duration(seconds: 1));
      final laterY =
          tester.getTopLeft(find.byKey(AnalysisScrollHint.hintKey)).dy;
      expect(laterY, greaterThan(initialY));

      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pump();
      expect(find.byKey(AnalysisScrollHint.hintKey), findsNothing);
    });

    testWidgets('respects reduced motion while retaining the timed cue',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child:
                const AnalysisScrollHint(duration: Duration(milliseconds: 300)),
          ),
        ),
      );

      final initialY =
          tester.getTopLeft(find.byKey(AnalysisScrollHint.hintKey)).dy;
      await tester.pump(const Duration(milliseconds: 150));
      final laterY =
          tester.getTopLeft(find.byKey(AnalysisScrollHint.hintKey)).dy;
      expect(laterY, initialY);

      await tester.pump(const Duration(milliseconds: 150));
      expect(find.byKey(AnalysisScrollHint.hintKey), findsNothing);
    });
  });
}
