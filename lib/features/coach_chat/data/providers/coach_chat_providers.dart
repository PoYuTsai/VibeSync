import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/storage_service.dart';
import '../../../coaching_memory/data/providers/coaching_outcome_providers.dart';
import '../../../conversation/data/providers/conversation_providers.dart';
import '../../../conversation/domain/entities/conversation.dart';
import '../../../partner/domain/services/partner_memory_tag_catalog.dart';
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

typedef CoachChatStyleContextResolver = Future<String?> Function({
  required String? partnerId,
  required bool includePartnerOverride,
});

/// Future-based on purpose (structurally mirrors `openerStyleContextProvider`,
/// 2026-08-03 fix): a sync `valueOrNull` read sends no style on a cold-start
/// Coach turn while the profile is still loading, silently dropping the
/// user's personalization for that request. Awaiting the profile future
/// guarantees the first request already carries the resolved style.
///
/// Not a replay/idempotency fix: `computeCoachInputHash` (server
/// billing.ts) does not include `effectiveStyleContext`, so a changed style
/// value on retry cannot trigger `COACH_REQUEST_REPLAY_MISMATCH` (confirmed
/// by cross-model review reading the server code — an earlier draft of this
/// comment claimed otherwise; that claim was refuted).
final coachChatStyleContextProvider =
    FutureProvider.family<String?, CoachChatStyleContextArgs>((
  ref,
  args,
) async {
  final global = await ref.watch(userProfileControllerProvider.future);
  final partner = args.partnerId != null && args.includePartnerOverride
      ? await ref.watch(partnerStyleOverrideProvider(args.partnerId!).future)
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
      )).future,
    );
  };
});

/// Batch B1：partner scope 的「最近一段有效對話」——教練本次參考的來源。
/// 有效＝至少一則非空白訊息；取最後一則非空白訊息時間最新者。controller
/// 送 wire 與畫面顯示「教練本次參考」都讀這裡，同源不漂移。沒有有效對話
/// 時回 null＝維持現行為（首輪證據制釐清會接手）。
final coachPartnerSourceConversationProvider =
    Provider.family<Conversation?, String>((ref, partnerId) {
  final conversations = ref.watch(conversationsByPartnerProvider(partnerId));
  Conversation? latest;
  DateTime? latestAt;
  for (final conversation in conversations) {
    final at = lastNonEmptyMessageAt(conversation);
    if (at == null) continue;
    if (latestAt == null || at.isAfter(latestAt)) {
      latest = conversation;
      latestAt = at;
    }
  }
  return latest;
});

