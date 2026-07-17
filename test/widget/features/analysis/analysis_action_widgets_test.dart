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
}
