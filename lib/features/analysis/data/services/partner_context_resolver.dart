import '../../../conversation/domain/entities/conversation.dart';
import '../../../partner/domain/entities/partner.dart';
import '../../../partner/domain/services/partner_summary_builder.dart';

/// Read-only Partner lookup needed by [PartnerContextResolver]. The real
/// [PartnerRepository] satisfies this surface; the test stub implements it
/// directly without touching Hive.
abstract class PartnerRepoView {
  Partner? getById(String id);
}

/// Read-only conversation-by-partner listing surface. Real repository
/// satisfies this via `listByPartner`; tests provide an in-memory stub.
abstract class ConversationListByPartnerView {
  List<Conversation> listByPartner(String partnerId);
}

/// Builds the per-call partner-context summary for `analyze-chat`.
///
/// The summary is rebuilt on every call (no caching) so the partner
/// aggregate reflects the latest snapshot — see plan §Task 5 contract.
/// Returns null when there is no partner context worth attaching:
///   - conversation has no partnerId (legacy / unmigrated)
///   - partnerId points at a deleted/missing partner row
///   - summary builder yields empty string (owner-mismatch defense)
class PartnerContextResolver {
  PartnerContextResolver({
    required this.partnerRepo,
    required this.conversationRepo,
    required this.summaryBuilder,
  });

  final PartnerRepoView partnerRepo;
  final ConversationListByPartnerView conversationRepo;
  final PartnerSummaryBuilder summaryBuilder;

  String? resolve(Conversation conversation) {
    final partnerId = conversation.partnerId;
    if (partnerId == null) return null;

    final partner = partnerRepo.getById(partnerId);
    if (partner == null) return null;

    final conversations = conversationRepo.listByPartner(partnerId);
    final summary = summaryBuilder.build(
      partner: partner,
      conversations: conversations,
    );
    return summary.isEmpty ? null : summary;
  }
}
