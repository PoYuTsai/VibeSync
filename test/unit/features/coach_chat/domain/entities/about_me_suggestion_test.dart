import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/coach_chat/domain/entities/about_me_suggestion.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';

void main() {
  group('AboutMeSuggestion.fromWire', () {
    test('收卡點與練習重點的固定代碼', () {
      expect(
        AboutMeSuggestion.fromWire(
            {'field': 'stuckPoint', 'key': 'overExplains'}),
        const AboutMeSuggestion.stuckPoint(StuckPoint.overExplains),
      );
      expect(
        AboutMeSuggestion.fromWire(
            {'field': 'practiceGoal', 'key': 'softInvite'}),
        const AboutMeSuggestion.practiceGoal(PracticeGoal.softInvite),
      );
    });

    test('不認得的欄位或代碼當沒有', () {
      for (final raw in <Object?>[
        null,
        'overExplains',
        const ['stuckPoint', 'overExplains'],
        {'field': 'stuckPoint'},
        {'field': 'stuckPoint', 'key': 3},
        {'field': 'stuckPoint', 'key': 'noSuchCode'},
        // 代碼要屬於那個欄位。
        {'field': 'stuckPoint', 'key': 'softInvite'},
        {'field': 'practiceGoal', 'key': 'overExplains'},
        {'field': 'interactionStyle', 'key': 'humorous'},
        {'field': 'topicSeed', 'key': 'travel'},
        {'key': 'overExplains'},
      ]) {
        expect(AboutMeSuggestion.fromWire(raw), isNull, reason: '$raw');
      }
    });
  });

  group('對照關於我', () {
    const stuck = AboutMeSuggestion.stuckPoint(StuckPoint.overExplains);
    const goal = AboutMeSuggestion.practiceGoal(PracticeGoal.softInvite);
    final at = DateTime.utc(2026, 10, 1);

    test('還沒有關於我：不算已經有、也不算滿', () {
      expect(stuck.isIn(null), isFalse);
      expect(stuck.categoryFullIn(null), isFalse);
      expect(goal.isIn(null), isFalse);
      expect(goal.categoryFullIn(null), isFalse);
    });

    test('已經有那個選項', () {
      final profile = UserProfile.create(
        stuckPoints: const [StuckPoint.overExplains],
        practiceGoals: const [PracticeGoal.softInvite],
        updatedAt: at,
      );
      expect(stuck.isIn(profile), isTrue);
      expect(goal.isIn(profile), isTrue);
      expect(
        const AboutMeSuggestion.stuckPoint(StuckPoint.leftOnRead).isIn(profile),
        isFalse,
      );
    });

    test('卡點滿 2 個、練習重點滿 3 個才算滿', () {
      final oneEach = UserProfile.create(
        stuckPoints: const [StuckPoint.fadesOut],
        practiceGoals: const [
          PracticeGoal.comfortableChat,
          PracticeGoal.humorousReply,
        ],
        updatedAt: at,
      );
      expect(stuck.categoryFullIn(oneEach), isFalse);
      expect(goal.categoryFullIn(oneEach), isFalse);
      final full = UserProfile.create(
        stuckPoints: const [StuckPoint.fadesOut, StuckPoint.leftOnRead],
        practiceGoals: const [
          PracticeGoal.comfortableChat,
          PracticeGoal.humorousReply,
          PracticeGoal.buildCloseness,
        ],
        updatedAt: at,
      );
      expect(stuck.categoryFullIn(full), isTrue);
      expect(goal.categoryFullIn(full), isTrue);
    });
  });

  group('AboutMeSuggestion.addTo', () {
    final writtenAt = DateTime.utc(2026, 10, 18, 9);
    final now = DateTime.utc(2026, 10, 21, 12);

    test('還沒有關於我：新建一份，只有這個選項', () {
      final added = const AboutMeSuggestion.stuckPoint(StuckPoint.overExplains)
          .addTo(null, now: now);
      expect(added.stuckPoints, [StuckPoint.overExplains]);
      expect(added.practiceGoals, isEmpty);
      expect(added.updatedAt, now);
      expect(added.recentNote, isNull);
    });

    test('只加這一個，其他欄位照舊，更新時間換成現在', () {
      final before = UserProfile.create(
        interactionStyle: InteractionStyle.humorous,
        practiceGoals: const [PracticeGoal.comfortableChat],
        topicSeeds: const [TopicSeed.travel],
        stuckPoints: const [StuckPoint.fadesOut],
        customTopics: '登山',
        notes: '不要太快邀約',
        updatedAt: writtenAt,
        recentNote: '這週很忙',
        recentNoteUpdatedAt: writtenAt,
      );

      final withStuck =
          const AboutMeSuggestion.stuckPoint(StuckPoint.overExplains)
              .addTo(before, now: now);
      expect(withStuck.stuckPoints, [
        StuckPoint.fadesOut,
        StuckPoint.overExplains,
      ]);
      expect(withStuck.practiceGoals, [PracticeGoal.comfortableChat]);
      expect(withStuck.updatedAt, now);

      final withGoal =
          const AboutMeSuggestion.practiceGoal(PracticeGoal.softInvite)
              .addTo(before, now: now);
      expect(withGoal.practiceGoals, [
        PracticeGoal.comfortableChat,
        PracticeGoal.softInvite,
      ]);
      expect(withGoal.stuckPoints, [StuckPoint.fadesOut]);

      for (final added in [withStuck, withGoal]) {
        expect(added.interactionStyle, InteractionStyle.humorous);
        expect(added.topicSeeds, [TopicSeed.travel]);
        expect(added.customTopics, '登山');
        expect(added.notes, '不要太快邀約');
        // 近況的寫下時間不能被這次加入刷新，不然過期的近況會又送給教練 14 天。
        expect(added.recentNote, '這週很忙');
        expect(added.recentNoteUpdatedAt, writtenAt);
      }
    });

    test('已經有就不重複加', () {
      final before = UserProfile.create(
        stuckPoints: const [StuckPoint.overExplains],
        updatedAt: writtenAt,
      );
      final added = const AboutMeSuggestion.stuckPoint(StuckPoint.overExplains)
          .addTo(before, now: now);
      expect(added.stuckPoints, [StuckPoint.overExplains]);
    });

    test('那一類滿了會丟錯，不會偷偷擠掉舊的', () {
      final full = UserProfile.create(
        stuckPoints: const [StuckPoint.fadesOut, StuckPoint.leftOnRead],
        updatedAt: writtenAt,
      );
      expect(
        () => const AboutMeSuggestion.stuckPoint(StuckPoint.overExplains)
            .addTo(full, now: now),
        throwsArgumentError,
      );
    });
  });
}
