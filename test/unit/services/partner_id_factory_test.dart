import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/partner/data/services/partner_id_factory.dart';

void main() {
  group('PartnerIdFactory.deriveFromConversationId', () {
    test('same input always produces same partnerId (deterministic)', () {
      final a = PartnerIdFactory.deriveFromConversationId('conv-abc');
      final b = PartnerIdFactory.deriveFromConversationId('conv-abc');
      expect(a, b);
    });

    test('different inputs produce different partnerIds', () {
      final a = PartnerIdFactory.deriveFromConversationId('conv-abc');
      final b = PartnerIdFactory.deriveFromConversationId('conv-xyz');
      expect(a, isNot(b));
    });

    test(
        'namespace constant must never change '
        '(regression guard — changing breaks idempotency)',
        () {
      // If this test fails, do NOT update the expected value.
      // Instead, revert the namespace change. Existing user data depends on it.
      expect(
        PartnerIdFactory.namespaceForRegressionGuard,
        '6f6e8b5a-4f8b-4e3a-b1c4-2026042501a1',
      );
    });

    test('returns a well-formed UUID v5 string', () {
      final id = PartnerIdFactory.deriveFromConversationId('conv-abc');
      expect(
        id,
        matches(RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')),
      );
    });
  });
}
