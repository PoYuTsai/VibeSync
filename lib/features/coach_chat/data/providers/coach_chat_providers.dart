import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/storage_service.dart';
import '../../../coaching_memory/data/providers/coaching_outcome_providers.dart';
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
  return CoachChatRepositoryImpl(
    StorageService.unifiedCoachResultsBox,
    StorageService.coachChatResultsBox,
    StorageService.coachFollowUpResultsBox,
  );
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

final coachChatProgressProvider = StateProvider.autoDispose
    .family<CoachChatProgressUpdate?, String>((ref, conversationId) => null);

final coachChatControllerProvider = AsyncNotifierProvider.autoDispose
    .family<CoachChatController, CoachChatResult?, String>(
  CoachChatController.new,
);

class CoachChatController
    extends AutoDisposeFamilyAsyncNotifier<CoachChatResult?, String> {
  static const int maxNoChargeClarificationTurns = 3;

  // Hive 舊結果的 session 只在此窗口內視為「本輪延續」；超過即換新
  // session，避免 prompt 把幾天前的問答當成本輪脈絡。
  static const Duration sessionResumeWindow = Duration(hours: 24);

  bool _inFlight = false;
  String? _activeSessionId;
  List<CoachChatSessionTurn> _activeTurns = const [];

  static int countClarificationTurns(List<CoachChatSessionTurn> turns) {
    return turns
        .where((turn) => turn.role == 'coach' && turn.kind == 'clarification')
        .length;
  }

  static bool shouldForceAnswerAfterClarifications({
    required List<CoachChatSessionTurn> turns,
    required bool forceAnswer,
  }) {
    return forceAnswer ||
        countClarificationTurns(turns) >= maxNoChargeClarificationTurns;
  }

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
    final keepAliveLink = ref.keepAlive();
    try {
      final conversationId = arg;
      final repo = ref.read(coachChatRepositoryProvider);
      final previousResult =
          state.valueOrNull ?? repo.latestForConversation(conversationId);
      final resumablePrevious =
          previousResult != null && _canResumeSession(previousResult)
              ? previousResult
              : null;
      final sessionId = _activeSessionId ??
          resumablePrevious?.sessionId ??
          'coach-$conversationId-${DateTime.now().microsecondsSinceEpoch}';
      final outboundTurns = _seedTurns(resumablePrevious);
      final effectiveForceAnswer =
          CoachChatController.shouldForceAnswerAfterClarifications(
        turns: outboundTurns,
        forceAnswer: forceAnswer,
      );
      state = const AsyncValue.loading();
      ref.read(coachChatProgressProvider(conversationId).notifier).state = null;
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

      // 教練有記憶：近期建議結果 digest。≥3 筆訊號才注入（hasEnoughSignal），
      // 不足時傳空陣列＝維持現行為（server 側該欄缺席，prompt 不加此節）。
      // 一律用 statisticalInsightLines（只去識別化統計/類別句），絕不用
      // localInsightLines——後者含「最近嘗試」自由文字建議，會夾帶複製/生成
      // 回覆原文（Codex 批4 finding）。對象回覆原文與使用者筆記本就不在此。
      final outcomeDigest = partnerId != null
          ? ref.read(coachingOutcomeDigestProvider(partnerId))
          : ref.read(coachingUnboundOutcomeDigestProvider);
      final outcomeInsightLines = outcomeDigest.hasEnoughSignal
          ? outcomeDigest.statisticalInsightLines
          : const <String>[];

      final result = await api.ask(
        conversationId: conversationId,
        partnerId: partnerId,
        sessionId: sessionId,
        question: trimmed,
        activeSessionTurns: outboundTurns,
        forceAnswer: effectiveForceAnswer,
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
        outcomeInsightLines: outcomeInsightLines,
        dataQualityFlagged: flagged,
        onProgress: (update) {
          ref.read(coachChatProgressProvider(conversationId).notifier).state =
              update;
        },
      );
      await repo.put(result);
      ref.invalidate(coachChatHistoryProvider(conversationId));
      _activeSessionId = result.sessionId ?? sessionId;
      _activeTurns = _capTurns([
        ...outboundTurns,
        CoachChatSessionTurn(
          role: 'user',
          kind: effectiveForceAnswer ? 'supplement' : 'question',
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
      ref.read(coachChatProgressProvider(arg).notifier).state = null;
      _inFlight = false;
      keepAliveLink.close();
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

  bool _canResumeSession(CoachChatResult previousResult) {
    if (previousResult.sessionId == null) return false;
    return DateTime.now().difference(previousResult.generatedAt) <=
        sessionResumeWindow;
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
