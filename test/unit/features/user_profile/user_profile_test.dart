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
            PracticeGoal.comfortableChat,
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

    test('stuckPoints exceeds max throws', () {
      expect(
        () => UserProfile.create(
          stuckPoints: StuckPoint.values.take(3).toList(),
          updatedAt: DateTime.utc(2026),
        ),
        throwsArgumentError,
      );
    });

    test('isEmpty is false when only stuckPoints set', () {
      final p = UserProfile.create(
        stuckPoints: [StuckPoint.fadesOut],
        updatedAt: DateTime.utc(2026),
      );
      expect(p.isEmpty, isFalse);
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

  // 規格 PR-8「最近的狀況」：60 字、要有寫下時間、14 天內才算新的。
  group('recentNote', () {
    final ts = DateTime.utc(2026, 10, 21, 12);

    test('trims, keeps the date, and counts toward isEmpty', () {
      final p = UserProfile.create(
        recentNote: '  這週很忙  ',
        recentNoteUpdatedAt: ts,
        updatedAt: ts,
      );
      expect(p.recentNote, '這週很忙');
      expect(p.recentNoteUpdatedAt, ts);
      expect(p.isEmpty, isFalse);
    });

    test('blank note drops both fields', () {
      final p = UserProfile.create(
        recentNote: '   ',
        recentNoteUpdatedAt: ts,
        updatedAt: ts,
      );
      expect(p.recentNote, isNull);
      expect(p.recentNoteUpdatedAt, isNull);
      expect(p.isEmpty, isTrue);
    });

    test('over 60 chars or missing date throws', () {
      expect(
        () => UserProfile.create(
          recentNote: 'a' * (UserProfile.maxRecentNoteLength + 1),
          recentNoteUpdatedAt: ts,
          updatedAt: ts,
        ),
        throwsArgumentError,
      );
      expect(
        () => UserProfile.create(recentNote: '這週很忙', updatedAt: ts),
        throwsArgumentError,
      );
    });

    // 「14 天後會自動不再提供給教練」：滿 14 × 24 小時就不算新的（PR-8 主審 1 殘餘）。
    test('fresh until 14 full days have passed', () {
      UserProfile written(Duration ago) => UserProfile.create(
            recentNote: '這週很忙',
            recentNoteUpdatedAt: ts.subtract(ago),
            updatedAt: ts,
          );
      final almost = written(const Duration(days: 13, hours: 23, minutes: 59));
      expect(almost.recentNoteAgeDays(ts), 13);
      expect(almost.recentNoteIsFresh(ts), isTrue);
      final full = written(const Duration(days: 14));
      expect(full.recentNoteAgeDays(ts), 14);
      expect(full.recentNoteIsFresh(ts), isFalse);
      expect(UserProfile.create(updatedAt: ts).recentNoteIsFresh(ts), isFalse);
    });

    // PR-8 主審 1 P2：時間在未來（裝置時鐘曾經設錯）不算新的，免得有效期被拉長。
    test('a timestamp in the future is not fresh', () {
      final future = UserProfile.create(
        recentNote: '這週很忙',
        recentNoteUpdatedAt: ts.add(const Duration(days: 365)),
        updatedAt: ts,
      );
      expect(future.recentNoteIsFresh(ts), isFalse);
      expect(future.recentNoteAgeDays(ts), lessThan(0));
    });

    // PR-8 主審 1 P2：跟輸入框一樣算看得到的字數，emoji 不會因為佔兩個 UTF-16
    // 單位就存不進去。
    test('counts visible characters, so 59 字＋1 個 emoji 存得進去', () {
      final note = '${'忙' * 59}😀';
      expect(note.length, 61);
      final p = UserProfile.create(
        recentNote: note,
        recentNoteUpdatedAt: ts,
        updatedAt: ts,
      );
      expect(p.recentNote, note);
      expect(
        () => UserProfile.create(
          recentNote: '$note忙',
          recentNoteUpdatedAt: ts,
          updatedAt: ts,
        ),
        throwsArgumentError,
      );
    });
  });
}
