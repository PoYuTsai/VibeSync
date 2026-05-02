// Spec 5 — B11 phase enum tests.
//
// Stable .name keys are part of the wire contract: client→Edge JSON uses the
// English key; Hive persists CoachFollowUpResult.phase as the same String.
// Display 繁中 is a presentation concern (displayLabel getter) and must NEVER
// be persisted or sent on the wire (design §1 stable-key discipline).

import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/coach_follow_up/domain/entities/coach_follow_up_phase.dart';

void main() {
  group('CoachFollowUpPhase', () {
    test('phase serializes to stable English string keys', () {
      expect(CoachFollowUpPhase.prepareInvite.name, equals('prepareInvite'));
      expect(CoachFollowUpPhase.preDateReminder.name, equals('preDateReminder'));
      expect(
        CoachFollowUpPhase.postDateReflection.name,
        equals('postDateReflection'),
      );
    });

    test('values list has exactly 3 phases (no extras / no missing)', () {
      expect(CoachFollowUpPhase.values, hasLength(3));
      expect(CoachFollowUpPhase.values, contains(CoachFollowUpPhase.prepareInvite));
      expect(
        CoachFollowUpPhase.values,
        contains(CoachFollowUpPhase.preDateReminder),
      );
      expect(
        CoachFollowUpPhase.values,
        contains(CoachFollowUpPhase.postDateReflection),
      );
    });

    test('fromString returns matching enum for each stable key', () {
      expect(
        CoachFollowUpPhase.fromString('prepareInvite'),
        equals(CoachFollowUpPhase.prepareInvite),
      );
      expect(
        CoachFollowUpPhase.fromString('preDateReminder'),
        equals(CoachFollowUpPhase.preDateReminder),
      );
      expect(
        CoachFollowUpPhase.fromString('postDateReflection'),
        equals(CoachFollowUpPhase.postDateReflection),
      );
    });

    test('fromString returns null for unknown / empty / null input', () {
      expect(CoachFollowUpPhase.fromString('invalid'), isNull);
      expect(CoachFollowUpPhase.fromString(''), isNull);
      expect(CoachFollowUpPhase.fromString(null), isNull);
      // Display labels must NOT round-trip through fromString — only stable
      // English keys are accepted.
      expect(CoachFollowUpPhase.fromString('準備邀約'), isNull);
    });

    test('displayLabel returns 繁中 for each phase (presentation only)', () {
      expect(CoachFollowUpPhase.prepareInvite.displayLabel, equals('準備邀約'));
      expect(
        CoachFollowUpPhase.preDateReminder.displayLabel,
        equals('約會前提醒'),
      );
      expect(
        CoachFollowUpPhase.postDateReflection.displayLabel,
        equals('約會後復盤'),
      );
    });
  });
}
