// lib/features/partner/data/services/partner_id_factory.dart
import 'package:uuid/uuid.dart';

/// Compile-time constant. Changing this breaks migration idempotency
/// for every existing user. Treat as immutable.
const _kPartnerNamespaceUuid = '6f6e8b5a-4f8b-4e3a-b1c4-2026042501a1';

/// Derives stable `partnerId` values from `Conversation.id` using UUID v5.
///
/// The migration (A1 task 6) calls [deriveFromConversationId] for each
/// legacy conversation. Re-running the migration over the same conversation
/// produces the same partnerId, which makes the migration loop idempotent
/// without depending on a "done" flag for correctness.
class PartnerIdFactory {
  PartnerIdFactory._();

  /// Exposed only for the regression-guard test in
  /// `partner_id_factory_test.dart`. Do not use this constant outside
  /// of that test.
  static const namespaceForRegressionGuard = _kPartnerNamespaceUuid;

  /// Returns a deterministic UUID v5 derived from [conversationId].
  /// Same input → same output, across processes and across reruns.
  static String deriveFromConversationId(String conversationId) {
    return const Uuid().v5(_kPartnerNamespaceUuid, conversationId);
  }
}
