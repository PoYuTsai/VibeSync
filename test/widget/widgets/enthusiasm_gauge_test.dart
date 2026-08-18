import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/shared/widgets/enthusiasm_gauge.dart';

void main() {
  group('EnthusiasmGauge', () {
    testWidgets('displays correct score', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: EnthusiasmGauge(score: 72)),
        ),
      );

      // 分數是 0→72 的 count-up 揭曉，等動畫收斂才停在終點值。
      await tester.pumpAndSettle();
      expect(find.text('72/100'), findsOneWidget);
    });

    testWidgets('displays cold icon for low score', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: EnthusiasmGauge(score: 25)),
        ),
      );

      expect(find.byIcon(TablerIcons.snowflake), findsOneWidget);
      expect(find.text('投入偏低'), findsOneWidget);
    });

    testWidgets('displays warm icon for moderate score', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: EnthusiasmGauge(score: 45)),
        ),
      );

      expect(find.byIcon(TablerIcons.sun_low), findsOneWidget);
      expect(find.text('有在回應'), findsOneWidget);
    });

    testWidgets('displays hot icon for high score', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: EnthusiasmGauge(score: 75)),
        ),
      );

      expect(find.byIcon(TablerIcons.flame), findsOneWidget);
      expect(find.text('投入明顯'), findsOneWidget);
    });

    testWidgets('displays veryHot icon for very high score', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: EnthusiasmGauge(score: 90)),
        ),
      );

      expect(find.byIcon(TablerIcons.hearts), findsOneWidget);
      expect(find.text('高度投入'), findsOneWidget);
    });
  });
}
