import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/storage_service.dart';
import '../../../conversation/data/providers/conversation_providers.dart';
import '../../../conversation/domain/entities/conversation.dart';
import '../../../partner/presentation/providers/partner_providers.dart';
import '../../../subscription/data/providers/subscription_providers.dart';
import '../../../user_profile/data/providers/data_quality_flag_provider.dart';
import '../../../user_profile/data/providers/partner_style_providers.dart';
import '../../../user_profile/data/providers/user_profile_providers.dart';
import '../../domain/entities/coach_chat_result.dart';
import '../../domain/repositories/coach_chat_repository.dart';
import '../repositories/coach_chat_repository_impl.dart';
import '../services/coach_chat_api_service.dart';

final coachChatRepositoryProvider = Provider<CoachChatRepository>((ref) {
  return CoachChatRepositoryImpl(StorageService.coachChatResultsBox);
});

final coachChatApiServiceProvider = Provider<CoachChatApiService>((ref) {
  return CoachChatApiService();
});

final coachChatUsageSyncProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    await ref.read(subscriptionProvider.notifier).refresh();
  };
});

typedef CoachChatStyleContextArgs = ({
  String? partnerId,
  bool includePartnerOverride,
});

typedef CoachChatStyleContextResolver = String? Function({
  required String? partnerId,
  required bool includePartnerOverride,
});

final coachChatStyleContextProvider =
    Provider.family<String?, CoachChatStyleContextArgs>((ref, args) {
  final global = ref.watch(userProfileControllerProvider).valueOrNull;
  final partner = args.partnerId != null && args.includePartnerOverride
      ? ref.watch(partnerStyleOverrideProvider(args.partnerId!)).valueOrNull
      : null;
  return ref.watch(effectiveStylePromptBuilderProvider).buildForCoachFollowUp(
        global: global,
        partner: partner,
        includePartnerOverride: args.includePartnerOverride,
      );
});

final coachChatStyleContextResolverProvider =
    Provider<CoachChatStyleContextResolver>((ref) {
  return ({
    required String? partnerId,
    required bool includePartnerOverride,
  }) {
    return ref.read(
      coachChatStyleContextProvider((
        partnerId: partnerId,
        includePartnerOverride: includePartnerOverride,
      )),
    );
  };
});

final coachChatHistoryProvider =
    Provider.family<List<CoachChatResult>, String>((ref, conversationId) {
  final repo = ref.watch(coachChatRepositoryProvider);
  return repo.listByConversation(conversationId);
});

final coachChatControllerProvider =
    AsyncNotifierProvider.family<CoachChatController, CoachChatResult?, String>(
  CoachChatController.new,
);

class CoachChatController
    extends FamilyAsyncNotifier<CoachChatResult?, String> {
  bool _inFlight = false;

  @override
  Future<CoachChatResult?> build(String conversationId) async {
    final repo = ref.read(coachChatRepositoryProvider);
    return repo.latestForConversation(conversationId);
  }

  Future<void> ask({
    required String question,
    required CoachChatAnalysisSnapshot analysisSnapshot,
  }) async {
    final trimmed = question.trim();
    if (trimmed.isEmpty || _inFlight) return;
    _inFlight = true;
    try {
      state = const AsyncValue.loading();
      final conversationId = arg;
      final conversation = ref.read(conversationProvider(conversationId));
      if (conversation == null) {
        throw StateError('Conversation not found');
      }

      final api = ref.read(coachChatApiServiceProvider);
      final repo = ref.read(coachChatRepositoryProvider);
      final partnerId = conversation.partnerId;
      final dataQualityFlag = partnerId == null
          ? null
          : ref.read(dataQualityFlagProvider(partnerId));
      final flagged = dataQualityFlag?.isFlagged ?? false;

      final result = await api.ask(
        conversationId: conversationId,
        partnerId: partnerId,
        question: trimmed,
        recentMessages: _recentMessages(conversation),
        conversationSummary: _conversationSummary(conversation),
        analysisSnapshot: analysisSnapshot,
        effectiveStyleContext: _styleContext(
          partnerId: partnerId,
          includePartnerOverride: !flagged,
        ),
        partnerHint: _partnerHint(
          partnerId: partnerId,
          dataQualityFlagged: flagged,
        ),
        dataQualityFlagged: flagged,
      );
      await repo.put(result);
      state = AsyncValue.data(result);
      await _syncUsageSnapshot();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    } finally {
      _inFlight = false;
    }
  }

  List<CoachChatMessage> _recentMessages(Conversation conversation) {
    return conversation
        .getRecentMessages(15)
        .where((message) => message.content.trim().isNotEmpty)
        .take(30)
        .map(
          (message) => CoachChatMessage(
            isFromMe: message.isFromMe,
            text: message.content,
            createdAt: message.timestamp,
          ),
        )
        .toList(growable: false);
  }

  String? _conversationSummary(Conversation conversation) {
    final summaries = conversation.summaries;
    if (summaries == null || summaries.isEmpty) return null;
    final text = summaries.reversed
        .map((summary) => summary.content.trim())
        .where((content) => content.isNotEmpty)
        .take(2)
        .join('\n');
    if (text.isEmpty) return null;
    return text.length <= 500 ? text : '${text.substring(0, 499).trimRight()}…';
  }

  String? _styleContext({
    required String? partnerId,
    required bool includePartnerOverride,
  }) {
    return ref.read(coachChatStyleContextResolverProvider)(
      partnerId: partnerId,
      includePartnerOverride: includePartnerOverride,
    );
  }

  CoachChatPartnerHint? _partnerHint({
    required String? partnerId,
    required bool dataQualityFlagged,
  }) {
    if (partnerId == null) return null;
    final partner = ref.read(partnerByIdProvider(partnerId));
    if (partner == null) return null;
    if (dataQualityFlagged) {
      return CoachChatPartnerHint(name: partner.name);
    }
    final aggregate = ref.read(partnerAggregateProvider(partnerId));
    return CoachChatPartnerHint(
      name: partner.name,
      traits: aggregate.unionTraits.take(5).toList(growable: false),
    );
  }

  Future<void> _syncUsageSnapshot() async {
    final syncUsage = ref.read(coachChatUsageSyncProvider);
    try {
      await syncUsage();
    } catch (_) {
      // Generation and local persistence already succeeded. Usage refresh is
      // a UI catch-up only and must not hide the result.
    }
  }
}
