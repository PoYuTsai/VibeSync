import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_result.dart';
import 'package:vibesync/features/analysis/presentation/widgets/psychology_card.dart';

void main() {
  testWidgets('shows investment signal without early-game proving language',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PsychologyCard(
            psychology: PsychologyAnalysis(
              subtext: '她對你有好奇，正在觀察你是否有趣。',
              qualificationSignal: true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('她有主動投入訊號'), findsOneWidget);
    expect(find.textContaining('證明自己'), findsNothing);
    expect(find.textContaining('Qualification Signal'), findsNothing);
  });

  testWidgets('uses user-facing interaction-test language', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PsychologyCard(
            psychology: PsychologyAnalysis(
              subtext: '她在測你的穩定感。',
              shitTestDetected: true,
              shitTestSuggestion: '不要急著解釋，穩定接住就好。',
            ),
          ),
        ),
      ),
    );

    expect(find.text('互動測試訊號'), findsOneWidget);
    expect(find.textContaining('廢測'), findsNothing);
  });
}
