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
        onFollowProgress: () {},
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
        onFollowProgress: () {},
      );

      expect(overlay, isA<FloatingAnalysisActionButton>());
    });

    test('failed stream keeps a shortcut to the retry area', () {
      final overlay = buildAnalysisFloatingOverlay(
        showStartAction: false,
        isAnalyzing: false,
        analysisCompleted: false,
        streamInterrupted: true,
        onStart: () {},
        onFollowProgress: () {},
      );

      expect(overlay, isA<AnalysisScrollHint>());
      expect((overlay! as AnalysisScrollHint).interrupted, isTrue);
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
    testWidgets('stays visible for the full stream and jumps on tap',
        (tester) async {
      var tapCount = 0;
      await tester.pumpWidget(
        _wrap(AnalysisScrollHint(onPressed: () => tapCount++)),
      );

      expect(find.byKey(AnalysisScrollHint.hintKey), findsOneWidget);
      expect(find.text('跟到最新'), findsOneWidget);
      expect(
        find.bySemanticsLabel('分析內容會在下方陸續出現，點一下跟到最新進度'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(AnalysisScrollHint.hintKey));
      await tester.pump();
      expect(tapCount, 1);

      await tester.pump(const Duration(seconds: 30));
      expect(find.byKey(AnalysisScrollHint.hintKey), findsOneWidget);
    });

    testWidgets('following and interrupted states use explicit labels',
        (tester) async {
      await tester.pumpWidget(
        _wrap(const AnalysisScrollHint(isFollowing: true)),
      );
      expect(find.text('跟隨進度'), findsOneWidget);

      await tester.pumpWidget(
        _wrap(const AnalysisScrollHint(interrupted: true)),
      );
      await tester.pump();
      expect(find.text('查看中斷'), findsOneWidget);
      expect(
        find.bySemanticsLabel('分析中斷，點一下查看保留內容與重試選項'),
        findsOneWidget,
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(tester.binding.transientCallbackCount, 0,
          reason: 'Interrupted state must not keep an invisible ticker alive.');
      await tester.pump(const Duration(seconds: 5));
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('reduced motion keeps a static persistent action',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: const AnalysisScrollHint(),
          ),
        ),
      );

      final initialY =
          tester.getTopLeft(find.byKey(AnalysisScrollHint.hintKey)).dy;
      await tester.pump(const Duration(seconds: 5));
      final laterY =
          tester.getTopLeft(find.byKey(AnalysisScrollHint.hintKey)).dy;
      expect(laterY, initialY);
      expect(find.byKey(AnalysisScrollHint.hintKey), findsOneWidget);
    });
  });
}
