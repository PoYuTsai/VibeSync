import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/coach/coach_action_type.dart';
import 'package:vibesync/features/analysis/domain/coach/learning_link_resolver.dart';

void main() {
  group('LearningLinkResolver.resolve', () {
    test('softInvite -> null (no exact article in current 20-set)', () {
      expect(LearningLinkResolver.resolve(CoachActionType.softInvite), isNull);
    });

    test('lowerPressureReply -> 10', () {
      expect(
        LearningLinkResolver.resolve(CoachActionType.lowerPressureReply),
        '10',
      );
    });

    test('extendTopicStoryFrame -> 14', () {
      expect(
        LearningLinkResolver.resolve(CoachActionType.extendTopicStoryFrame),
        '14',
      );
    });

    test('emotionalResonance -> 11', () {
      expect(
        LearningLinkResolver.resolve(CoachActionType.emotionalResonance),
        '11',
      );
    });

    test('rightSizeReply -> 12', () {
      expect(
        LearningLinkResolver.resolve(CoachActionType.rightSizeReply),
        '12',
      );
    });

    test('playfulReply -> 3', () {
      expect(
        LearningLinkResolver.resolve(CoachActionType.playfulReply),
        '3',
      );
    });

    test('pausePursuit -> null (no exact article in current 20-set)', () {
      expect(LearningLinkResolver.resolve(CoachActionType.pausePursuit), isNull);
    });

    test('preferenceSignal -> 2', () {
      expect(
        LearningLinkResolver.resolve(CoachActionType.preferenceSignal),
        '2',
      );
    });

    test('fitCheck -> 18', () {
      expect(LearningLinkResolver.resolve(CoachActionType.fitCheck), '18');
    });
  });
}
