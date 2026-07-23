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
    String? customTopics,
    String? notes,
  }) =>
      UserProfile.create(
        interactionStyle: style,
        secondaryStyle: secondaryStyle,
        practiceGoals: goals,
        topicSeeds: seeds,
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
          goals: const [PracticeGoal.explainLess],
          seeds: const [TopicSeed.fitness, TopicSeed.coffee],
          customTopics: '日劇',
          notes: '我慢熟，希望不要太快邀約',
        ),
        partner: null,
        includePartnerOverride: true,
      )!;

      expect(context, contains('Preferred voice: 幽默'));
      expect(context, contains('輕鬆'));
      expect(context, contains('Practice focus: 減少解釋'));
      expect(context, contains('更短、更有留白'));
      expect(context, contains('Topic seeds: 健身、咖啡、日劇'));
      expect(context, contains('Notes: 我慢熟，希望不要太快邀約'));
      expect(context, contains('1.8x 黃金法則優先'));
      expect(context, contains('不要替用戶假裝成另一個人'));
    });

    test('partner override wins when it is trusted', () {
      final context = builder.buildForAnalysis(
        global: profile(
          style: InteractionStyle.gentle,
          goals: const [PracticeGoal.reduceAnxiety],
          notes: '全域備註',
        ),
        partner: override(
          style: InteractionStyle.direct,
          goals: const [PracticeGoal.softInvite],
          notes: '這位對象喜歡乾脆一點',
        ),
        includePartnerOverride: true,
      )!;

      expect(context, contains('Preferred voice: 直接'));
      expect(context, contains('模糊邀約'));
      expect(context, contains('這位對象喜歡乾脆一點'));
      expect(context, isNot(contains('全域備註')));
      expect(context, isNot(contains('溫柔')));
    });

    test('ignores partner override when Spec 3 flags partner data', () {
      final context = builder.buildForAnalysis(
        global: profile(
          style: InteractionStyle.gentle,
          goals: const [PracticeGoal.reduceAnxiety],
          notes: '全域低壓',
        ),
        partner: override(
          style: InteractionStyle.direct,
          goals: const [PracticeGoal.softInvite],
          notes: '疑似混入的對象備註',
        ),
        includePartnerOverride: false,
      )!;

      expect(context, contains('Preferred voice: 溫柔'));
      expect(context, contains('降低焦慮'));
      expect(context, contains('全域低壓'));
      expect(context, isNot(contains('疑似混入的對象備註')));
      expect(context, isNot(contains('模糊邀約')));
    });
  });

  group('EffectiveStylePromptBuilder style pair', () {
    test('主-only output is byte-for-byte identical to pre-pair format', () {
      // 最重要回歸保險：所有舊用戶（無副風格）的 prompt 必須一字不差。
      final context = builder.buildForAnalysis(
        global: profile(style: InteractionStyle.humorous),
        partner: null,
        includePartnerOverride: true,
      );

      expect(
        context,
        '- Preferred voice: 幽默；回覆要輕鬆、有畫面感，可以自然幽默但不要硬講笑話\n'
        '- Contract: 這些設定只調整語氣、練習方向和跟進建議；不要替用戶假裝成另一個人。'
        '當前對話、同意與安全、1.8x 黃金法則優先。',
      );
    });

    test('主+副 leads with pair framing, full 主 prompt, 點綴 副 prompt', () {
      final context = builder.buildForAnalysis(
        global: profile(
          style: InteractionStyle.steady,
          secondaryStyle: InteractionStyle.humorous,
        ),
        partner: null,
        includePartnerOverride: true,
      )!;

      expect(context, contains('Preferred voice: 以穩重為主、幽默為輔'));
      expect(context, contains('回覆乾淨穩定，不急著推進，也不要過度解釋'));
      expect(context, contains('點綴'));
      expect(context, contains('不要蓋過主基調'));
      // 副風格絕不用全力描述（防 LLM 把兩風格平均掉）。
      expect(context, isNot(contains('可以自然幽默但不要硬講笑話')));
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

      expect(context, contains('Preferred voice: 直接'));
      expect(context, isNot(contains('為輔')));
      expect(context, isNot(contains('幽默')));
    });

    test('buildForCoachFollowUp carries the same pair voice line', () {
      final context = builder.buildForCoachFollowUp(
        global: profile(
          style: InteractionStyle.gentle,
          secondaryStyle: InteractionStyle.playful,
        ),
        partner: null,
        includePartnerOverride: true,
      )!;

      expect(context, contains('Preferred voice: 以溫柔為主、有玩心為輔'));
      expect(context, contains('不要蓋過主基調'));
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
          goals: const [PracticeGoal.explainLess],
          seeds: const [TopicSeed.fitness, TopicSeed.coffee],
          customTopics: '日劇',
          notes: '我慢熟，開場不要太衝',
        ),
        partner: null,
        includePartnerOverride: true,
      )!;

      expect(context, contains('Preferred voice: 幽默'));
      expect(context, contains('Practice focus: 減少解釋'));
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
      expect(trusted, contains('Preferred voice: 直接'));
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
      expect(flagged, contains('Preferred voice: 溫柔'));
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

      expect(context, contains('Preferred voice: 以穩重為主、有玩心為輔'));
      expect(context, contains('不要蓋過主基調'));
    });

    test('stays within the opener max length', () {
      final context = builder.buildForOpener(
        global: profile(
          style: InteractionStyle.humorous,
          secondaryStyle: InteractionStyle.playful,
          goals: const [
            PracticeGoal.softInvite,
            PracticeGoal.reduceAnxiety,
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
        goals: const [PracticeGoal.explainLess],
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
    test('uses only interaction style + practice goals', () {
      final context = builder.buildForCoachFollowUp(
        global: profile(
          style: InteractionStyle.playful,
          goals: const [PracticeGoal.humorousReply],
          seeds: const [TopicSeed.travel],
          customTopics: '爵士酒吧',
          notes: '不要把這段 notes 送給 Spec 5',
        ),
        partner: null,
        includePartnerOverride: true,
      )!;

      expect(context, contains('Preferred voice: 有玩心'));
      expect(context, contains('幽默回應'));
      expect(context, isNot(contains('爵士酒吧')));
      expect(context, isNot(contains('不要把這段 notes 送給 Spec 5')));
      expect(context, contains('教練語氣與任務 framing'));
    });

    test('captures the A/B-visible style differences we promised users', () {
      final humorous = builder.buildForAnalysis(
        global: profile(
          style: InteractionStyle.humorous,
          goals: const [PracticeGoal.explainLess],
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
          goals: const [PracticeGoal.reduceAnxiety],
        ),
        partner: null,
        includePartnerOverride: true,
      )!;

      expect(humorous, contains('輕鬆'));
      expect(humorous, contains('留白'));
      expect(direct, contains('清楚'));
      expect(direct, contains('低壓的邀約方向'));
      expect(gentle, contains('低壓'));
      expect(gentle, contains('不催促、不追問'));
    });
  });
}
