import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/coach/coach_action_card_data.dart';
import 'package:vibesync/features/analysis/domain/coach/coach_action_type.dart';

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
}
