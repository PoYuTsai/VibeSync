// lib/features/analysis/data/providers/analysis_providers.dart
//
// AnalyzeChat 的 composition root：Riverpod provider、Hive store 與具體
// client 的組裝都在這裡；application coordinator 只拿到具名注入的
// callable／instance，不自行解析 provider。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/services/funnel_tracker.dart';
import '../../../../core/services/revenuecat_service.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../analysis_history/data/providers/analysis_history_providers.dart';
import '../../../conversation/data/providers/conversation_archive_providers.dart';
import '../../../conversation/data/repositories/conversation_archive_store.dart'
    show ConversationArchiveStatus;
import '../../../conversation/data/providers/conversation_providers.dart';
import '../../../conversation/data/providers/conversation_write_controller.dart';
import '../../../conversation/domain/entities/conversation.dart';
import '../../../partner/domain/entities/partner.dart';
import '../../../partner/domain/services/partner_summary_builder.dart';
import '../../../partner/presentation/providers/partner_providers.dart';
import '../../../subscription/data/providers/subscription_providers.dart';
import '../../../user_profile/data/providers/data_quality_flag_provider.dart';
import '../../../user_profile/data/providers/partner_style_providers.dart';
import '../../../user_profile/data/providers/user_profile_providers.dart';
import '../../../user_profile/data/repositories/partner_data_quality_repo_view.dart';
import '../../../user_profile/data/repositories/partner_data_quality_repository.dart';
import '../../application/analysis_persistence_coordinator.dart';
import '../../application/ports/conversation_write_ports.dart';
import '../../application/analysis_run_preparer.dart';
import '../../application/analysis_session_controller.dart';
import '../../application/reply_iteration_coordinator.dart';
import '../../application/screenshot_import_coordinator.dart';
import '../notifiers/streaming_analyze_notifier.dart';
import '../repositories/analysis_record_port_adapter.dart';
import '../services/analysis_auxiliary_client.dart';
import '../services/conversation_memory_adapter.dart';
import '../services/ocr_recognition_cache_adapter.dart';
import '../services/optimize_billing_adapter.dart';
import '../services/reply_refine_draft_adapter.dart';
import '../services/optimize_message_request_session.dart';
import '../services/reply_refine_draft_store.dart';
import 'analysis_record_providers.dart';
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

/// AnalyzeChat 請求組裝器。partner 脈絡與有效風格解析走既有 provider；
/// 兩者皆為 per-call `read`（一次性快照，不做 reactive 監聽）。
final analysisRunPreparerProvider = Provider<AnalysisRunPreparer>((ref) {
  // Spec 2.5: About Me + per-partner style becomes compact prompt context.
  // If Spec 3 flags this partner card, partner-specific style is suspended
  // and only global About Me remains trusted.
  String? resolveEffectiveStyleContext(Conversation conversation) {
    final global = ref.read(userProfileControllerProvider).valueOrNull;
    final partnerId = conversation.partnerId;
    if (partnerId == null) {
      return ref.read(effectiveStylePromptBuilderProvider).buildForAnalysis(
            global: global,
            partner: null,
            includePartnerOverride: false,
          );
    }

    final includePartnerOverride =
        !ref.read(dataQualityFlagProvider(partnerId)).isFlagged;
    final partner = includePartnerOverride
        ? ref.read(partnerStyleOverrideProvider(partnerId)).valueOrNull
        : null;
    return ref.read(effectiveStylePromptBuilderProvider).buildForAnalysis(
          global: global,
          partner: partner,
          includePartnerOverride: includePartnerOverride,
        );
  }

  return AnalysisRunPreparer(
    memory: ConversationMemoryAdapter(),
    resolvePartnerSummary: (conversation) =>
        ref.read(partnerContextResolverProvider).resolve(conversation),
    resolveEffectiveStyleContext: resolveEffectiveStyleContext,
  );
});

/// [AnalysisPersistenceCoordinator] 的工廠。畫面提供 UI callback；
/// 資料相依全部在這裡以具名 callable 解析（維持原 per-call read 新鮮度）。
typedef AnalysisPersistenceCoordinatorFactory = AnalysisPersistenceCoordinator
    Function({
  required String conversationId,
  required void Function() notifyStateChanged,
  required void Function(Conversation conversation) invalidateRecordViews,
  required Future<void> Function(Conversation conversation)
      afterAnalysisPersisted,
});

final analysisPersistenceCoordinatorFactoryProvider =
    Provider<AnalysisPersistenceCoordinatorFactory>((ref) {
  return ({
    required String conversationId,
    required void Function() notifyStateChanged,
    required void Function(Conversation conversation) invalidateRecordViews,
    required Future<void> Function(Conversation conversation)
        afterAnalysisPersisted,
  }) {
    return AnalysisPersistenceCoordinator(
      conversationId: conversationId,
      getConversation: (id) =>
          ref.read(conversationRepositoryProvider).getConversation(id),
      persistAnalysisCompleted: (
        conversation, {
        required expectedContentRevision,
      }) =>
          ref.read(conversationWriteControllerProvider.notifier).save(
                conversation,
                intent: ConversationSaveIntent.analysisCompleted,
                expectedContentRevision: expectedContentRevision,
              ),
      persistContentChanged: (conversation) =>
          ref.read(conversationWriteControllerProvider.notifier).save(
                conversation,
                intent: ConversationSaveIntent.contentChanged,
              ),
      markConversationActive: (conversation) => ref
          .read(conversationArchiveControllerProvider.notifier)
          .markActive(conversation),
      archiveMarkerFor: (conversation) {
        final entry =
            ref.read(conversationArchiveStoreProvider).entryFor(conversation);
        if (entry == null) return null;
        return ArchiveMarkerSnapshot(
          contentRevision: entry.contentRevision,
          isArchived: entry.status == ConversationArchiveStatus.archived,
        );
      },
      recordPort: AnalysisRecordPortAdapter(
        store: () => ref.read(analysisRecordStoreProvider),
      ),
      currentRecordOwnerUserId: () => ref.read(analysisRecordOwnerProvider),
      historyRepository: () => ref.read(analysisHistoryRepositoryProvider),
      trackFunnelOnce: (eventKey) =>
          ref.read(funnelTrackerProvider).trackOnce(eventKey),
      lastPayloadCharCount: () => ref
          .read(streamingAnalyzeProvider(conversationId).notifier)
          .lastPayloadCharCount,
      notifyStateChanged: notifyStateChanged,
      invalidateRecordViews: invalidateRecordViews,
      afterAnalysisPersisted: afterAnalysisPersisted,
    );
  };
});

