import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';

void main() {
  group('UserProfile.create', () {
    test('empty inputs normalize to null / empty list', () {
      final p = UserProfile.create(
        interactionStyle: null,
        practiceGoals: const [],
        topicSeeds: const [],
        customTopics: '   ',
        notes: '',
        updatedAt: DateTime(2026, 4, 30),
      );

      expect(p.interactionStyle, isNull);
      expect(p.practiceGoals, isEmpty);
      expect(p.topicSeeds, isEmpty);
      expect(p.customTopics, isNull);
      expect(p.notes, isNull);
    });

    test('trims whitespace on text fields', () {
      final p = UserProfile.create(
        customTopics: '  咖啡、旅行  ',
        notes: '  慢熟  ',
        updatedAt: DateTime(2026, 4, 30),
      );

      expect(p.customTopics, '咖啡、旅行');
      expect(p.notes, '慢熟');
    });

    test('practiceGoals capped at 3 throws when exceeded', () {
      expect(
        () => UserProfile.create(
          practiceGoals: const [
            PracticeGoal.softInvite,
            PracticeGoal.reduceAnxiety,
            PracticeGoal.humorousReply,
            PracticeGoal.buildCloseness,
          ],
          updatedAt: DateTime(2026, 4, 30),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('topicSeeds capped at 5 throws when exceeded', () {
      expect(
        () => UserProfile.create(
          topicSeeds: const [
            TopicSeed.fitness,
            TopicSeed.travel,
            TopicSeed.coffee,
            TopicSeed.music,
            TopicSeed.movies,
            TopicSeed.photography,
          ],
          updatedAt: DateTime(2026, 4, 30),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('customTopics > 60 chars throws', () {
      expect(
        () => UserProfile.create(
          customTopics: 'x' * 61,
          updatedAt: DateTime(2026, 4, 30),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('notes > 100 chars throws', () {
      expect(
        () => UserProfile.create(
          notes: 'x' * 101,
          updatedAt: DateTime(2026, 4, 30),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('UserProfile.isEmpty', () {
    test('all null / empty returns true', () {
      final p = UserProfile.create(updatedAt: DateTime(2026, 4, 30));
      expect(p.isEmpty, isTrue);
    });

    test('any field present returns false', () {
      final p = UserProfile.create(
        interactionStyle: InteractionStyle.gentle,
        updatedAt: DateTime(2026, 4, 30),
      );
      expect(p.isEmpty, isFalse);
    });
  });

  group('UserProfile.create style pair', () {
    final ts = DateTime(2026, 6, 10);

    test('secondary without primary throws', () {
      expect(
        () => UserProfile.create(
          secondaryStyle: InteractionStyle.humorous,
          updatedAt: ts,
        ),
        throwsArgumentError,
      );
    });

    test('secondary equal to primary throws', () {
      expect(
        () => UserProfile.create(
          interactionStyle: InteractionStyle.steady,
          secondaryStyle: InteractionStyle.steady,
          updatedAt: ts,
        ),
        throwsArgumentError,
      );
    });

    test('primary + distinct secondary is valid', () {
      final p = UserProfile.create(
        interactionStyle: InteractionStyle.steady,
        secondaryStyle: InteractionStyle.humorous,
        updatedAt: ts,
      );
      expect(p.interactionStyle, InteractionStyle.steady);
      expect(p.secondaryStyle, InteractionStyle.humorous);
      expect(p.isEmpty, isFalse);
    });

    test('primary-only stays valid (secondary defaults to null)', () {
      final p = UserProfile.create(
        interactionStyle: InteractionStyle.steady,
        updatedAt: ts,
      );
      expect(p.secondaryStyle, isNull);
    });
  });
}
