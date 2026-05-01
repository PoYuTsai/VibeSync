// lib/features/analysis/data/providers/analysis_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../conversation/data/providers/conversation_providers.dart';
import '../../../conversation/domain/entities/conversation.dart';
import '../../../conversation/domain/entities/message.dart';
import '../../../conversation/domain/entities/session_context.dart';
import '../../../partner/domain/entities/partner.dart';
import '../../../partner/domain/services/partner_summary_builder.dart';
import '../../../partner/presentation/providers/partner_providers.dart';
import '../../../user_profile/data/repositories/partner_data_quality_repository.dart';
import '../../domain/entities/analysis_models.dart';
import '../services/analysis_service.dart';
import '../services/partner_context_resolver.dart';

/// Provider for AnalysisService
final analysisServiceProvider = Provider<AnalysisService>((ref) {
  return AnalysisService();
});

/// Provider for the Spec 3 data-quality repository. Reads/writes to the
/// `partner_data_quality_states` Hive box. Phase 4 Task 16 will introduce a
/// `dataQualityFlagProvider` that wraps this repo for live flag detection.
final partnerDataQualityRepoProvider =
    Provider<PartnerDataQualityRepository>((ref) {
  return PartnerDataQualityRepository();
});

/// Provider for the per-call partner-context resolver. Adapters keep
/// `partner` and `analysis` features decoupled at the type level — the
/// real repos do not implement the resolver-local view interfaces.
final partnerContextResolverProvider =
    Provider<PartnerContextResolver>((ref) {
  final partnerRepo = ref.watch(partnerRepositoryProvider);
  final conversationRepo = ref.watch(conversationRepositoryProvider);
  return PartnerContextResolver(
    partnerRepo: _PartnerRepoAdapter(partnerRepo.getById),
    conversationRepo:
        _ConversationListByPartnerAdapter(conversationRepo.listByPartner),
    summaryBuilder: PartnerSummaryBuilder(),
    dataQualityRepo: ref.watch(partnerDataQualityRepoProvider),
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

/// State for analysis operation
sealed class AnalysisState {}

class AnalysisInitial extends AnalysisState {}

class AnalysisLoading extends AnalysisState {}

class AnalysisSuccess extends AnalysisState {
  final AnalysisResult result;
  AnalysisSuccess(this.result);
}

class AnalysisError extends AnalysisState {
  final String message;
  final bool isDailyLimit;
  final bool isMonthlyLimit;

  AnalysisError(
    this.message, {
    this.isDailyLimit = false,
    this.isMonthlyLimit = false,
  });
}

/// Notifier for managing analysis state
class AnalysisNotifier extends StateNotifier<AnalysisState> {
  final AnalysisService _service;

  AnalysisNotifier(this._service) : super(AnalysisInitial());

  Future<void> analyze(
    List<Message> messages, {
    SessionContext? sessionContext,
  }) async {
    state = AnalysisLoading();

    try {
      final result = await _service.analyzeConversation(
        messages,
        sessionContext: sessionContext,
      );
      state = AnalysisSuccess(result);
    } on DailyLimitExceededException catch (e) {
      state = AnalysisError(
        '今日額度已用完 (${e.used}/${e.dailyLimit})',
        isDailyLimit: true,
      );
    } on MonthlyLimitExceededException catch (e) {
      state = AnalysisError(
        '本月額度已用完 (${e.used}/${e.monthlyLimit})',
        isMonthlyLimit: true,
      );
    } on AnalysisException catch (e) {
      state = AnalysisError(e.message);
    }
  }

  void reset() {
    state = AnalysisInitial();
  }
}

/// Provider for analysis state management
final analysisNotifierProvider =
    StateNotifierProvider<AnalysisNotifier, AnalysisState>((ref) {
  final service = ref.watch(analysisServiceProvider);
  return AnalysisNotifier(service);
});
