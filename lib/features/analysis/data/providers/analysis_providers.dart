// lib/features/analysis/data/providers/analysis_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/services/revenuecat_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../conversation/data/providers/conversation_providers.dart';
import '../../../conversation/domain/entities/conversation.dart';
import '../../../partner/domain/entities/partner.dart';
import '../../../partner/domain/services/partner_summary_builder.dart';
import '../../../partner/presentation/providers/partner_providers.dart';
import '../../../subscription/data/providers/subscription_providers.dart';
import '../../../user_profile/data/providers/data_quality_flag_provider.dart';
import '../../../user_profile/data/repositories/partner_data_quality_repo_view.dart';
import '../../../user_profile/data/repositories/partner_data_quality_repository.dart';
import '../services/analyze_stream_client.dart';
import '../services/partner_context_resolver.dart';

Future<String?> _revenueCatAppUserId() async {
  final userId = SupabaseService.currentUser?.id;
  final customerInfo = userId == null
      ? await RevenueCatService.getCustomerInfo().timeout(
          const Duration(seconds: 3),
          onTimeout: () => null,
        )
      : await RevenueCatService.getCustomerInfoForAppUserId(userId).timeout(
          const Duration(seconds: 3),
          onTimeout: () => null,
        );
  return RevenueCatService.getRevenueCatAppUserId(customerInfo);
}

/// AnalyzeChat 主分析唯一串流傳輸的 provider（entitlement 佐證與
/// [analysisServiceProvider] 同一套 wiring）。
final analyzeStreamClientProvider = Provider<AnalyzeStreamClient>((ref) {
  final subscription = ref.watch(subscriptionProvider);
  return AnalyzeStreamClient(
    expectedTierProvider: () => subscription.tier,
    revenueCatAppUserIdProvider: _revenueCatAppUserId,
  );
});

/// Provider for the Spec 3 data-quality repository. Reads/writes to the
/// `partner_data_quality_states` Hive box. Used by Task 20's `markSamePerson`
/// action handler for writes, and by [dataQualityFlagProvider] for read-only
/// access to the confirmed-pairs list.
final partnerDataQualityRepoProvider =
    Provider<PartnerDataQualityRepository>((ref) {
  return PartnerDataQualityRepository();
});

/// Read-only [PartnerDataQualityRepoView] backed by [dataQualityFlagProvider].
///
/// The resolver is synchronous (`PartnerContextResolver.resolve()` is a one-
/// shot call, not a reactive watcher), so the adapter uses `_ref.read` to
/// fetch the current flag value on demand. Switching to this view replaces
/// the placeholder always-false behaviour in `PartnerDataQualityRepository`
/// with real cross-conversation flag detection (Spec 3 Phase 4 Task 16).
final partnerDataQualityRepoViewProvider =
    Provider<PartnerDataQualityRepoView>((ref) {
  return _ProviderBackedDataQualityRepoView(ref);
});

class _ProviderBackedDataQualityRepoView implements PartnerDataQualityRepoView {
  _ProviderBackedDataQualityRepoView(this._ref);
  final Ref _ref;

  @override
  bool isFlaggedUnresolved(String partnerId) =>
      _ref.read(dataQualityFlagProvider(partnerId)).isFlagged;
}

/// Provider for the per-call partner-context resolver. Adapters keep
/// `partner` and `analysis` features decoupled at the type level — the
/// real repos do not implement the resolver-local view interfaces.
final partnerContextResolverProvider = Provider<PartnerContextResolver>((ref) {
  final partnerRepo = ref.watch(partnerRepositoryProvider);
  final conversationRepo = ref.watch(conversationRepositoryProvider);
  return PartnerContextResolver(
    partnerRepo: _PartnerRepoAdapter(partnerRepo.getById),
    conversationRepo:
        _ConversationListByPartnerAdapter(conversationRepo.listByPartner),
    summaryBuilder: PartnerSummaryBuilder(),
    dataQualityRepo: ref.watch(partnerDataQualityRepoViewProvider),
  );
});

class _PartnerRepoAdapter implements PartnerRepoView {
  _PartnerRepoAdapter(this._getById);
  final Partner? Function(String id) _getById;

  @override
  Partner? getById(String id) => _getById(id);
}

class _ConversationListByPartnerAdapter
    implements ConversationListByPartnerView {
  _ConversationListByPartnerAdapter(this._listByPartner);
  final List<Conversation> Function(String partnerId) _listByPartner;

  @override
  List<Conversation> listByPartner(String partnerId) =>
      _listByPartner(partnerId);
}
