import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_debrief_card.dart';

void main() {
  testWidgets('PracticeDebriefCard renders optional Game breakdown',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PracticeDebriefCard(
              summary: 'solid',
              strengths: ['hook'],
              watchouts: ['too fast'],
              suggestedLine: 'next line',
              vibe: 'neutral',
              gameBreakdownPhaseReached: 'value stage',
              gameBreakdownMissedVariable: 'investment',
              gameBreakdownFailureState: 'too many questions',
              gameBreakdownNextFirstLine: 'lead with a callback',
              gameBreakdownInviteDirection: 'soft invite',
            ),
          ),
        ),
      ),
    );

    expect(find.text('Game 拆盤'), findsOneWidget);
    expect(find.textContaining('value stage'), findsOneWidget);
    expect(find.textContaining('investment'), findsOneWidget);
    expect(find.textContaining('too many questions'), findsOneWidget);
    expect(find.textContaining('lead with a callback'), findsOneWidget);
    expect(find.textContaining('soft invite'), findsOneWidget);
  });

  testWidgets('PracticeDebriefCard never renders a partial Game breakdown',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PracticeDebriefCard(
            summary: 'solid',
            strengths: ['hook'],
            watchouts: ['too fast'],
            suggestedLine: 'next line',
            vibe: 'neutral',
            gameBreakdownPhaseReached: 'value stage',
          ),
        ),
      ),
    );

    expect(find.text('Game 拆盤'), findsNothing);
    expect(find.textContaining('value stage'), findsNothing);
  });
}
