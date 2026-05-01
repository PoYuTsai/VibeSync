import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/user_profile/domain/entities/partner_data_quality_state.dart';

void main() {
  group('NamePair', () {
    test('canonicalizes to lower-case sorted pair', () {
      final p = NamePair.canonical('May', 'Anna');
      expect(p.first, 'anna');
      expect(p.second, 'may');
    });

    test('rejects empty names', () {
      expect(() => NamePair.canonical('', 'May'), throwsArgumentError);
    });

    test('equality is order-independent', () {
      expect(
        NamePair.canonical('Anna', 'May'),
        NamePair.canonical('May', 'Anna'),
      );
    });
  });

  group('PartnerDataQualityState', () {
    test('defaults to empty confirmed pairs', () {
      final s = PartnerDataQualityState.empty(
        'p1',
        updatedAt: DateTime(2026, 5, 1),
      );
      expect(s.partnerId, 'p1');
      expect(s.confirmedSamePersonPairs, isEmpty);
    });

    test('confirmsSamePerson is true after marking', () {
      final s = PartnerDataQualityState.empty(
        'p1',
        updatedAt: DateTime(2026, 5, 1),
      ).withConfirmed(
        NamePair.canonical('Anna', 'May'),
        at: DateTime(2026, 5, 1),
      );
      expect(s.confirmsSamePerson(NamePair.canonical('May', 'Anna')), isTrue);
      expect(s.confirmsSamePerson(NamePair.canonical('Anna', 'Lily')), isFalse);
    });
  });
}
