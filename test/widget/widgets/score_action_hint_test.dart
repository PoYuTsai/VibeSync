import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_models.dart';
import 'package:vibesync/features/analysis/domain/entities/game_stage.dart';
import 'package:vibesync/shared/widgets/score_action_hint.dart';

void main() {
  group('ScoreActionHint', () {
    testWidgets(
      'high heat shows actionable next-step sourced from gameStage.nextStep',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: ScoreActionHint(
                score: 90,
                gameStage: GameStageInfo(
                  current: GameStage.close,
                  status: GameStageStatus.canAdvance,
                  nextStep: '提議週末一起去看那部電影',
                ),
                recommendation: FinalRecommendation(
                  pick: 'extend',
                  content: '剛好我也想去，週六下午有空嗎？',
                  reason: '趁熱拋出具體時間能降低對方拒絕成本',
                  psychology: '具體選項比開放邀請更容易成行',
                ),
              ),
            ),
          ),
        );

        expect(find.text('下一步'), findsOneWidget);
        expect(find.textContaining('提議週末一起去看那部電影'), findsOneWidget);
        expect(find.textContaining('趁熱拋出具體時間'), findsOneWidget);
        expect(find.textContaining('週六下午'), findsOneWidget);
      },
    );

    testWidgets(
      'low heat suppresses meeting-suggesting payload and falls back to tier hint',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: ScoreActionHint(
                score: 20,
                gameStage: GameStageInfo(
                  current: GameStage.opening,
                  nextStep: '直接約她出來吃飯',
                ),
              ),
            ),
          ),
        );

        for (final keyword in ['見面', '邀約', '約她', '約他', '約出來']) {
          expect(
            find.textContaining(keyword),
            findsNothing,
            reason:
                'low heat must not surface meeting-related token "$keyword"',
          );
        }
        expect(find.text('下一步'), findsOneWidget);
        expect(find.textContaining('觀察'), findsOneWidget);
      },
    );

    testWidgets(
      'low heat suppresses meeting-suggesting recommendation body and example',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: ScoreActionHint(
                score: 35,
                gameStage: GameStageInfo(
                  current: GameStage.premise,
                  nextStep: '提議週末一起去看電影',
                ),
                recommendation: FinalRecommendation(
                  pick: 'extend',
                  content: '週末要不要一起去喝咖啡？',
                  reason: '趁熱邀約會讓關係升溫',
                  psychology: '低門檻邀請降低壓力',
                ),
              ),
            ),
          ),
        );

        expect(find.textContaining('週末一起'), findsNothing);
        expect(find.textContaining('喝咖啡'), findsNothing);
        expect(find.textContaining('邀約'), findsNothing);
        expect(find.text('試試這樣回'), findsNothing);
        expect(find.textContaining('共同點'), findsOneWidget);
      },
    );

    testWidgets(
      'missing payload renders safe tier fallback without crash',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: ScoreActionHint(
                score: 50,
                recommendation: FinalRecommendation(
                  pick: 'extend',
                  content: '',
                  reason: '',
                  psychology: '',
                ),
              ),
            ),
          ),
        );

        expect(find.text('下一步'), findsOneWidget);
        expect(find.textContaining('共同點'), findsOneWidget);
      },
    );
  });
}
