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
      // Positive assertion pins the flagged code path — without it the
      // denylist below is true-by-construction (the unflagged template
      // also happens not to contain those tokens). If a future refactor
      // routes flagged inputs through unflagged copy, this fails first.
      expect(card.whyNow, contains('資料還不完整'));
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

    test('should pick softInvite when heat is in veryHot range and stage is close',
        () {
      final card = CoachActionPolicy.evaluate(
        heatScore: 90,
        gameStage: const GameStageInfo(
          current: GameStage.close,
          status: GameStageStatus.canAdvance,
          nextStep: '提議週末一起去看那部電影',
        ),
        finalRecommendation: const FinalRecommendation(
          pick: 'extend',
          content: '剛好我也想去，週六下午有空嗎？',
          reason: '趁熱拋出具體時間能降低拒絕成本',
          psychology: '具體選項比開放邀請更容易成行',
        ),
        messages: const [],
        practiceGoals: const [],
        isDataQualityFlagged: false,
      );
      expect(card.actionLabel, '模糊邀約');
      expect(card.suggestedLine, '剛好我也想去，週六下午有空嗎？');
      expect(card.learningLink, isNull);
    });

    test(
        'should pick pausePursuit when heat is cold and nextStep contains meeting keyword',
        () {
      final card = CoachActionPolicy.evaluate(
        heatScore: 20,
        gameStage: const GameStageInfo(
          current: GameStage.opening,
          nextStep: '直接約她出來吃飯',
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
      expect(card.actionLabel, '暫停追問');
      expect(card.suggestedLine, isNull);
    });

    test(
        'should suppress suggestedLine when heat is below 81 and content contains meeting keyword',
        () {
      final card = CoachActionPolicy.evaluate(
        heatScore: 35,
        gameStage: const GameStageInfo(
          current: GameStage.premise,
          nextStep: '提議週末一起去看電影',
        ),
        finalRecommendation: const FinalRecommendation(
          pick: 'extend',
          content: '週末要不要一起去喝咖啡？',
          reason: '趁熱邀約會讓關係升溫',
          psychology: '低門檻邀請降低壓力',
        ),
        messages: const [],
        practiceGoals: const [],
        isDataQualityFlagged: false,
      );
      expect(
        card.suggestedLine,
        isNull,
        reason: 'meeting-keyword content must not surface below heat 81',
      );
    });

    test(
        'should pick pausePursuit (not softInvite) when heat is cold and nextStep contains 見個面',
        () {
      final card = CoachActionPolicy.evaluate(
        heatScore: 25,
        gameStage: const GameStageInfo(
          current: GameStage.opening,
          nextStep: '找機會見個面',
        ),
        finalRecommendation: const FinalRecommendation(
          pick: 'extend',
          content: '想約她出來吃飯',
          reason: '',
          psychology: '',
        ),
        messages: const [],
        practiceGoals: const [],
        isDataQualityFlagged: false,
      );
      expect(card.actionLabel, '暫停追問');
    });
  });
}
