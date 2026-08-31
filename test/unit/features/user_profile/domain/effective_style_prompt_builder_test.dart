import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/user_profile/domain/entities/partner_style_override.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';
import 'package:vibesync/features/user_profile/domain/services/effective_style_prompt_builder.dart';

// 2026-08-04 拍板：關於我只用來增加 Coach 1:1 對使用者的了解，不再影響
// analyze-chat 五風格回覆／開場白／新話題的實際輸出內容。互動風格／舒適區
// （延伸標記）概念一併移除。buildForAnalysis/buildForOpener/buildForNewTopic
// 因此恆定回傳 null；只有 buildForCoachFollowUp 仍讀取關於我，Batch D
// 會明確帶入主／副風格、句長與問句密度。
void main() {
  const builder = EffectiveStylePromptBuilder();
  final now = DateTime(2026, 5, 5);

  UserProfile profile({
    InteractionStyle? style,
    InteractionStyle? secondaryStyle,
    List<PracticeGoal> goals = const [],
    List<TopicSeed> seeds = const [],
    List<StuckPoint> stuckPoints = const [],
    String? customTopics,
    String? notes,
  }) =>
      UserProfile.create(
        interactionStyle: style,
        secondaryStyle: secondaryStyle,
        practiceGoals: goals,
        topicSeeds: seeds,
        stuckPoints: stuckPoints,
        customTopics: customTopics,
        notes: notes,
        updatedAt: now,
      );

  PartnerStyleOverride override({
    InteractionStyle? style,
    InteractionStyle? secondaryStyle,
    List<PracticeGoal> goals = const [],
    String? notes,
  }) =>
      PartnerStyleOverride.create(
        partnerId: 'p-1',
        interactionStyle: style,
        secondaryStyle: secondaryStyle,
        practiceGoals: goals,
        notes: notes,
        updatedAt: now,
      );

  group('EffectiveStylePromptBuilder.buildForAnalysis is permanently off', () {
    test('returns null even with a fully populated global profile', () {
      expect(
        builder.buildForAnalysis(
          global: profile(
            style: InteractionStyle.humorous,
            goals: const [PracticeGoal.findCompatiblePartner],
            seeds: const [TopicSeed.fitness, TopicSeed.coffee],
            customTopics: '日劇',
            notes: '我慢熟，希望不要太快邀約',
          ),
          partner: null,
          includePartnerOverride: true,
        ),
        isNull,
      );
    });

    test('returns null even with a trusted partner override', () {
      expect(
        builder.buildForAnalysis(
          global: profile(style: InteractionStyle.gentle),
          partner: override(style: InteractionStyle.direct, notes: '直接一點'),
          includePartnerOverride: true,
        ),
        isNull,
      );
    });
  });

  group('EffectiveStylePromptBuilder.buildForOpener is permanently off', () {
    test('returns null even with a fully populated global profile', () {
      expect(
        builder.buildForOpener(
          global: profile(
            style: InteractionStyle.humorous,
            goals: const [PracticeGoal.findCompatiblePartner],
            seeds: const [TopicSeed.fitness, TopicSeed.coffee],
            customTopics: '日劇',
            notes: '我慢熟，開場不要太衝',
          ),
          partner: null,
          includePartnerOverride: true,
        ),
        isNull,
      );
    });
  });

  group('EffectiveStylePromptBuilder.buildForNewTopic is permanently off', () {
    test('returns null even with a fully populated global profile', () {
      expect(
        builder.buildForNewTopic(
          global: profile(
            style: InteractionStyle.humorous,
            seeds: const [TopicSeed.fitness, TopicSeed.coffee],
          ),
          partner: null,
          includePartnerOverride: false,
        ),
        isNull,
      );
    });
  });

  group('EffectiveStylePromptBuilder.buildForCoachFollowUp', () {
    test('returns null when global and partner settings are empty', () {
      expect(
        builder.buildForCoachFollowUp(
          global: null,
          partner: null,
          includePartnerOverride: true,
        ),
        isNull,
      );
    });

    test('includes stuck points and boundary notes', () {
      final context = builder.buildForCoachFollowUp(
        global: profile(
          style: InteractionStyle.steady,
          stuckPoints: const [StuckPoint.fadesOut],
          notes: '不要太快邀約',
        ),
        partner: null,
        includePartnerOverride: false,
      );
      expect(context, contains('話題卡住'));
      expect(context, contains('不要太快邀約'));
    });

    test(
        'uses style pair, output shape, practice goals + notes, but not topics',
        () {
      final context = builder.buildForCoachFollowUp(
        global: profile(
          style: InteractionStyle.playful,
          secondaryStyle: InteractionStyle.humorous,
          goals: const [PracticeGoal.humorousReply],
          seeds: const [TopicSeed.travel],
          customTopics: '爵士酒吧',
          notes: '這段 notes 現在批3 拍板要送給 Spec 5',
        ),
        partner: null,
        includePartnerOverride: true,
      )!;

      expect(context, contains('想讓對話更幽默、有來有往'));
      expect(context, contains('主要互動風格：有玩心'));
      expect(context, contains('次要互動風格：幽默'));
      expect(context, contains('建議句長度：短到中短'));
      expect(context, contains('問句密度：低，每則最多 1 個問句'));
      // topics 仍不進 Coach 1:1（只有 stuckPoints/goals/notes 三段）。
      expect(context, isNot(contains('爵士酒吧')));
      expect(context, contains('這段 notes 現在批3 拍板要送給 Spec 5'));
      expect(context, contains('教練語氣與任務框架'));
    });

    test('practice goals alone still resolve without interaction style', () {
      final context = builder.buildForCoachFollowUp(
        global: profile(goals: const [PracticeGoal.softInvite]),
        partner: null,
        includePartnerOverride: false,
      )!;

      expect(context, contains('想約得出來'));
      expect(context, isNot(contains('舒適區')));
      expect(context, isNot(contains('問句密度')));
    });

    test('findCompatiblePartner keeps bidirectional filtering balance', () {
      final context = builder.buildForCoachFollowUp(
        global: profile(
          goals: const [PracticeGoal.findCompatiblePartner],
        ),
        partner: null,
        includePartnerOverride: false,
      )!;

      expect(context, contains('雙向篩選'));
      expect(context, contains('持續投入、尊重界線、生活節奏適配'));
      expect(context, contains('不要為了不設限而忽略不適合訊號'));
      expect(context, contains('不要因單一標籤太早淘汰'));
    });

    test('partner override notes win when trusted, ignored when flagged', () {
      final trusted = builder.buildForCoachFollowUp(
        global: profile(notes: '全域備註'),
        partner: override(notes: '這位對象喜歡乾脆一點'),
        includePartnerOverride: true,
      )!;
      expect(trusted, contains('這位對象喜歡乾脆一點'));
      expect(trusted, isNot(contains('全域備註')));

      final flagged = builder.buildForCoachFollowUp(
        global: profile(notes: '全域備註'),
        partner: override(notes: '疑似混入的對象備註'),
        includePartnerOverride: false,
      )!;
      expect(flagged, contains('全域備註'));
      expect(flagged, isNot(contains('疑似混入的對象備註')));
    });

    test('stays within coachFollowUpMaxChars', () {
      final context = builder.buildForCoachFollowUp(
        global: profile(
          goals: const [
            PracticeGoal.softInvite,
            PracticeGoal.comfortableChat,
            PracticeGoal.buildCloseness,
          ],
          stuckPoints: const [StuckPoint.fadesOut, StuckPoint.leftOnRead],
          notes: 'y' * UserProfile.maxNotesLength,
        ),
        partner: null,
        includePartnerOverride: false,
      )!;

      expect(
        context.length,
        lessThanOrEqualTo(EffectiveStylePromptBuilder.coachFollowUpMaxChars),
      );
    });
  });
}
