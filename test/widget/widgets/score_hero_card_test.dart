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
  });
}
