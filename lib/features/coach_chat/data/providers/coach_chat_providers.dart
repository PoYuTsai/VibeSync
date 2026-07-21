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
import '../../domain/entities/coach_scope.dart';
import '../../domain/entities/unified_coach_result.dart';
import '../../domain/repositories/coach_chat_repository.dart';
import '../repositories/coach_chat_repository_impl.dart';
import '../services/coach_chat_api_service.dart';
import '../services/coach_request_id_session.dart';

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

/// Phase E：scope-keyed 歷史（unified rows，含 read-bridge 合併的 legacy）。
final coachChatHistoryProvider =
    Provider.family<List<UnifiedCoachResult>, CoachScope>((ref, scope) {
  final repo = ref.watch(coachChatRepositoryProvider);
  return repo.listByScope(scope.type, scope.id);
});

final coachChatProgressProvider = StateProvider.autoDispose
    .family<CoachChatProgressUpdate?, CoachScope>((ref, scope) => null);

final coachChatControllerProvider = AsyncNotifierProvider.autoDispose
    .family<CoachChatController, UnifiedCoachResult?, CoachScope>(
  CoachChatController.new,
);

class CoachChatController
    extends AutoDisposeFamilyAsyncNotifier<UnifiedCoachResult?, CoachScope> {
  static const int maxNoChargeClarificationTurns = 3;

  // Hive 舊結果的 session 只在此窗口內視為「本輪延續」；超過即換新
  // session，避免 prompt 把幾天前的問答當成本輪脈絡。
  static const Duration sessionResumeWindow = Duration(hours: 24);

  bool _inFlight = false;
  String? _activeSessionId;
  List<CoachChatSessionTurn> _activeTurns = const [];

  /// 扣費 idempotency：同 intent 失敗重試沿用同 requestId，成功落卡才 retire。
  final CoachRequestIdSession _requestIdSession = CoachRequestIdSession();

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
  Future<UnifiedCoachResult?> build(CoachScope scope) async {
    final repo = ref.read(coachChatRepositoryProvider);
    return repo.latestForScope(scope.type, scope.id);
  }

  Future<void> ask({
    required String question,
    CoachChatAnalysisSnapshot? analysisSnapshot,
    bool forceAnswer = false,
    String? lifecyclePhase,
  }) async {
    final trimmed = question.trim();
    if (trimmed.isEmpty || _inFlight) return;
    _inFlight = true;
    final keepAliveLink = ref.keepAlive();
    try {
      final scope = arg;
      final repo = ref.read(coachChatRepositoryProvider);
      final previousResult =
          state.valueOrNull ?? repo.latestForScope(scope.type, scope.id);
      final resumablePrevious =
          previousResult != null && _canResumeSession(previousResult)
              ? previousResult
              : null;
      // resume 到的 session id（可為 null）。requestId signature 必須用它而
      // 非合成後的 sessionId：合成 id 帶時間戳，失敗重試會重新合成，若進了
      // signature 就會讓「同 intent 重試沿用同 requestId」失效。
      final resumedSessionId = _activeSessionId ?? resumablePrevious?.sessionId;
      final outboundTurns = _seedTurns(resumablePrevious);
      final effectiveForceAnswer =
          CoachChatController.shouldForceAnswerAfterClarifications(
        turns: outboundTurns,
        forceAnswer: forceAnswer,
      );
      state = const AsyncValue.loading();
      ref.read(coachChatProgressProvider(scope).notifier).state = null;

      Conversation? conversation;
      final String? partnerId;
      if (scope.isConversation) {
        conversation = ref.read(conversationProvider(scope.id));
        if (conversation == null) {
          throw StateError('Conversation not found');
        }
        partnerId = conversation.partnerId;
      } else {
        // partner scope：對象即 scope 本體，不依賴任何 conversation 資料。
        partnerId = scope.id;
      }
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

      // 同 intent＝(question, effectiveForceAnswer, lifecyclePhase, resume
      // session) 四元組；effectiveForceAnswer 才是 wire 上實際送出的語意
      // （server ledger 綁 payload，同 id 換 payload 會 REPLAY_MISMATCH）。
      final requestId = _requestIdSession.begin(
        '$trimmed|$effectiveForceAnswer|${lifecyclePhase ?? ''}'
        '|${resumedSessionId ?? ''}',
      );
      // fresh session 的合成 sessionId 綁 requestId 生命週期：server
      // input_hash 含 wire sessionId，重試若重合成時間戳會變成同 requestId
      // 不同 hash → COACH_REQUEST_REPLAY_MISMATCH 卡死重試（P1 修）。
      final sessionId = resumedSessionId ??
          _requestIdSession.resolveSessionId(() => _newSessionId(scope));

      final api = ref.read(coachChatApiServiceProvider);
      final result = await api.ask(
        conversationId: scope.id,
        partnerId: partnerId,
        sessionId: sessionId,
        question: trimmed,
        activeSessionTurns: outboundTurns,
        forceAnswer: effectiveForceAnswer,
        recentMessages:
            conversation != null ? _recentMessages(conversation) : const [],
        conversationSummary:
            conversation != null ? _conversationSummary(conversation) : null,
        analysisSnapshot: scope.isConversation ? analysisSnapshot : null,
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
        requestId: requestId,
        scope: scope,
        lifecyclePhase: lifecyclePhase,
        onProgress: (update) {
          ref.read(coachChatProgressProvider(scope).notifier).state = update;
        },
      );
      final unified = _toUnified(
        result,
        scope: scope,
        lifecyclePhase: lifecyclePhase,
      );
      await repo.putUnified(unified);
      // 成功持久化才 retire；失敗（catch）保留 pending id 供同值重試。
      // 釐清回應也是一次成功落卡：下一輪追問是新 intent，一樣 retire。
      _requestIdSession.retire();
      ref.invalidate(coachChatHistoryProvider(scope));
      _activeSessionId = unified.sessionId ?? sessionId;
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
          kind: unified.isClarifyingQuestion ? 'clarification' : 'answer',
          content: unified.isClarifyingQuestion
              ? (unified.reflectionQuestion ?? unified.answer)
              : unified.answer,
          createdAt: unified.generatedAt,
        ),
      ]);
      state = AsyncValue.data(unified);
      if (unified.costDeducted > 0) {
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
    CoachChatAnalysisSnapshot? analysisSnapshot,
    String? lifecyclePhase,
  }) async {
    final latest = state.valueOrNull ??
        ref
            .read(coachChatRepositoryProvider)
            .latestForScope(arg.type, arg.id);
    // legacy follow-up 映射列的 question 是空字串，一樣落到預設句。
    final previousQuestion = latest?.question.trim();
    await ask(
      question: previousQuestion == null || previousQuestion.isEmpty
          ? '請直接給我建議'
          : previousQuestion,
      analysisSnapshot: analysisSnapshot,
      forceAnswer: true,
      lifecyclePhase: lifecyclePhase,
    );
  }

  /// 新合成 session id：conversation scope 保留既有 `coach-<id>-<ts>` 形狀
  /// （語意零變）；partner scope 用 scope.key 避免與同 id 的 conversation
  /// session 撞名。
  String _newSessionId(CoachScope scope) {
    final base = scope.isConversation ? scope.id : scope.key;
    return 'coach-$base-${DateTime.now().microsecondsSinceEpoch}';
  }

  /// scope 欄位一律由 [CoachScope] 推導，絕不信 api result 的
  /// conversationId/partnerId（partner scope 下該兩欄不可靠——Task 3 review）。
  UnifiedCoachResult _toUnified(
    CoachChatResult result, {
    required CoachScope scope,
    String? lifecyclePhase,
  }) {
    if (scope.isConversation) {
      // 既有 1:1 映射 factory；result.conversationId 就是本 controller 傳給
      // api 的 scope.id 原值回流，scopeId 仍等於 scope.id。lifecyclePhase
      // 已隨 wire 送出，本地卡同步保存（Task 4 Minor 1）。
      return UnifiedCoachResult.fromCoachChatResult(
        result,
        lifecyclePhase: lifecyclePhase,
      );
    }
    return UnifiedCoachResult(
      id: result.id,
      conversationId: null,
      partnerId: scope.id,
      question: result.question,
      mode: result.mode,
      headline: result.headline,
      answer: result.answer,
      userState: result.userState,
      nextStep: result.nextStep,
      suggestedLine: result.suggestedLine,
      boundaryReminder: result.boundaryReminder,
      needsReflection: result.needsReflection,
      reflectionQuestion: result.reflectionQuestion,
      generatedAt: result.generatedAt,
      provider: result.provider,
      modelUsed: result.modelUsed,
      responseType: result.responseType,
      sessionId: result.sessionId,
      userTruth: result.userTruth,
      rewriteDecision: result.rewriteDecision,
      rewriteReason: result.rewriteReason,
      costDeducted: result.costDeducted,
      frictionType: result.frictionType,
      earlierSummary: result.earlierSummary,
      earlierResultCount: result.earlierResultCount,
      scopeType: CoachScopeType.partner,
      scopeId: scope.id,
      lifecyclePhase: lifecyclePhase,
    );
  }

  bool _canResumeSession(UnifiedCoachResult previousResult) {
    if (previousResult.sessionId == null) return false;
    return DateTime.now().difference(previousResult.generatedAt) <=
        sessionResumeWindow;
  }

  List<CoachChatSessionTurn> _seedTurns(UnifiedCoachResult? previousResult) {
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
