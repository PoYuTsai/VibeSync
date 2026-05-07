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

final coachChatControllerProvider = AsyncNotifierProvider.autoDispose
    .family<CoachChatController, CoachChatResult?, String>(
  CoachChatController.new,
);

class CoachChatController
    extends AutoDisposeFamilyAsyncNotifier<CoachChatResult?, String> {
  bool _inFlight = false;
  String? _activeSessionId;
  List<CoachChatSessionTurn> _activeTurns = const [];

  @override
  Future<CoachChatResult?> build(String conversationId) async {
    final repo = ref.read(coachChatRepositoryProvider);
    return repo.latestForConversation(conversationId);
  }

  Future<void> ask({
    required String question,
    required CoachChatAnalysisSnapshot analysisSnapshot,
    bool forceAnswer = false,
  }) async {
    final trimmed = question.trim();
    if (trimmed.isEmpty || _inFlight) return;
    _inFlight = true;
    try {
      final conversationId = arg;
      final repo = ref.read(coachChatRepositoryProvider);
      final previousResult =
          state.valueOrNull ?? repo.latestForConversation(conversationId);
      final sessionId = _activeSessionId ??
          previousResult?.sessionId ??
          'coach-$conversationId-${DateTime.now().microsecondsSinceEpoch}';
      final outboundTurns = _seedTurns(previousResult);
      state = const AsyncValue.loading();
      final conversation = ref.read(conversationProvider(conversationId));
      if (conversation == null) {
        throw StateError('Conversation not found');
      }

      final api = ref.read(coachChatApiServiceProvider);
      final partnerId = conversation.partnerId;
      final dataQualityFlag = partnerId == null
          ? null
          : ref.read(dataQualityFlagProvider(partnerId));
      final flagged = dataQualityFlag?.isFlagged ?? false;

      final result = await api.ask(
        conversationId: conversationId,
        partnerId: partnerId,
        sessionId: sessionId,
        question: trimmed,
        activeSessionTurns: outboundTurns,
        forceAnswer: forceAnswer,
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
      _activeSessionId = result.sessionId ?? sessionId;
      _activeTurns = _capTurns([
        ...outboundTurns,
        CoachChatSessionTurn(
          role: 'user',
          kind: forceAnswer ? 'supplement' : 'question',
          content: trimmed,
          createdAt: DateTime.now(),
        ),
        CoachChatSessionTurn(
          role: 'coach',
          kind: result.isClarifyingQuestion ? 'clarification' : 'answer',
          content: result.isClarifyingQuestion
              ? (result.reflectionQuestion ?? result.answer)
              : result.answer,
          createdAt: result.generatedAt,
        ),
      ]);
      state = AsyncValue.data(result);
      if (result.costDeducted > 0) {
        await _syncUsageSnapshot();
      }
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    } finally {
      _inFlight = false;
    }
  }

  Future<void> forceAnswer({
    required CoachChatAnalysisSnapshot analysisSnapshot,
  }) async {
    final latest = state.valueOrNull ??
        ref.read(coachChatRepositoryProvider).latestForConversation(arg);
    await ask(
      question: latest?.question ?? '請直接給我建議',
      analysisSnapshot: analysisSnapshot,
      forceAnswer: true,
    );
  }

  List<CoachChatSessionTurn> _seedTurns(CoachChatResult? previousResult) {
    if (_activeTurns.isNotEmpty) return _activeTurns;
    if (previousResult == null || previousResult.sessionId == null) {
      return const [];
    }
    _activeSessionId = previousResult.sessionId;
    final turns = <CoachChatSessionTurn>[
      CoachChatSessionTurn(
        role: 'user',
        kind: 'question',
        content: previousResult.question,
        createdAt: previousResult.generatedAt,
      ),
      CoachChatSessionTurn(
        role: 'coach',
        kind: previousResult.isClarifyingQuestion ? 'clarification' : 'answer',
        content: previousResult.isClarifyingQuestion
            ? (previousResult.reflectionQuestion ?? previousResult.answer)
            : previousResult.answer,
        createdAt: previousResult.generatedAt,
      ),
    ];
    return _capTurns(turns);
  }

  List<CoachChatSessionTurn> _capTurns(List<CoachChatSessionTurn> turns) {
    if (turns.length <= 12) return List.unmodifiable(turns);
    return List.unmodifiable(turns.sublist(turns.length - 12));
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