/// 最後一則非空白訊息的時間；wire 的 lastMessageAt 與「教練本次參考」
/// 顯示共用（同源）。
DateTime? lastNonEmptyMessageAt(Conversation conversation) {
  for (final message in conversation.messages.reversed) {
    if (message.content.trim().isNotEmpty) return message.timestamp;
  }
  return null;
}

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

  /// 目前追問串已用的免費釐清數——與送給後端的 activeSessionTurns 同源，
  /// 也就是 3 次上限實際依據的數字。UI 序數必須用這個：歷史卡按 sessionId
  /// 數會跨追問串灌水（app 重啟後 _seedTurns 只回種最後一組問答，預算實質
  /// 重算），曾出現「第 5 次」的假標（2026-08-31 Bruce 截圖）。
  int get noChargeClarificationsUsed => countClarificationTurns(_activeTurns);

  static bool shouldForceAnswerAfterClarifications({
    required List<CoachChatSessionTurn> turns,
    required bool forceAnswer,
  }) {
    return forceAnswer ||
        countClarificationTurns(turns) >= maxNoChargeClarificationTurns;
  }

  @override
  UnifiedCoachResult? build(CoachScope scope) {
    // 同步回傳，不留 AsyncLoading 首幀：Hive 讀本來就是 sync，掛 async 會讓
    // autoDispose provider 每次熱切換 scope 都閃一幀 loading，UI 把它當
    // 「正在送出問題」誤播（2026-08-11 Eric 真機回報）。isLoading 從此只在
    // ask() 明確設 loading 時為真＝真的有問題在送。
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
      var outboundTurns = _seedTurns(resumablePrevious);
      // 跨天備案（2026-08-18 拍板）：超過 24h resume 窗的上一筆結果不再接回
      // 同 session，但把重點壓成一組 digest turns 讓教練「記得上次聊到哪」。
      // 用既有 kind（question/answer）走既有 activeSessionTurns 通道，
      // 零 Edge schema 改動；sessionId 維持 null → 照常開新 session、
      // 不影響釐清次數與計費。
      if (outboundTurns.isEmpty && previousResult != null) {
        outboundTurns = _staleSessionDigestTurns(previousResult);
      }
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
      } else if (scope.isGlobal) {
        // global scope：不綁對象，scope.id 是哨兵值 'me' 不是 partnerId。
        partnerId = null;
      } else {
        // partner scope：對象即 scope 本體。Batch B1：補「最近一段有效對話」
        // 當個案證據（recentMessages/conversationSummary 走既有通道），
        // 沒有有效對話時維持現行為（Edge 首輪證據制釐清接手）。
        partnerId = scope.id;
        conversation =
            ref.read(coachPartnerSourceConversationProvider(scope.id));
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

      // await，不用 valueOrNull sync 讀：profile 還在載入時 sync 讀會讓冷啟動
      // 第一次 Coach 請求漏帶使用者風格（2026-08-03 修）。不是重放/計費
      // 問題——server 的 computeCoachInputHash 不含 effectiveStyleContext，
      // 風格值改變不會觸發 COACH_REQUEST_REPLAY_MISMATCH（cross-review 已核）。
      final effectiveStyleContext = await _styleContext(
        partnerId: partnerId,
        // global 沒有對象可覆寫，明確傳 false（不靠 partnerId null 隱含）。
        includePartnerOverride: scope.isGlobal ? false : !flagged,
      );

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
        effectiveStyleContext: effectiveStyleContext,
        partnerHint: _partnerHint(
          partnerId: partnerId,
          dataQualityFlagged: flagged,
        ),
        outcomeInsightLines: outcomeInsightLines,
        dataQualityFlagged: flagged,
        requestId: requestId,
        scope: scope,
        lifecyclePhase: lifecyclePhase,
        // Batch B1：只有 partner scope 標來源（server schema 對其他 scope
        // 拒收；api service 另有同規則守門）。
        contextProvenance: scope.isPartner && conversation != null
            ? CoachChatContextProvenance(
                sourceConversationId: conversation.id,
                lastMessageAt: lastNonEmptyMessageAt(conversation),
              )
            : null,
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

  /// 「想問別的」：關掉目前這串釐清並重開（2026-08-16 Bruce 回饋二輪）。
  ///
  /// 釐清輪免費、不含正式建議，整串連續的釐清列直接刪掉，露出上一個正式
  /// 回答（或空狀態）；session 歸零，下一個問題不再續接這條釐清脈絡。
  /// read-bridge 的 legacy 列刪不動時就地停下（遠古資料，不硬拗）。
  Future<void> discardClarifyingThread() async {
    if (_inFlight) return;
    final scope = arg;
    final repo = ref.read(coachChatRepositoryProvider);
    var latest = state.valueOrNull ?? repo.latestForScope(scope.type, scope.id);
    var removedAny = false;
    while (latest != null && latest.isClarifyingQuestion) {
      if (!await repo.deleteUnified(latest.id)) break;
      removedAny = true;
      latest = repo.latestForScope(scope.type, scope.id);
    }
    _activeSessionId = null;
    _activeTurns = const [];
    if (!removedAny) return;
    ref.invalidate(coachChatHistoryProvider(scope));
    state = AsyncValue.data(latest);
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
    // global 紀錄兩個外鍵皆 null（scope.id 'me' 不是 partnerId）。
    return UnifiedCoachResult(
      id: result.id,
      conversationId: null,
      partnerId: scope.isGlobal ? null : scope.id,
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
      scopeType: scope.isGlobal ? CoachScopeType.global : CoachScopeType.partner,
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

  /// 跨天「上次聊到」digest：一問一答兩個 turn。內容只取教練自己產出的
  /// 重點句（headline/nextStep/suggestedLine）＋既有 rollup 摘要，不帶
  /// 對話原文；schema 上限 500 字，這裡自行 clamp。
  List<CoachChatSessionTurn> _staleSessionDigestTurns(
    UnifiedCoachResult previous,
  ) {
    // 上次停在沒回答的釐清問題 → 沒有可延續的結論，不注入。
    // question 空字串過不了 Edge schema（min 1），一併跳過。
    if (previous.isClarifyingQuestion || previous.question.trim().isEmpty) {
      return const [];
    }
    String clamp(String value) =>
        value.length <= 500 ? value : '${value.substring(0, 499).trimRight()}…';
    final answerLines = <String>[
      '（上次聊到，僅供延續脈絡）${previous.headline}',
      if (previous.suggestedLine?.trim().isNotEmpty == true)
        '當時建議這樣說：${previous.suggestedLine!.trim()}',
      if (previous.nextStep.trim().isNotEmpty)
        '當時的下一步：${previous.nextStep.trim()}',
      if (previous.earlierSummary?.trim().isNotEmpty == true)
        previous.earlierSummary!.trim(),
    ];
    return [
      CoachChatSessionTurn(
        role: 'user',
        kind: 'question',
        content: clamp(previous.question.trim()),
        createdAt: previous.generatedAt,
      ),
      CoachChatSessionTurn(
        role: 'coach',
        kind: 'answer',
        content: clamp(answerLines.join('\n')),
        createdAt: previous.generatedAt,
      ),
    ];
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

  Future<String?> _styleContext({
    required String? partnerId,
    required bool includePartnerOverride,
  }) async {
    try {
      return await ref.read(coachChatStyleContextResolverProvider)(
        partnerId: partnerId,
        includePartnerOverride: includePartnerOverride,
      );
    } catch (_) {
      // profile/partner-style 載入失敗（Hive/repo 炸掉）就退回無風格，不擋
      // 整個 Coach 請求——風格是個人化加分項，不是必要輸入（Codex
      // cross-review P2 finding）。
      return null;
    }
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
      note: PartnerMemoryTagCatalog.sanitizedNote(partner.customNote),
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
