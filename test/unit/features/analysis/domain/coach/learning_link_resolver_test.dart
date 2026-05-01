import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/coach/coach_action_type.dart';
import 'package:vibesync/features/analysis/domain/coach/learning_link_resolver.dart';
import 'package:vibesync/features/learning/data/articles_data.dart';

void main() {
  group('LearningLinkResolver.resolve', () {
    test('should return null for softInvite when no exact article exists', () {
      expect(LearningLinkResolver.resolve(CoachActionType.softInvite), isNull);
    });

    test('should return article 10 for lowerPressureReply', () {
      expect(
        LearningLinkResolver.resolve(CoachActionType.lowerPressureReply),
        '10',
      );
    });

    test('should return article 14 for extendTopicStoryFrame', () {
      expect(
        LearningLinkResolver.resolve(CoachActionType.extendTopicStoryFrame),
        '14',
      );
    });

    test('should return article 11 for emotionalResonance', () {
      expect(
        LearningLinkResolver.resolve(CoachActionType.emotionalResonance),
        '11',
      );
    });

    test('should return article 12 for rightSizeReply', () {
      expect(
        LearningLinkResolver.resolve(CoachActionType.rightSizeReply),
        '12',
      );
    });

    test('should return article 3 for playfulReply', () {
      expect(
        LearningLinkResolver.resolve(CoachActionType.playfulReply),
        '3',
      );
    });

    test('should return null for pausePursuit when no exact article exists',
        () {
      expect(
        LearningLinkResolver.resolve(CoachActionType.pausePursuit),
        isNull,
      );
    });

    test('should return article 2 for preferenceSignal', () {
      expect(
        LearningLinkResolver.resolve(CoachActionType.preferenceSignal),
        '2',
      );
    });

    test('should return article 18 for fitCheck', () {
      expect(LearningLinkResolver.resolve(CoachActionType.fitCheck), '18');
    });

    test(
        'should reference an existing article id whenever resolver returns non-null',
        () {
      for (final type in CoachActionType.values) {
        final id = LearningLinkResolver.resolve(type);
        if (id == null) continue;
        final exists = articles.any((a) => a.id == id);
        expect(
          exists,
          isTrue,
          reason:
              '$type maps to articleId "$id" but no such article in articles',
        );
      }
    });
  });
}
