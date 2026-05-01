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

    test('raw non-canonical pair is NOT equal to canonical equivalent (dual-constructor contract)', () {
      // Anti-canonical order: first > second, untrimmed, mixed case
      final raw = NamePair(first: 'May', second: 'Anna');
      final canonical = NamePair.canonical('Anna', 'May');
      expect(raw == canonical, isFalse,
          reason: 'raw constructor lets bypass canonicalization; equality must NOT silently bridge them — '
                  'a non-canonical pair in confirmedSamePersonPairs would otherwise create false positives');
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

    test('confirmsSamePerson on raw non-canonical pair does not match canonical-stored pair', () {
      final s = PartnerDataQualityState.empty('p1', updatedAt: DateTime(2026, 5, 1))
          .withConfirmed(NamePair.canonical('Anna', 'May'), at: DateTime(2026, 5, 1));
      expect(s.confirmsSamePerson(NamePair(first: 'May', second: 'Anna')), isFalse,
          reason: 'callers must canonicalize before query; dual-constructor risk surface');
    });

    test('withConfirmed is idempotent on duplicate — returns same instance, no updatedAt drift', () {
      final base = PartnerDataQualityState.empty('p1', updatedAt: DateTime(2026, 5, 1))
          .withConfirmed(NamePair.canonical('Anna', 'May'), at: DateTime(2026, 5, 1, 12));
      final t2 = DateTime(2026, 5, 2);
      final after = base.withConfirmed(NamePair.canonical('May', 'Anna'), at: t2);
      expect(identical(base, after), isTrue,
          reason: 'duplicate confirmation must short-circuit; preserves both instance and original updatedAt');
      expect(after.updatedAt, base.updatedAt,
          reason: 'updatedAt must not drift when withConfirmed is a no-op');
    });

    test('withConfirmed propagates the at: parameter to updatedAt on real append', () {
      final base = PartnerDataQualityState.empty('p1', updatedAt: DateTime(2026, 5, 1));
      final t2 = DateTime(2026, 5, 2, 14, 30);
      final after = base.withConfirmed(NamePair.canonical('Anna', 'May'), at: t2);
      expect(after.updatedAt, t2,
          reason: 'at: parameter must propagate; otherwise the param is meaningless');
      expect(after.confirmedSamePersonPairs.length, 1,
          reason: 'real append happened (not no-op idempotent path)');
    });
  });
}