/// [AnalysisSessionController] 的工廠：串流 notifier（autoDispose family，
/// 逐次解析）、訂閱權益預同步與當前對話快照都以具名 callable 注入。
typedef AnalysisSessionControllerFactory = AnalysisSessionController Function({
  required String conversationId,
  required AnalysisPersistenceCoordinator persistence,
});

final analysisSessionControllerFactoryProvider =
    Provider<AnalysisSessionControllerFactory>((ref) {
  return ({
    required String conversationId,
    required AnalysisPersistenceCoordinator persistence,
  }) {
    return AnalysisSessionController(
      conversationId: conversationId,
      startRun: ({
        required messages,
        sessionContext,
        conversationSummary,
        partnerSummary,
        effectiveStyleContext,
        knownContactName,
        previousAnalyzedCount,
        previousAnalyzedCharCount,
        confirmedOvercharge,
        conversationMessageCount,
        analyzedMessageCount,
        conversationContentRevision,
      }) =>
          ref.read(streamingAnalyzeProvider(conversationId).notifier).start(
                messages: messages,
                sessionContext: sessionContext,
                conversationSummary: conversationSummary,
                partnerSummary: partnerSummary,
                effectiveStyleContext: effectiveStyleContext,
                knownContactName: knownContactName,
                previousAnalyzedCount: previousAnalyzedCount,
                previousAnalyzedCharCount: previousAnalyzedCharCount,
                confirmedOvercharge: confirmedOvercharge,
                conversationMessageCount: conversationMessageCount,
                analyzedMessageCount: analyzedMessageCount,
                conversationContentRevision: conversationContentRevision,
              ),
      retryRun: () => ref
          .read(streamingAnalyzeProvider(conversationId).notifier)
          .retryStream(),
      ensureServerEntitlementSynced: () => ref
          .read(subscriptionProvider.notifier)
          .ensureServerEntitlementSyncedForAnalysis(),
      currentConversation: () => ref.read(conversationProvider(conversationId)),
      persistence: persistence,
    );
  };
});

/// [ScreenshotImportCoordinator] 的工廠：對話讀寫、partner 查名與免費
/// OCR client 的組裝都在這裡。
typedef ScreenshotImportCoordinatorFactory = ScreenshotImportCoordinator
    Function({
  required String conversationId,
  required void Function() invalidateConversationProvider,
});

final screenshotImportCoordinatorFactoryProvider =
    Provider<ScreenshotImportCoordinatorFactory>((ref) {
  return ({
    required String conversationId,
    required void Function() invalidateConversationProvider,
  }) {
    return ScreenshotImportCoordinator(
      conversationId: conversationId,
      getConversation: (id) =>
          ref.read(conversationRepositoryProvider).getConversation(id),
      createConversation: ({
        required name,
        required messages,
        partnerId,
      }) =>
          ref.read(conversationWriteControllerProvider.notifier).create(
                name: name,
                messages: messages,
                partnerId: partnerId,
              ),
      saveConversation: (conversation) => ref
          .read(conversationWriteControllerProvider.notifier)
          .save(conversation),
      partnerById: (partnerId) =>
          ref.read(partnerRepositoryProvider).getById(partnerId),
      recognizeScreenshots: AnalysisAuxiliaryClient().recognizeScreenshots,
      recognitionCache: const OcrRecognitionCacheAdapter(),
      invalidateConversationProvider: invalidateConversationProvider,
    );
  };
});

/// [ReplyIterationCoordinator] 的工廠：exactly-once session 與微調稿
/// 暫存的 Hive 組裝、輔助 client 建構都收在這裡（box 取用維持 lazy，
/// 首次真正讀寫才碰 Hive）。
final replyIterationCoordinatorFactoryProvider =
    Provider<ReplyIterationCoordinator Function()>((ref) {
  return () {
    final auxiliaryClient = AnalysisAuxiliaryClient();
    return ReplyIterationCoordinator(
      billing: OptimizeBillingAdapter(
        session: OptimizeMessageRequestIdSession(
          store: HiveOptimizeMessagePendingRequestStore(
            () => StorageService.settingsBox,
          ),
        ),
      ),
      draftStore: ReplyRefineDraftAdapter(
        store: HiveReplyRefineDraftStore(
          () => StorageService.settingsBox,
        ),
      ),
      optimizeDraft: auxiliaryClient.optimizeDraft,
      refineReply: auxiliaryClient.refineReply,
    );
  };
});
