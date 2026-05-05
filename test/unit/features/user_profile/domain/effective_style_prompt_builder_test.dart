import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/user_profile/domain/entities/partner_style_override.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';
import 'package:vibesync/features/user_profile/domain/services/effective_style_prompt_builder.dart';

void main() {
  const builder = EffectiveStylePromptBuilder();
  final now = DateTime(2026, 5, 5);

  UserProfile profile({
    InteractionStyle? style,
    List<PracticeGoal> goals = const [],
    List<TopicSeed> seeds = const [],
    String? customTopics,
    String? notes,
  }) =>
      UserProfile.create(
        interactionStyle: style,
        practiceGoals: goals,
        topicSeeds: seeds,
        customTopics: customTopics,
        notes: notes,
        updatedAt: now,
      );

  PartnerStyleOverride override({
    InteractionStyle? style,
    List<PracticeGoal> goals = const [],
    String? notes,
  }) =>
      PartnerStyleOverride.create(
        partnerId: 'p-1',
        interactionStyle: style,
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
