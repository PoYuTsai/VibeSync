import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/storage_service.dart';
import '../../../coaching_memory/data/providers/coaching_outcome_providers.dart';
import '../../../coaching_memory/domain/entities/coaching_outcome_digest.dart';
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

const _maxOutcomeDigestContextChars = 500;

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
        outcomeDigestContext: _outcomeDigestContext(partnerId),
        partnerHint: _partnerHint(
          partnerId: partnerId,
          dataQualityFlagged: flagged,
        ),
        dataQualityFlagged: flagged,
      );
      await repo.put(result);
      ref.invalidate(coachChatHistoryProvider(conversationId));
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

  String? _outcomeDigestContext(String? partnerId) {
    if (partnerId == null) return null;
    final digest = ref.read(coachingOutcomeDigestProvider(partnerId));
    if (!digest.hasEnoughSignal) return null;
    final lines = <String>[
      '本地結果摘要（僅作輔助，不要過度推論）：最近 ${digest.totalEvents} 次教練建議回報；對方有接 ${digest.engagedCount}、冷回 ${digest.coldCount}、未回 ${digest.noReplyCount}、負面 ${digest.negativeCount}、待觀察 ${digest.pendingCount}。',
      '使用者行動：直接送出 ${digest.sentAsIsCount}、修改後送出 ${digest.editedAndSentCount}、沒送出 ${digest.didNotSendCount}、又問教練 ${digest.askedCoachCount}。',
      ..._outcomeDigestGuidance(digest),
    ];
    final text = lines
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join('\n');
    if (text.length <= _maxOutcomeDigestContextChars) return text;
    return '${text.substring(0, _maxOutcomeDigestContextChars - 3).trimRight()}...';
  }

  List<String> _outcomeDigestGuidance(CoachingOutcomeDigest digest) {
    final guidance = <String>[];
    if (digest.userOftenDoesNotSend) {
      guidance.add('觀察：使用者常沒送出，優先降低心理阻力，給更小步驟。');
    } else if (digest.oftenReturnsToCoach) {
      guidance.add('觀察：使用者常回來問教練，回答要更明確、少分岔。');
    } else if (digest.engagementRate >= 0.6 &&
        digest.resolvedOutcomeCount >= 3) {
      guidance.add('觀察：先前建議較常被接住，可以延續自然接球與輕推進。');
    } else if (digest.stalledOutcomeCount >= digest.engagedCount &&
        digest.resolvedOutcomeCount >= 3) {
      guidance.add('觀察：近期較常卡住，先校準語氣與節奏，不要硬推進。');
    }
    if (digest.recentMoveSummaries.isNotEmpty) {
      guidance.add(
        '近期建議主題：${digest.recentMoveSummaries.take(2).join(' / ')}',
      );
    }
    return guidance;
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
