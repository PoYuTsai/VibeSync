import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/opener/presentation/widgets/opener_generation_progress.dart';

Widget _wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

void main() {
  group('OpenerGenerationProgress.phrasesFor', () {
    test('screenshot path leads with reading the screenshot', () {
      final phrases = OpenerGenerationProgress.phrasesFor(hasImages: true);
      expect(phrases.first, contains('截圖'));
      expect(phrases.length, greaterThanOrEqualTo(3));
    });

    test('manual path never mentions screenshots', () {
      final phrases = OpenerGenerationProgress.phrasesFor(hasImages: false);
      expect(phrases.any((p) => p.contains('截圖')), isFalse);
      expect(phrases.length, greaterThanOrEqualTo(3));
    });

    test('final stage stays honest when generation takes longer', () {
      for (final phrases in [
        kOpenerScreenshotProgressPhrases,
        kOpenerManualProgressPhrases,
      ]) {
        expect(phrases.last, '還在整理開場方向，請保持連線…');
        expect(phrases.last, isNot(contains('快好了')));
      }
    });
  });

  group('OpenerGenerationProgress staged copy', () {
    const testPhrases = ['第一階段', '第二階段', '第三階段'];
    const interval = Duration(seconds: 3);

    testWidgets('shows the first phrase immediately', (tester) async {
      await tester.pumpWidget(_wrap(
        const OpenerGenerationProgress(
          phrases: testPhrases,
          interval: interval,
        ),
      ));

      expect(find.text('第一階段'), findsOneWidget);
      expect(find.text('第二階段'), findsNothing);
    });

    testWidgets('advances one stage per interval', (tester) async {
      await tester.pumpWidget(_wrap(
        const OpenerGenerationProgress(
          phrases: testPhrases,
          interval: interval,
        ),
      ));

      await tester.pump(interval);
      // 讓文字過場動畫走完，舊句才會離開樹。
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('第二階段'), findsOneWidget);
      expect(find.text('第一階段'), findsNothing);
    });

    testWidgets('holds on the last phrase instead of looping', (tester) async {
      await tester.pumpWidget(_wrap(
        const OpenerGenerationProgress(
          phrases: testPhrases,
          interval: interval,
        ),
      ));

      // Advance far beyond the last stage: must clamp, never wrap to stage 1.
      for (var i = 0; i < 10; i++) {
        await tester.pump(interval);
      }
      expect(find.text('第三階段'), findsOneWidget);
      expect(find.text('第一階段'), findsNothing);
    });

    testWidgets('timer stops at the last stage so pumpAndSettle converges',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const OpenerGenerationProgress(
          phrases: testPhrases,
          interval: interval,
        ),
      ));

      await tester.pump(interval);
      await tester.pump(interval);
      expect(find.text('第三階段'), findsOneWidget);

      // With the timer cancelled, the only remaining animation is the spinner;
      // replacing the tree must leave no pending timers (flutter_test 會抓).
      await tester.pumpWidget(_wrap(const SizedBox.shrink()));
    });

    testWidgets('disposing mid-stage cancels the timer', (tester) async {
      await tester.pumpWidget(_wrap(
        const OpenerGenerationProgress(
          phrases: testPhrases,
          interval: interval,
        ),
      ));

      await tester.pump(interval);
      // Still mid-progression; dispose must not leak the periodic timer.
      await tester.pumpWidget(_wrap(const SizedBox.shrink()));
    });

    testWidgets(
        'phrase list changes after mount are ignored (generation snapshot)',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const OpenerGenerationProgress(
          phrases: testPhrases,
          interval: interval,
        ),
      ));
      await tester.pump(interval);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('第二階段'), findsOneWidget);

      // 生成中途 parent rebuild 換了 phrases（例如用戶切 tab 改輸入）：
      // 進度文案必須凍結在生成開始當下的快照，不得跟著漂移。
      await tester.pumpWidget(_wrap(
        const OpenerGenerationProgress(
          phrases: ['漂移一', '漂移二', '漂移三'],
          interval: interval,
        ),
      ));
      await tester.pump();
      expect(find.text('第二階段'), findsOneWidget);
      expect(find.text('漂移二'), findsNothing);

      await tester.pump(interval);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('第三階段'), findsOneWidget);
      expect(find.text('漂移三'), findsNothing);
    });

    testWidgets('single-phrase list never schedules a timer', (tester) async {
      await tester.pumpWidget(_wrap(
        const OpenerGenerationProgress(
          phrases: ['唯一一句'],
          interval: interval,
        ),
      ));

      expect(find.text('唯一一句'), findsOneWidget);
      await tester.pumpWidget(_wrap(const SizedBox.shrink()));
    });
  });
}
