import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/user_profile/domain/entities/partner_style_override.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';
import 'package:vibesync/features/user_profile/domain/services/resolve_effective_style.dart';

void main() {
  final ts = DateTime.utc(2026, 5, 1);
  final globalStyle = UserProfile.create(
    interactionStyle: InteractionStyle.steady,
    practiceGoals: const [PracticeGoal.softInvite],
    notes: 'global notes',
    updatedAt: ts,
  );

  group('resolveEffectiveStyle', () {
    test('returns all global fields when partner override is null', () {
      final r = resolveEffectiveStyle(global: globalStyle, partner: null);
      expect(r.interactionStyle, InteractionStyle.steady);
      expect(r.practiceGoals, [PracticeGoal.softInvite]);
      expect(r.notes, 'global notes');
    });

    test('overrides interactionStyle but inherits goals + notes', () {
      final partner = PartnerStyleOverride.create(
        partnerId: 'p1',
        interactionStyle: InteractionStyle.humorous,
        updatedAt: ts,
      );
      final r = resolveEffectiveStyle(global: globalStyle, partner: partner);
      expect(r.interactionStyle, InteractionStyle.humorous);
      expect(r.practiceGoals, [PracticeGoal.softInvite]);
      expect(r.notes, 'global notes');
    });

    test('overrides practiceGoals when partner has any', () {
      final partner = PartnerStyleOverride.create(
        partnerId: 'p1',
        practiceGoals: const [PracticeGoal.reduceAnxiety],
        updatedAt: ts,
      );
      final r = resolveEffectiveStyle(global: globalStyle, partner: partner);
      expect(r.practiceGoals, [PracticeGoal.reduceAnxiety]);
    });

    test('falls back to global goals when partner goals are empty', () {
      final partner = PartnerStyleOverride.create(
        partnerId: 'p1',
        interactionStyle: InteractionStyle.gentle,
        updatedAt: ts,
      );
      final r = resolveEffectiveStyle(global: globalStyle, partner: partner);
      expect(r.practiceGoals, [PracticeGoal.softInvite]);
    });

    test('overrides notes per-field independently of style/goals', () {
      final partner = PartnerStyleOverride.create(
        partnerId: 'p1',
        notes: '對方慢熟',
        updatedAt: ts,
      );
      final r = resolveEffectiveStyle(global: globalStyle, partner: partner);
      expect(r.interactionStyle, InteractionStyle.steady);
      expect(r.practiceGoals, [PracticeGoal.softInvite]);
      expect(r.notes, '對方慢熟');
    });

    test('returns all-null / empty when both layers null', () {
      final r = resolveEffectiveStyle(global: null, partner: null);
      expect(r.interactionStyle, isNull);
      expect(r.practiceGoals, isEmpty);
      expect(r.notes, isNull);
    });

    test('handles global=null + partner with values', () {
      final partner = PartnerStyleOverride.create(
        partnerId: 'p1',
        interactionStyle: InteractionStyle.direct,
        practiceGoals: const [PracticeGoal.humorousReply],
        notes: 'notes only on partner layer',
        updatedAt: ts,
      );
      final r = resolveEffectiveStyle(global: null, partner: partner);
      expect(r.interactionStyle, InteractionStyle.direct);
      expect(r.practiceGoals, [PracticeGoal.humorousReply]);
      expect(r.notes, 'notes only on partner layer');
    });

    test('all three fields independently inherit (mixed override)', () {
      // partner sets ONLY notes; should inherit style + goals from global.
      final partner = PartnerStyleOverride.create(
        partnerId: 'p1',
        notes: '主角',
        updatedAt: ts,
      );
      final r = resolveEffectiveStyle(global: globalStyle, partner: partner);
      expect(r.interactionStyle, InteractionStyle.steady);
      expect(r.practiceGoals, [PracticeGoal.softInvite]);
      expect(r.notes, '主角');
    });
  });

  group('resolveEffectiveStyle style pair (atomic 主+副)', () {
    final globalPair = UserProfile.create(
      interactionStyle: InteractionStyle.steady,
      secondaryStyle: InteractionStyle.humorous,
      updatedAt: ts,
    );

    test('partner with 主 wins the whole pair (主+副 from partner)', () {
      final partner = PartnerStyleOverride.create(
        partnerId: 'p1',
        interactionStyle: InteractionStyle.direct,
        secondaryStyle: InteractionStyle.playful,
        updatedAt: ts,
      );
      final r = resolveEffectiveStyle(global: globalPair, partner: partner);
      expect(r.interactionStyle, InteractionStyle.direct);
      expect(r.secondaryStyle, InteractionStyle.playful);
    });

    test('partner 主-only wins the whole pair — global 副 must NOT leak in',
        () {
      // The contract case: mixing partner 主 + global 副 would compose a
      // persona the user never picked.
      final partner = PartnerStyleOverride.create(
        partnerId: 'p1',
        interactionStyle: InteractionStyle.direct,
        updatedAt: ts,
      );
      final r = resolveEffectiveStyle(global: globalPair, partner: partner);
      expect(r.interactionStyle, InteractionStyle.direct);
      expect(r.secondaryStyle, isNull);
    });

    test('partner without 主 inherits the whole global pair', () {
      final partner = PartnerStyleOverride.create(
        partnerId: 'p1',
        notes: '只有備註',
        updatedAt: ts,
      );
      final r = resolveEffectiveStyle(global: globalPair, partner: partner);
      expect(r.interactionStyle, InteractionStyle.steady);
      expect(r.secondaryStyle, InteractionStyle.humorous);
    });

    test('partner null inherits the whole global pair', () {
      final r = resolveEffectiveStyle(global: globalPair, partner: null);
      expect(r.interactionStyle, InteractionStyle.steady);
      expect(r.secondaryStyle, InteractionStyle.humorous);
    });
  });
}
