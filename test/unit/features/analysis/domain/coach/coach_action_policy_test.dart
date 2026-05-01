import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/coach/coach_action_card_data.dart';
import 'package:vibesync/features/analysis/domain/coach/coach_action_policy.dart';
import 'package:vibesync/features/analysis/domain/coach/coach_action_type.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_models.dart';
import 'package:vibesync/features/analysis/domain/entities/game_stage.dart';

void main() {
  group('CoachActionType', () {
    test('should expose 9 distinct values matching spec', () {
      expect(CoachActionType.values.length, 9);
      expect(CoachActionType.values.toSet(), {
        CoachActionType.softInvite,
        CoachActionType.lowerPressureReply,
        CoachActionType.extendTopicStoryFrame,
        CoachActionType.emotionalResonance,
        CoachActionType.rightSizeReply,
        CoachActionType.playfulReply,
        CoachActionType.pausePursuit,
        CoachActionType.preferenceSignal,
        CoachActionType.fitCheck,
      });
    });
  });

  group('CoachActionCardData', () {
    test('should be value-equal when all 6 fields match', () {
      const a = CoachActionCardData(
        actionLabel: '模糊邀約',
        whyNow: '熱度 88，可以給具體時間',
        task: '拋一個低門檻邀約',
        suggestedLine: '週六下午有空嗎？',
        avoid: '別問三題',
        learningLink: null,
      );
      const b = CoachActionCardData(
        actionLabel: '模糊邀約',
        whyNow: '熱度 88，可以給具體時間',
        task: '拋一個低門檻邀約',
        suggestedLine: '週六下午有空嗎？',
        avoid: '別問三題',
        learningLink: null,
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('should not be equal when suggestedLine differs', () {
      const a = CoachActionCardData(
        actionLabel: 'x',
        whyNow: 'x',
        task: 'x',
        suggestedLine: 'a',
        avoid: 'x',
        learningLink: null,
      );
      const b = CoachActionCardData(
        actionLabel: 'x',
        whyNow: 'x',
        task: 'x',
        suggestedLine: 'b',
        avoid: 'x',
        learningLink: null,
      );
      expect(a, isNot(equals(b)));
    });
  });

  group('CoachActionPolicy.evaluate', () {
    test('should return fitCheck card when no upstream rule matches', () {
      final card = CoachActionPolicy.evaluate(
        heatScore: 50,
        gameStage: const GameStageInfo(
          current: GameStage.opening,
          nextStep: '',
        ),
        finalRecommendation: const FinalRecommendation(
          pick: 'extend',
          content: '',
          reason: '',
          psychology: '',
        ),
        messages: const [],
        practiceGoals: const [],
        isDataQualityFlagged: false,
      );
      expect(card.actionLabel, '互動品質觀察');
      expect(card.suggestedLine, isNull);
      expect(card.learningLink, '18');
    });

    test('should not surface long-term-trait phrases when partner is flagged',
        () {
      final card = CoachActionPolicy.evaluate(
        heatScore: 50,
        gameStage: const GameStageInfo(
          current: GameStage.opening,
          nextStep: '',
        ),
        finalRecommendation: const FinalRecommendation(
          pick: 'extend',
          content: '',
          reason: '',
          psychology: '',
        ),
        messages: const [],
        practiceGoals: const [],
        isDataQualityFlagged: true,
      );
      for (final forbidden in const [
        '你們之前',
        '上次',
        '通常她',
        '她總是',
        '從歷史看',
      ]) {
        expect(
          card.whyNow.contains(forbidden),
          isFalse,
          reason: 'flagged whyNow leaked long-term-trait token "$forbidden"',
        );
      }
    });
  });
}
