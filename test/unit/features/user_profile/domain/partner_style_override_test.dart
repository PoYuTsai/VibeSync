import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/user_profile/domain/entities/partner_style_override.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';

void main() {
  final ts = DateTime(2026, 5, 1);

  group('PartnerStyleOverride.create', () {
    test('should construct minimal override when only partnerId given', () {
      final ov = PartnerStyleOverride.create(partnerId: 'p1', updatedAt: ts);
      expect(ov.partnerId, 'p1');
      expect(ov.interactionStyle, isNull);
      expect(ov.practiceGoals, isEmpty);
      expect(ov.notes, isNull);
      expect(ov.isEmpty, isTrue);
    });

    test('should reject partnerId empty', () {
      expect(
        () => PartnerStyleOverride.create(partnerId: '', updatedAt: ts),
        throwsArgumentError,
      );
    });

    test('should reject practiceGoals exceeding max 3', () {
      expect(
        () => PartnerStyleOverride.create(
          partnerId: 'p1',
          practiceGoals: const [
            PracticeGoal.softInvite,
            PracticeGoal.reduceAnxiety,
            PracticeGoal.humorousReply,
            PracticeGoal.buildCloseness,
          ],
          updatedAt: ts,
        ),
        throwsArgumentError,
      );
    });

    test('should reject notes exceeding 100 chars', () {
      expect(
        () => PartnerStyleOverride.create(
          partnerId: 'p1',
          notes: 'x' * 101,
          updatedAt: ts,
        ),
        throwsArgumentError,
      );
    });

    test('should trim notes and treat empty as null', () {
      final ov = PartnerStyleOverride.create(
        partnerId: 'p1',
        notes: '   ',
        updatedAt: ts,
      );
      expect(ov.notes, isNull);
    });

    test('should mark isEmpty false when any field is set', () {
      final ov = PartnerStyleOverride.create(
        partnerId: 'p1',
        interactionStyle: InteractionStyle.steady,
        updatedAt: ts,
      );
      expect(ov.isEmpty, isFalse);
    });

    test('should reject secondaryStyle without interactionStyle (主)', () {
      expect(
        () => PartnerStyleOverride.create(
          partnerId: 'p1',
          secondaryStyle: InteractionStyle.humorous,
          updatedAt: ts,
        ),
        throwsArgumentError,
      );
    });

    test('should reject secondaryStyle equal to interactionStyle', () {
      expect(
        () => PartnerStyleOverride.create(
          partnerId: 'p1',
          interactionStyle: InteractionStyle.steady,
          secondaryStyle: InteractionStyle.steady,
          updatedAt: ts,
        ),
        throwsArgumentError,
      );
    });

    test('should accept 主 + distinct 副 and count toward isEmpty', () {
      final ov = PartnerStyleOverride.create(
        partnerId: 'p1',
        interactionStyle: InteractionStyle.steady,
        secondaryStyle: InteractionStyle.humorous,
        updatedAt: ts,
      );
      expect(ov.secondaryStyle, InteractionStyle.humorous);
      expect(ov.isEmpty, isFalse);
    });

    test('should make practiceGoals unmodifiable', () {
      final ov = PartnerStyleOverride.create(
        partnerId: 'p1',
        practiceGoals: const [PracticeGoal.softInvite],
        updatedAt: ts,
      );
      expect(
        () => ov.practiceGoals.add(PracticeGoal.reduceAnxiety),
        throwsUnsupportedError,
      );
    });
  });
}
