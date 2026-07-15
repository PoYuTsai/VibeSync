import 'package:flutter/material.dart';
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

      expect(find.text('72/100'), findsOneWidget);
    });

    testWidgets('displays cold emoji for low score', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: EnthusiasmGauge(score: 25)),
        ),
      );

      expect(find.text('❄️'), findsOneWidget);
      expect(find.text('投入偏低'), findsOneWidget);
    });

    testWidgets('displays warm emoji for moderate score', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: EnthusiasmGauge(score: 45)),
        ),
      );

      expect(find.text('🌤️'), findsOneWidget);
      expect(find.text('有在回應'), findsOneWidget);
    });

    testWidgets('displays hot emoji for high score', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: EnthusiasmGauge(score: 75)),
        ),
      );

      expect(find.text('🔥'), findsOneWidget);
      expect(find.text('投入明顯'), findsOneWidget);
    });

    testWidgets('displays veryHot emoji for very high score', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: EnthusiasmGauge(score: 90)),
        ),
      );

      expect(find.text('💖'), findsOneWidget);
      expect(find.text('高度投入'), findsOneWidget);
    });
  });
}
