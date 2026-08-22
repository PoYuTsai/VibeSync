import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/shared/widgets/score_hero_card.dart';

void main() {
  testWidgets('分數卡明確限定為對方這次的文字投入訊號', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            child: ScoreHeroCard(score: 72, previousScore: 65),
          ),
        ),
      ),
    );

    expect(find.text('對方這次的投入度'), findsOneWidget);
    expect(find.text('投入明顯'), findsOneWidget);
    expect(find.text('這次投入訊號明顯'), findsOneWidget);
    expect(
      find.text('只反映這次互動中的文字訊號，不代表關係進度。'),
      findsOneWidget,
    );
    expect(find.text('較上次 +7，只比較兩次互動'), findsOneWidget);
    expect(find.textContaining('對話健康'), findsNothing);
    // 可見尺度以 90 為滿分：任何 /100 字樣都是違規。
    expect(find.textContaining('/100'), findsNothing);
  });

  testWidgets('圓環以 90 為滿分：90 分滿圈、45 分半圈（閉環驗收 15）', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 420, child: ScoreHeroCard(score: 90)),
        ),
      ),
    );
    var ring = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(ring.value, 1.0);
    expect(find.text('90'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 420, child: ScoreHeroCard(score: 45)),
        ),
      ),
    );
    ring = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(ring.value, 0.5);
  });
}
