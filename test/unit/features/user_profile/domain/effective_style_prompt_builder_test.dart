import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/user_profile/domain/entities/partner_style_override.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';
import 'package:vibesync/features/user_profile/domain/services/effective_style_prompt_builder.dart';

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

  group('EffectiveStylePromptBuilder.buildForAnalysis', () {
    test('returns null when global and partner settings are empty', () {
      expect(
        builder.buildForAnalysis(
          global: null,
          partner: null,
          includePartnerOverride: true,
        ),
        isNull,
      );
    });

    test('turns global About Me into compact prompt context', () {
      final context = builder.buildForAnalysis(
        global: profile(
          style: InteractionStyle.humorous,
          goals: const [PracticeGoal.findCompatiblePartner],
          seeds: const [TopicSeed.fitness, TopicSeed.coffee],
          customTopics: '日劇',
          notes: '我慢熟，希望不要太快邀約',
        ),
        partner: null,
        includePartnerOverride: true,
      )!;

      expect(context, contains('使用者目前的舒適區：幽默'));
      expect(context, contains('不要因為舒適區而收斂任何一種'));
      expect(context, contains('Practice focus: 想找到聊得來的對象'));
      expect(context, contains('不要急著篩選或設限'));
      expect(context, contains('Topic seeds: 健身、咖啡、日劇'));
      expect(context, contains('Notes: 我慢熟，希望不要太快邀約'));
      expect(context, contains('1.8x 黃金法則優先'));
      expect(context, contains('不要替用戶假裝成另一個人'));
    });

    test('partner override wins when it is trusted', () {
      final context = builder.buildForAnalysis(
        global: profile(
          style: InteractionStyle.gentle,
          goals: const [PracticeGoal.comfortableChat],
          notes: '全域備註',
        ),
        partner: override(
          style: InteractionStyle.direct,
          goals: const [PracticeGoal.softInvite],
          notes: '這位對象喜歡乾脆一點',
        ),
        includePartnerOverride: true,
      )!;

      expect(context, contains('使用者目前的舒適區：直接'));
      expect(context, contains('想約得出來'));
      expect(context, contains('這位對象喜歡乾脆一點'));
      expect(context, isNot(contains('全域備註')));
      expect(context, isNot(contains('溫柔')));
    });

    test('ignores partner override when Spec 3 flags partner data', () {
      final context = builder.buildForAnalysis(
        global: profile(
          style: InteractionStyle.gentle,
          goals: const [PracticeGoal.comfortableChat],
          notes: '全域低壓',
        ),
        partner: override(
          style: InteractionStyle.direct,
          goals: const [PracticeGoal.softInvite],
          notes: '疑似混入的對象備註',
        ),
        includePartnerOverride: false,
      )!;

      expect(context, contains('使用者目前的舒適區：溫柔'));
      expect(context, contains('想先能自在聊天'));
      expect(context, contains('全域低壓'));
      expect(context, isNot(contains('疑似混入的對象備註')));
      expect(context, isNot(contains('想約得出來')));
    });
  });

  group('EffectiveStylePromptBuilder style pair', () {
    test('comfort-zone framing never collapses to a template instruction', () {
      final context = builder.buildForAnalysis(
        global: profile(style: InteractionStyle.humorous),
        partner: null,
        includePartnerOverride: true,
      );

      expect(context, isNot(contains('Preferred voice')));
      expect(context, contains('這不是你要模仿的模板'));
      expect(context, contains('不要因為舒適區而收斂任何一種'));
    });

    test('主+副 comfort-zone pair description renders as 以X為主、Y為輔', () {
      final context = builder.buildForAnalysis(
        global: profile(
          style: InteractionStyle.steady,
          secondaryStyle: InteractionStyle.humorous,
        ),
        partner: null,
        includePartnerOverride: true,
      )!;

      expect(context, contains('使用者目前的舒適區：以穩重為主、幽默為輔'));
      expect(context, contains('不要因為舒適區而收斂任何一種'));
      expect(context, contains('至少一種要明顯超出他的舒適區'));
    });

    test('partner 主-only pair beats global 主+副 atomically in prompt', () {
      final context = builder.buildForAnalysis(
        global: profile(
          style: InteractionStyle.steady,
          secondaryStyle: InteractionStyle.humorous,
        ),
        partner: override(style: InteractionStyle.direct),
        includePartnerOverride: true,
      )!;

      expect(context, contains('使用者目前的舒適區：直接'));
      expect(context, isNot(contains('為輔')));
      expect(context, isNot(contains('幽默')));
    });

    test('buildForCoachFollowUp carries the same pair comfort-zone line', () {
      final context = builder.buildForCoachFollowUp(
        global: profile(
          style: InteractionStyle.gentle,
          secondaryStyle: InteractionStyle.playful,
        ),
        partner: null,
        includePartnerOverride: true,
      )!;

      expect(context, contains('使用者目前的舒適區：以溫柔為主、有玩心為輔'));
      expect(context, contains('這張建議可以明顯超出他的舒適區'));
      expect(context, isNot(contains('五種回覆風格')));
    });
  });

  group('EffectiveStylePromptBuilder.buildForOpener', () {
    test('returns null when global and partner settings are empty', () {
      expect(
        builder.buildForOpener(
          global: null,
          partner: null,
          includePartnerOverride: true,
        ),
        isNull,
      );
    });

    test('turns global About Me into opener style context', () {
      final context = builder.buildForOpener(
        global: profile(
          style: InteractionStyle.humorous,
          goals: const [PracticeGoal.findCompatiblePartner],
          seeds: const [TopicSeed.fitness, TopicSeed.coffee],
          customTopics: '日劇',
          notes: '我慢熟，開場不要太衝',
        ),
        partner: null,
        includePartnerOverride: true,
      )!;

      expect(context, contains('使用者目前的舒適區：幽默'));
      expect(context, contains('Practice focus: 想找到聊得來的對象'));
      expect(context, contains('Topic seeds: 健身、咖啡、日劇'));
      expect(context, contains('Notes: 我慢熟，開場不要太衝'));
      // opener 專用 contract：只調語氣，對方線索與安全優先。
      expect(context, contains('只用來調整開場白語氣'));
      expect(context, contains('不要替用戶假裝成另一個人'));
      expect(context, contains('對方可見線索、明確禁忌與安全分寸永遠優先'));
    });

    test('topic seeds carry the no-fabricated-common-ground guard', () {
      final context = builder.buildForOpener(
        global: profile(seeds: const [TopicSeed.coffee]),
        partner: null,
        includePartnerOverride: true,
      )!;

      // 用戶自己的興趣絕不能被當成「和對方的共同點」素材。
      expect(context, contains('這是用戶自己的興趣'));
      expect(context, contains('真實交集'));
      expect(context, contains('絕不假造共同點'));
      // analyze 版的措辭不該滲進來（那句沒有共同點守門）。
      expect(context, isNot(contains('只在自然時作為延伸素材')));
    });

    test('partner override wins when trusted, suspended when flagged', () {
      final trusted = builder.buildForOpener(
        global: profile(style: InteractionStyle.gentle, notes: '全域備註'),
        partner: override(
          style: InteractionStyle.direct,
          notes: '對這位直接一點',
        ),
        includePartnerOverride: true,
      )!;
      expect(trusted, contains('使用者目前的舒適區：直接'));
      expect(trusted, contains('對這位直接一點'));
      expect(trusted, isNot(contains('全域備註')));

      final flagged = builder.buildForOpener(
        global: profile(style: InteractionStyle.gentle, notes: '全域備註'),
        partner: override(
          style: InteractionStyle.direct,
          notes: '疑似混入的對象備註',
        ),
        includePartnerOverride: false,
      )!;
      expect(flagged, contains('使用者目前的舒適區：溫柔'));
      expect(flagged, contains('全域備註'));
      expect(flagged, isNot(contains('疑似混入的對象備註')));
    });

    test('carries the 主+副 pair voice line', () {
      final context = builder.buildForOpener(
        global: profile(
          style: InteractionStyle.steady,
          secondaryStyle: InteractionStyle.playful,
        ),
        partner: null,
        includePartnerOverride: true,
      )!;

      expect(context, contains('使用者目前的舒適區：以穩重為主、有玩心為輔'));
      expect(context, contains('不要因為舒適區而收斂任何一種'));
    });

    test('stays within the opener max length', () {
      final context = builder.buildForOpener(
        global: profile(
          style: InteractionStyle.humorous,
          secondaryStyle: InteractionStyle.playful,
          goals: const [
            PracticeGoal.softInvite,
            PracticeGoal.comfortableChat,
            PracticeGoal.buildCloseness,
          ],
          seeds: const [
            TopicSeed.fitness,
            TopicSeed.travel,
            TopicSeed.coffee,
          ],
          customTopics: 'x' * UserProfile.maxCustomTopicsLength,
          notes: 'y' * UserProfile.maxNotesLength,
        ),
        partner: null,
        includePartnerOverride: true,
      )!;

      expect(
        context.length,
        lessThanOrEqualTo(EffectiveStylePromptBuilder.openerMaxChars),
      );
    });
  });

  group('EffectiveStylePromptBuilder.buildForNewTopic', () {
    test('returns null when global and partner settings are empty', () {
      expect(
        builder.buildForNewTopic(
          global: null,
          partner: null,
          includePartnerOverride: true,
        ),
        isNull,
      );
    });

    test('topic seeds＝使用者自己的興趣：可自我揭露、不得聲稱對方也喜歡', () {
      final context = builder.buildForNewTopic(
        global: profile(
          style: InteractionStyle.humorous,
          seeds: const [TopicSeed.fitness, TopicSeed.coffee],
        ),
        partner: null,
        includePartnerOverride: false,
      )!;

      expect(context, contains('這是用戶自己的興趣'));
      expect(context, contains('可以自然分享自身生活畫面'));
      expect(context, contains('不得聲稱對方也喜歡'));
      expect(context, contains('自然展現生活感、品味或行動力'));
      // visible 文字禁 DHV 字面。
      expect(context, isNot(contains('DHV')));
    });

    test('contract：不假裝身份、不覆蓋 consent／低壓互動要求', () {
      final context = builder.buildForNewTopic(
        global: profile(style: InteractionStyle.gentle),
        partner: null,
        includePartnerOverride: false,
      )!;

      expect(context, contains('不得為了配合對方假裝身份、經歷或興趣'));
      expect(context, contains('同意與低壓互動要求永遠優先'));
      expect(context, contains('只調整話題的說法與語氣'));
    });

    test('flagged partner 停用 override、global 仍生效', () {
      final flagged = builder.buildForNewTopic(
        global: profile(style: InteractionStyle.steady),
        partner: override(style: InteractionStyle.playful),
        includePartnerOverride: false,
      )!;
      expect(flagged, contains('穩重'));
      expect(flagged, isNot(contains('有玩心')));

      final trusted = builder.buildForNewTopic(
        global: profile(style: InteractionStyle.steady),
        partner: override(style: InteractionStyle.playful),
        includePartnerOverride: true,
      )!;
      expect(trusted, contains('有玩心'));
    });

    test('stays within newTopicMaxChars', () {
      final context = builder.buildForNewTopic(
        global: profile(
          style: InteractionStyle.playful,
          secondaryStyle: InteractionStyle.humorous,
          goals: const [
            PracticeGoal.softInvite,
            PracticeGoal.buildCloseness,
            PracticeGoal.humorousReply,
          ],
          seeds: const [
            TopicSeed.fitness,
            TopicSeed.travel,
            TopicSeed.coffee,
            TopicSeed.music,
            TopicSeed.photography,
          ],
          customTopics: '手沖咖啡器材、公路車、黑膠',
          notes: '週末常跑咖啡廳，喜歡低壓步調' * 6,
        ),
        partner: null,
        includePartnerOverride: false,
      )!;
      expect(
        context.length,
        lessThanOrEqualTo(EffectiveStylePromptBuilder.newTopicMaxChars),
      );
    });

    test('既有三個 builder 方法 snapshot 不因新增 buildForNewTopic 改變', () {
      final global = profile(
        style: InteractionStyle.humorous,
        goals: const [PracticeGoal.findCompatiblePartner],
        seeds: const [TopicSeed.coffee],
      );
      // 相同輸入下 opener/analysis/coach 三個 slice 的 contract 行不變。
      expect(
        builder.buildForOpener(
          global: global,
          partner: null,
          includePartnerOverride: false,
        ),
        contains('只用來調整開場白語氣與風格'),
      );
      expect(
        builder.buildForAnalysis(
          global: global,
          partner: null,
          includePartnerOverride: false,
        ),
        contains('1.8x 黃金法則優先'),
      );
      expect(
        builder.buildForCoachFollowUp(
          global: global,
          partner: null,
          includePartnerOverride: false,
        ),
        contains('僅用來調整教練語氣與任務 framing'),
      );
    });
  });

  group('EffectiveStylePromptBuilder.buildForCoachFollowUp', () {
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

    test('uses interaction style + practice goals + notes, but not topics',
        () {
      final context = builder.buildForCoachFollowUp(
        global: profile(
          style: InteractionStyle.playful,
          goals: const [PracticeGoal.humorousReply],
          seeds: const [TopicSeed.travel],
          customTopics: '爵士酒吧',
          notes: '這段 notes 現在批3 拍板要送給 Spec 5',
        ),
        partner: null,
        includePartnerOverride: true,
      )!;

      expect(context, contains('使用者目前的舒適區：有玩心'));
      expect(context, contains('想讓對話更幽默、有來有往'));
      // topics 仍不進 Coach 1:1（只有 stuckPoints/goals/notes 三段）。
      expect(context, isNot(contains('爵士酒吧')));
      expect(context, contains('這段 notes 現在批3 拍板要送給 Spec 5'));
      expect(context, contains('教練語氣與任務 framing'));
    });

    test(
        'comfort-zone description differs per style but the stretch '
        'instruction is universal', () {
      final humorous = builder.buildForAnalysis(
        global: profile(
          style: InteractionStyle.humorous,
          goals: const [PracticeGoal.findCompatiblePartner],
        ),
        partner: null,
        includePartnerOverride: true,
      )!;
      final direct = builder.buildForAnalysis(
        global: profile(
          style: InteractionStyle.direct,
          goals: const [PracticeGoal.softInvite],
        ),
        partner: null,
        includePartnerOverride: true,
      )!;
      final gentle = builder.buildForAnalysis(
        global: profile(
          style: InteractionStyle.gentle,
          goals: const [PracticeGoal.comfortableChat],
        ),
        partner: null,
        includePartnerOverride: true,
      )!;

      expect(humorous, contains('使用者目前的舒適區：幽默'));
      expect(direct, contains('使用者目前的舒適區：直接'));
      expect(gentle, contains('使用者目前的舒適區：溫柔'));
      for (final context in [humorous, direct, gentle]) {
        expect(context, contains('不要因為舒適區而收斂任何一種'));
        expect(context, contains('至少一種要明顯超出他的舒適區'));
      }
    });
  });
}
