import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/services/storage_service.dart';
import '../../../analysis_history/data/providers/analysis_history_providers.dart';
import '../../../analysis_history/domain/entities/analysis_history_event.dart';
import '../../../analysis_history/domain/repositories/analysis_history_repository.dart';
import '../../../subscription/data/providers/subscription_providers.dart';
import '../../domain/entities/practice_draw_draft.dart';
import '../../domain/entities/practice_girl_catalog.dart';
import '../../domain/entities/practice_girl_rarity.dart';
import '../../domain/entities/practice_hint.dart';
import '../../domain/entities/practice_learning_mode.dart';
import '../../domain/entities/practice_message.dart';
import '../../domain/entities/practice_profile.dart';
import '../../domain/entities/practice_session.dart';
import '../repositories/practice_collection_store.dart';
import '../repositories/practice_draw_draft_store.dart';
import '../repositories/practice_pending_draw_store.dart';
import '../repositories/practice_pending_debrief_store.dart';
import '../repositories/practice_pending_hint_store.dart';
import '../repositories/practice_session_repository.dart';
import '../services/practice_chat_api_service.dart';

/// 一場練習最多 20 則 AI 回覆（與伺服器 MAX_AI_REPLIES 同步）。
const int kMaxPracticeAiReplies = 20;

/// 新手模式同一輪最多 5 次 Hint（與伺服器 MAX_HINTS_PER_ROUND 同步）。
const int kMaxPracticeHintsPerRound = 5;

// 溫度開場 fallback 隨難度走：見 initialPracticeTemperatureScore（practice_profile.dart，
// 鏡像 server DIFFICULTY_TUNING）。
const int kInitialPracticeFamiliarityScore = 0;
const String kInitialPracticeRelationshipStageLabel = '建立熟悉中';

/// Long local threads are summarized before sending prompts to Edge.
const int kPracticePromptRecentTurns = 80;
const int kPracticeMemorySummaryMaxChars = 800;

/// 專案鐵則：loading state 下 await 網路一律 .timeout。
/// server hint 首輪 12s（timeout 不重試）；非 timeout 重試輪再 +9s，最壞 21s。
/// ＋RPC／冷啟動約 22-24s，client 取 25s 蓋過 server 最壞預算。
const Duration kPracticeHintRequestTimeout = Duration(seconds: 25);

/// server chat 主回覆最壞 ≈ 30s × 2 次嘗試＋輪次分類器 30s ≈ 90s，
/// client 取 120s 留裕度：只防 loading 卡死，不搶在 server 完成前放棄。
const Duration kPracticeSendMessageTimeout = Duration(seconds: 120);

final RegExp _practiceRawImageFilenamePattern = RegExp(
  r'(?:[A-Za-z]:)?(?:[\\/][^\s\\/]+)*[\\/]?(?:S__\d+\.(?:jpe?g|png|webp|heic)|IMG_\d+\.(?:jpe?g|png|webp|heic)|[^\\/\s]+\.(?:jpe?g|png|webp|heic))',
  caseSensitive: false,
);

const Set<String> _practicePartnerMoodValues = {
  'neutral',
  'curious',
  'amused',
  'comfortable',
  'guarded',
  'annoyed',
};

PracticeLearningMode _modeAllowedForGirl(
  PracticeLearningMode mode,
  PracticeGirlProfile? girl,
) {
  if (mode == PracticeLearningMode.game &&
      girl?.rarity != PracticeGirlRarity.sr) {
    return PracticeLearningMode.beginner;
  }
  return mode;
}

const _sentinel = Object();

enum _HintPrefetchFlightOutcome {
  persistFailed,
  readyAfterAck,
  readyAfterPrefetchFailure,
}

class _HintPrefetchPayload {
  const _HintPrefetchPayload({
    required this.profile,
    required this.turns,
    required this.memorySummary,
    required this.continuationPartnerState,
    required this.roundIndex,
    required this.visiblePracticeThreadId,
    required this.practiceMode,
  });

  final PracticeProfileDto profile;
  final List<PracticeTurnDto> turns;
  final String? memorySummary;
  final PracticePartnerState? continuationPartnerState;
  final int roundIndex;
  final String? visiblePracticeThreadId;
  final PracticeLearningMode practiceMode;
}

class _HintPrefetchFlight {
  _HintPrefetchFlight({
    required this.pending,
    required this.payload,
    required this.generation,
    required this.shouldPrefetch,
    required this.dependency,
    required this.previousAttempted,
  });

  final PracticePendingHint pending;
  final _HintPrefetchPayload payload;
  final int generation;
  final bool shouldPrefetch;
  final _HintPrefetchFlight? dependency;
  final bool previousAttempted;
  final Completer<_HintPrefetchFlightOutcome> completer =
      Completer<_HintPrefetchFlightOutcome>();

  Future<_HintPrefetchFlightOutcome> get outcome => completer.future;
}

/// 每日翻牌的揭曉狀態。locked＝今天還沒翻牌（不顯示任何對象）；drawing＝抽牌中；
/// revealed＝已有今日對象可開聊；error＝抽牌失敗（locked 情境下用，仍可重抽）。
enum PracticeDrawStatus { locked, drawing, revealed, error }

class PracticeChatState {
  final String sessionId;
  final DateTime createdAt;
  final List<PracticeMessage> messages;
  final bool isSending;
  final bool isPersistingTurn;
  final bool isDebriefing;
  final int aiReplyCount;
  final bool sessionComplete; // 已達 20 則
  final bool ended; // 使用者已結束練習，輸入鎖定
  final PracticeDebrief? debrief;
  final bool debriefFailed; // 拆解失敗，不回到普通輸入列
  final bool debriefRetryable; // true 顯示再試一次；false 只允許完成
  final String? errorMessage;
  final bool quotaExceeded;
  final bool upgradeRequired; // Free 續同一位被擋（402）：導向付費牆，與額度用罄分開
  final String? restoreText; // 失敗時把使用者剛打的字還回輸入列
  final PracticeLearningMode learningMode;
  final int? temperatureScore;

  /// server 回的溫度分檔（frozen/cold/neutral/warm/hot）；真相源在 server。
  /// 還原（Hive/draft 不存 band）或尚未收到回合時為 null → UI 用 score
  /// 鏡像 server 邊界查表兜底（practice_temperature_style.dart）。
  final String? temperatureBand;
  final int? familiarityScore;
  final String? relationshipStageLabel;
  final int? lastTemperatureDelta;
  final String? temperatureReason;
  final bool isHintLoading;
  final List<PracticeHintReply> hintReplies;
  final String? hintCoaching;
  final int hintUsedCount;
  final bool hintLimitReached;

  // ── 每日翻牌：揭曉狀態與免費額度狀態 ──
  /// 翻牌揭曉狀態。locked / drawing 時 [girl] 為 null，畫面不得顯示任何對象。
  final PracticeDrawStatus drawStatus;

  /// 本場對象（catalog-profile）：display-only 身份；尚未翻牌（locked/drawing）時為 null。
  final PracticeGirlProfile? girl;

  /// 翻牌免費額度狀態（server 為單一真實來源；給付費牆／提示文案用）。
  final int? drawFreeAllowance;
  final int? drawFreeUsed;
  final int? drawFreeRemaining;
  final int? drawExtraCost; // 免費用完後每次額外翻牌的成本（一般 quota）
  final String? drawNextResetAt; // 下一次免費翻牌重置點（ISO；Asia/Taipei 中午）
  final bool drawUpgradeRequired; // Free 翻牌用完且不可付費額外（402）→ 導升級
  final bool drawQuotaExceeded; // 付費額外翻牌但 quota 不足（429）

  // ── 本場角色＋難度（開場前可改；送出第一則後鎖定）──
  final PracticeDifficultyPreference difficultyPreference;
  final String personaId;
  final String personaLabel;
  final String difficulty;
  final String difficultyLabel;

  // ── 續玩同一位：roundIndex 第幾輪；threadId 跨輪穩定識別（log 用）──
  final int roundIndex;
  final String? visiblePracticeThreadId;

  const PracticeChatState({
    required this.sessionId,
    required this.createdAt,
    required this.girl,
    required this.personaId,
    required this.personaLabel,
    required this.difficulty,
    required this.difficultyLabel,
    this.drawStatus = PracticeDrawStatus.revealed,
    this.drawFreeAllowance,
    this.drawFreeUsed,
    this.drawFreeRemaining,
    this.drawExtraCost,
    this.drawNextResetAt,
    this.drawUpgradeRequired = false,
    this.drawQuotaExceeded = false,
    this.difficultyPreference = PracticeDifficultyPreference.normal,
    this.messages = const [],
    this.isSending = false,
    this.isPersistingTurn = false,
    this.isDebriefing = false,
    this.aiReplyCount = 0,
    this.sessionComplete = false,
    this.ended = false,
    this.debrief,
    this.debriefFailed = false,
    this.debriefRetryable = true,
    this.errorMessage,
    this.quotaExceeded = false,
    this.upgradeRequired = false,
    this.restoreText,
    this.learningMode = PracticeLearningMode.standard,
    this.temperatureScore,
    this.temperatureBand,
    this.familiarityScore,
    this.relationshipStageLabel,
    this.lastTemperatureDelta,
    this.temperatureReason,
    this.isHintLoading = false,
    this.hintReplies = const [],
    this.hintCoaching,
    this.hintUsedCount = 0,
    this.hintLimitReached = false,
    this.roundIndex = 1,
    this.visiblePracticeThreadId,
  });

  bool get isRevealed => drawStatus == PracticeDrawStatus.revealed;
  bool get isDrawing => drawStatus == PracticeDrawStatus.drawing;
  bool get isLocked => drawStatus != PracticeDrawStatus.revealed;

  int get remainingReplies =>
      (kMaxPracticeAiReplies - aiReplyCount).clamp(0, kMaxPracticeAiReplies);

  /// 必須先翻好牌（revealed）才能送訊息；hint 在途也擋（與 canRequestHint 的
  /// !isSending 成雙向互斥，避免平行請求交錯覆寫）。
  bool get canSend =>
      isRevealed &&
      !isSending &&
      !isPersistingTurn &&
      !isDebriefing &&
      !isHintLoading &&
      !ended &&
      !sessionComplete;

  bool get isBeginnerMode => learningMode == PracticeLearningMode.beginner;
  bool get isAssistedLearningMode => learningMode.usesAssistedLearning;
  bool get canUseGameMode => girl?.rarity == PracticeGirlRarity.sr;

  bool get canChangeLearningMode =>
      isRevealed &&
      messages.isEmpty &&
      !isSending &&
      !isPersistingTurn &&
      !isDebriefing;

  bool get canRequestHint =>
      isAssistedLearningMode &&
      isRevealed &&
      !hintLimitReached &&
      hintUsedCount < kMaxPracticeHintsPerRound &&
      !isHintLoading &&
      !isSending &&
      !isDebriefing &&
      !ended &&
      !sessionComplete &&
      girl != null &&
      aiReplyCount >= 1 &&
      messages.isNotEmpty &&
      messages.last.role == 'ai';

  /// 至少有一則 AI 回覆、尚未拆解，才能結束練習看拆解卡。
  bool get canDebrief =>
      aiReplyCount >= 1 &&
      !isDebriefing &&
      !isSending &&
      !isPersistingTurn &&
      debrief == null &&
      (!debriefFailed || debriefRetryable);

  PracticeChatState copyWith({
    List<PracticeMessage>? messages,
    bool? isSending,
    bool? isPersistingTurn,
    bool? isDebriefing,
    int? aiReplyCount,
    bool? sessionComplete,
    bool? ended,
    bool? debriefFailed,
    bool? debriefRetryable,
    bool? quotaExceeded,
    bool? upgradeRequired,
    PracticeDrawStatus? drawStatus,
    PracticeGirlProfile? girl,
    int? drawFreeAllowance,
    int? drawFreeUsed,
    int? drawFreeRemaining,
    int? drawExtraCost,
    String? drawNextResetAt,
    bool? drawUpgradeRequired,
    bool? drawQuotaExceeded,
    PracticeDifficultyPreference? difficultyPreference,
    String? personaId,
    String? personaLabel,
    String? difficulty,
    String? difficultyLabel,
    int? roundIndex,
    String? visiblePracticeThreadId,
    PracticeLearningMode? learningMode,
    bool? isHintLoading,
    List<PracticeHintReply>? hintReplies,
    int? hintUsedCount,
    bool? hintLimitReached,
    Object? debrief = _sentinel,
    Object? errorMessage = _sentinel,
    Object? restoreText = _sentinel,
    Object? temperatureScore = _sentinel,
    Object? temperatureBand = _sentinel,
    Object? familiarityScore = _sentinel,
    Object? relationshipStageLabel = _sentinel,
    Object? lastTemperatureDelta = _sentinel,
    Object? temperatureReason = _sentinel,
    Object? hintCoaching = _sentinel,
  }) {
    return PracticeChatState(
      sessionId: sessionId,
      createdAt: createdAt,
      girl: girl ?? this.girl,
      drawStatus: drawStatus ?? this.drawStatus,
      drawFreeAllowance: drawFreeAllowance ?? this.drawFreeAllowance,
      drawFreeUsed: drawFreeUsed ?? this.drawFreeUsed,
      drawFreeRemaining: drawFreeRemaining ?? this.drawFreeRemaining,
      drawExtraCost: drawExtraCost ?? this.drawExtraCost,
      drawNextResetAt: drawNextResetAt ?? this.drawNextResetAt,
      drawUpgradeRequired: drawUpgradeRequired ?? this.drawUpgradeRequired,
      drawQuotaExceeded: drawQuotaExceeded ?? this.drawQuotaExceeded,
      messages: messages ?? this.messages,
      isSending: isSending ?? this.isSending,
      isPersistingTurn: isPersistingTurn ?? this.isPersistingTurn,
      isDebriefing: isDebriefing ?? this.isDebriefing,
      aiReplyCount: aiReplyCount ?? this.aiReplyCount,
      sessionComplete: sessionComplete ?? this.sessionComplete,
      ended: ended ?? this.ended,
      debriefFailed: debriefFailed ?? this.debriefFailed,
      debriefRetryable: debriefRetryable ?? this.debriefRetryable,
      quotaExceeded: quotaExceeded ?? this.quotaExceeded,
      upgradeRequired: upgradeRequired ?? this.upgradeRequired,
      difficultyPreference: difficultyPreference ?? this.difficultyPreference,
      personaId: personaId ?? this.personaId,
      personaLabel: personaLabel ?? this.personaLabel,
      difficulty: difficulty ?? this.difficulty,
      difficultyLabel: difficultyLabel ?? this.difficultyLabel,
      roundIndex: roundIndex ?? this.roundIndex,
      visiblePracticeThreadId:
          visiblePracticeThreadId ?? this.visiblePracticeThreadId,
      learningMode: learningMode ?? this.learningMode,
      temperatureScore: identical(temperatureScore, _sentinel)
          ? this.temperatureScore
          : temperatureScore as int?,
      temperatureBand: identical(temperatureBand, _sentinel)
          ? this.temperatureBand
          : temperatureBand as String?,
      familiarityScore: identical(familiarityScore, _sentinel)
          ? this.familiarityScore
          : familiarityScore as int?,
      relationshipStageLabel: identical(relationshipStageLabel, _sentinel)
          ? this.relationshipStageLabel
          : relationshipStageLabel as String?,
      lastTemperatureDelta: identical(lastTemperatureDelta, _sentinel)
          ? this.lastTemperatureDelta
          : lastTemperatureDelta as int?,
      temperatureReason: identical(temperatureReason, _sentinel)
          ? this.temperatureReason
          : temperatureReason as String?,
      isHintLoading: isHintLoading ?? this.isHintLoading,
      hintReplies: hintReplies ?? this.hintReplies,
      hintCoaching: identical(hintCoaching, _sentinel)
          ? this.hintCoaching
          : hintCoaching as String?,
      hintUsedCount: hintUsedCount ?? this.hintUsedCount,
      hintLimitReached: hintLimitReached ?? this.hintLimitReached,
      debrief: identical(debrief, _sentinel)
          ? this.debrief
          : debrief as PracticeDebrief?,
      errorMessage: identical(errorMessage, _sentinel)
          ? this.errorMessage
          : errorMessage as String?,
      restoreText: identical(restoreText, _sentinel)
          ? this.restoreText
          : restoreText as String?,
    );
  }
}

class PracticeChatController extends StateNotifier<PracticeChatState> {
  PracticeChatController({
    required PracticeChatApiService api,
    required PracticeSessionRepository repository,
    PracticeDrawDraftStore? draftStore,
    PracticePendingHintStore? pendingHintStore,
    PracticePendingDrawStore? pendingDrawStore,
    void Function({required int monthlyRemaining, required int dailyRemaining})?
        onUsageSynced,
    void Function(String profileId)? onProfileUnlocked,
    AnalysisHistoryRepository? historyRepository,
    PracticeSession? initialSession,
    String? sessionId,
    DateTime? createdAt,
    DateTime? now,
    Duration? hintRequestTimeout,
    Duration? sendMessageTimeout,
  }) : this._(
          api: api,
          repository: repository,
          draftStore: draftStore ?? InMemoryPracticeDrawDraftStore(),
          pendingHintStore:
              pendingHintStore ?? InMemoryPracticePendingHintStore(),
          pendingDrawStore:
              pendingDrawStore ?? InMemoryPracticePendingDrawStore(),
          onUsageSynced: onUsageSynced,
          onProfileUnlocked: onProfileUnlocked,
          historyRepository: historyRepository,
          initialSession: initialSession,
          sessionId: sessionId,
          createdAt: createdAt,
          now: now ?? DateTime.now(),
          hintRequestTimeout: hintRequestTimeout ?? kPracticeHintRequestTimeout,
          sendMessageTimeout: sendMessageTimeout ?? kPracticeSendMessageTimeout,
        );

  PracticeChatController._({
    required PracticeChatApiService api,
    required PracticeSessionRepository repository,
    required PracticeDrawDraftStore draftStore,
    required PracticePendingHintStore pendingHintStore,
    required PracticePendingDrawStore pendingDrawStore,
    required void Function(
            {required int monthlyRemaining, required int dailyRemaining})?
        onUsageSynced,
    required void Function(String profileId)? onProfileUnlocked,
    required AnalysisHistoryRepository? historyRepository,
    required PracticeSession? initialSession,
    required String? sessionId,
    required DateTime? createdAt,
    required DateTime now,
    required Duration hintRequestTimeout,
    required Duration sendMessageTimeout,
  })  : _api = api,
        _repo = repository,
        _draftStore = draftStore,
        _pendingHintStore = pendingHintStore,
        _pendingDrawStore = pendingDrawStore,
        _onUsageSynced = onUsageSynced,
        _onProfileUnlocked = onProfileUnlocked,
        _historyRepository = historyRepository,
        _hintRequestTimeout = hintRequestTimeout,
        _sendMessageTimeout = sendMessageTimeout,
        super(_initialState(
          initialSession: initialSession,
          draft: _validDraft(draftStore, now),
          sessionId: sessionId,
          createdAt: createdAt ?? now,
        )) {
    // 圖鑑種子：進場還原到的當前對象（session 或 draft）視同已解鎖。
    _notifyProfileUnlocked(state.girl?.profileId);
  }

  final PracticeChatApiService _api;
  final PracticeSessionRepository _repo;
  final PracticeDrawDraftStore _draftStore;
  final PracticePendingHintStore _pendingHintStore;
  final PracticePendingDrawStore _pendingDrawStore;
  final void Function(
      {required int monthlyRemaining,
      required int dailyRemaining})? _onUsageSynced;
  final void Function(String profileId)? _onProfileUnlocked;
  final AnalysisHistoryRepository? _historyRepository;
  final Duration _hintRequestTimeout;
  final Duration _sendMessageTimeout;
  final List<PracticeAppliedHintTurnDto> _appliedHintTurns = [];

  /// 圖鑑解鎖記錄：純附加 side-channel。用 microtask 延後（provider 建構期
  /// 不得同步改其他 provider 的 state），callback 例外一律吞掉——圖鑑記錄
  /// 失敗絕不影響練習主流程。
  void _notifyProfileUnlocked(String? profileId) {
    final callback = _onProfileUnlocked;
    if (callback == null || profileId == null || profileId.isEmpty) return;
    scheduleMicrotask(() {
      try {
        callback(profileId);
      } catch (_) {
        // 圖鑑記錄失敗不阻斷練習。
      }
    });
  }

  /// hint 扣費 idempotency（比照 opener requestId 生命週期）：發起時若為 null
  /// 才鑄新 id；失敗（timeout/5xx/網路）沿用同 id 供重試，成功或 4xx 明確拒絕
  /// 才清空 rotate。記憶體 pending 帶指紋（sessionId＋aiCount），與持久化
  /// store 同語意：沿用前必核對指紋，對話推進（aiCount 變動）後自動作廢——
  /// 否則新回合沿用舊 id，server 會 replay 上一回合的舊 hint（牛頭不對馬嘴）。
  PracticePendingHint? _pendingHintRequest;
  _HintPrefetchFlight? _hintPrefetchFlight;
  bool _hintPrefetchAttemptedSinceFormalDispatch = false;
  bool _hintRequiresConversationAdvance = false;
  Object? _activeSendPipelineToken;

  PracticePendingHint? _loadPendingHintSafely() {
    try {
      return _pendingHintStore.load();
    } catch (_) {
      return null;
    }
  }

  Future<void> _savePendingHintSafely(PracticePendingHint pending) async {
    try {
      await _pendingHintStore.save(pending);
    } catch (_) {
      // Pending persistence is a replay safety net; memory ownership remains.
    }
  }

  Future<void> _clearPendingHintSafely() async {
    try {
      await _pendingHintStore.clear();
    } catch (_) {
      // A stale row is harmless because every read validates its fingerprint.
    }
  }

  ({PracticePendingHint pending, Future<void> saved}) _loadOrCreatePendingHint({
    required String sessionId,
    required int aiCount,
  }) {
    final pending = _candidatePendingHint(
      sessionId: sessionId,
      aiCount: aiCount,
    );
    _pendingHintRequest = pending;
    return (
      pending: pending,
      saved: _savePendingHintSafely(pending),
    );
  }

  PracticePendingHint _candidatePendingHint({
    required String sessionId,
    required int aiCount,
  }) {
    bool matches(PracticePendingHint pending) =>
        pending.sessionId == sessionId && pending.aiCount == aiCount;

    final memoryPending = _pendingHintRequest;
    final storedPending = _loadPendingHintSafely();
    final requestId = memoryPending != null && matches(memoryPending)
        ? memoryPending.requestId
        : storedPending != null && matches(storedPending)
            ? storedPending.requestId
            : const Uuid().v4();
    final pending = PracticePendingHint(
      sessionId: sessionId,
      aiCount: aiCount,
      requestId: requestId,
    );
    return pending;
  }

  /// 成功或 4xx 明確拒絕 → rotate：清記憶體＋清持久化 store。5xx/timeout
  /// **不**走這裡（兩者都保留，重試與重建後沿用）。dispose 也不清——在途 id
  /// 必須活過 autoDispose 重建，server 才能 replay 不雙扣。
  /// 只在完成的 [completedId] 仍是當前 pending id 時才清：過期舊回應完成時
  /// pending 可能已被較新的 hint 覆寫，不得把新 id 連帶清掉（會失去 replay 保護）。
  void _rotateHintRequestId(String completedId) {
    if (_pendingHintRequest?.requestId == completedId) {
      _pendingHintRequest = null;
    }
    // store 是跨 controller 共用的：autoDispose 後舊 controller 的在途請求
    // 可能晚到，這時 store 裡已是新 controller 的 id——只有 store 現值就是
    // 完成中的 id 才清，絕不誤刪別人的 replay 保護。
    final stored = _loadPendingHintSafely();
    if (stored != null && stored.requestId == completedId) {
      unawaited(_clearPendingHintSafely());
    }
  }

  /// 換場（送出新訊息／續玩／換一位／還原場次）時的無條件清：在途扣費 id
  /// 只對舊場有意義。
  void _clearPendingHintRequestId() {
    _pendingHintRequest = null;
    _hintPrefetchFlight = null;
    _hintPrefetchAttemptedSinceFormalDispatch = false;
    _hintRequiresConversationAdvance = false;
    // A lifecycle change may start a send in the new session while an old
    // provider/persistence Future is still unwinding. Identity-checked finally
    // blocks below keep that old operation from releasing the new owner.
    _activeSendPipelineToken = null;
    _appliedHintTurns.clear();
    unawaited(_clearPendingHintSafely());
  }

  /// 翻牌成功或 4xx 明確拒絕 → rotate。網路／5xx 不走這裡（保留供重試
  /// replay）。只在 store 現值仍是完成中的 id 才清：晚到的舊回應不得誤刪
  /// 較新 pending 的 replay 保護（同 hint 的防護）。
  void _rotateDrawRequestId(String completedId) {
    final stored = _pendingDrawStore.load();
    if (stored != null && stored.requestId == completedId) {
      unawaited(_pendingDrawStore.clear());
    }
  }

  /// hint 世代序號：送出新訊息／續玩／換一位／還原場次都 +1。在途 hint 回應
  /// 到達時序號不符＝過期（針對的 transcript 已翻頁）→ 丟棄不填 state。
  int _hintGeneration = 0;

  _HintPrefetchFlight? _prepareHintPrefetchFlight() {
    if (!state.canRequestHint) return null;

    final previousFlight =
        _hintPrefetchFlight?.pending.sessionId == state.sessionId
            ? _hintPrefetchFlight
            : null;
    final previousAttempted = _hintPrefetchAttemptedSinceFormalDispatch;
    final pending = _candidatePendingHint(
      sessionId: state.sessionId,
      aiCount: state.aiReplyCount,
    );
    final shouldPrefetch = !previousAttempted;
    final flight = _HintPrefetchFlight(
      pending: pending,
      payload: _HintPrefetchPayload(
        profile: _profileDto(),
        turns: _turnDtosForPrompt(state.messages),
        memorySummary: _memorySummaryForPrompt(state.messages),
        continuationPartnerState: _lastPartnerStateForPrompt(state.messages),
        roundIndex: state.roundIndex,
        visiblePracticeThreadId: state.visiblePracticeThreadId,
        practiceMode: state.learningMode,
      ),
      generation: _hintGeneration,
      shouldPrefetch: shouldPrefetch,
      dependency: previousFlight,
      previousAttempted: previousAttempted,
    );
    _hintPrefetchFlight = flight;
    if (shouldPrefetch) {
      _hintPrefetchAttemptedSinceFormalDispatch = true;
    }
    return flight;
  }

  void _launchHintPrefetchAfterPersist(_HintPrefetchFlight flight) {
    unawaited(_runHintPrefetchAfterPersist(flight));
  }

  Future<void> _runHintPrefetchAfterPersist(
    _HintPrefetchFlight flight,
  ) async {
    if (!flight.shouldPrefetch) {
      try {
        await flight.dependency?.outcome;
      } catch (_) {
        // A dependency is only a session-wide latch barrier. Its HTTP failure
        // still permits the formal request after the barrier completes.
      }
    }

    bool stillCurrent() =>
        mounted &&
        identical(_hintPrefetchFlight, flight) &&
        state.sessionId == flight.pending.sessionId &&
        state.aiReplyCount == flight.pending.aiCount &&
        _hintGeneration == flight.generation;
    if (!stillCurrent()) {
      _finishHintPrefetchFlight(
        flight,
        _HintPrefetchFlightOutcome.readyAfterPrefetchFailure,
      );
      return;
    }

    // The candidate request id becomes controller/store truth only after the
    // matching session turn is durable. Persist failure therefore needs no
    // asynchronous pending-store rollback and cannot overwrite a newer flight.
    _pendingHintRequest = flight.pending;
    await _savePendingHintSafely(flight.pending);
    if (!stillCurrent()) {
      _finishHintPrefetchFlight(
        flight,
        _HintPrefetchFlightOutcome.readyAfterPrefetchFailure,
      );
      return;
    }

    if (!flight.shouldPrefetch) {
      _finishHintPrefetchFlight(
        flight,
        _HintPrefetchFlightOutcome.readyAfterPrefetchFailure,
      );
      return;
    }

    var outcome = _HintPrefetchFlightOutcome.readyAfterAck;
    try {
      final payload = flight.payload;
      await _api
          .prefetchHint(
            sessionId: flight.pending.sessionId,
            requestId: flight.pending.requestId,
            profile: payload.profile,
            turns: payload.turns,
            expectedAiCount: flight.pending.aiCount,
            memorySummary: payload.memorySummary,
            continuationPartnerState: payload.continuationPartnerState,
            roundIndex: payload.roundIndex,
            visiblePracticeThreadId: payload.visiblePracticeThreadId,
            practiceMode: payload.practiceMode,
          )
          .timeout(_hintRequestTimeout);
    } catch (_) {
      outcome = _HintPrefetchFlightOutcome.readyAfterPrefetchFailure;
    }
    _finishHintPrefetchFlight(flight, outcome);
  }

  void _finishHintPrefetchFlight(
    _HintPrefetchFlight flight,
    _HintPrefetchFlightOutcome outcome,
  ) {
    if (identical(_hintPrefetchFlight, flight)) {
      _hintPrefetchFlight = null;
    }
    if (!flight.completer.isCompleted) {
      flight.completer.complete(outcome);
    }
  }

  void _markHintPrefetchPersistFailed(
    _HintPrefetchFlight flight,
  ) {
    if (identical(_hintPrefetchFlight, flight)) {
      _hintPrefetchAttemptedSinceFormalDispatch = flight.previousAttempted;
      final dependency = flight.dependency;
      _hintPrefetchFlight =
          dependency != null && !dependency.completer.isCompleted
              ? dependency
              : null;
    }
    if (!flight.completer.isCompleted) {
      flight.completer.complete(_HintPrefetchFlightOutcome.persistFailed);
    }
  }

  bool _hintIntentStillValid({
    required String sessionId,
    required int aiCount,
    required int generation,
  }) =>
      mounted &&
      state.sessionId == sessionId &&
      state.aiReplyCount == aiCount &&
      _hintGeneration == generation &&
      state.copyWith(isHintLoading: false).canRequestHint;

  void _releaseHintLoadingForIntent({
    required String sessionId,
    required int generation,
  }) {
    if (mounted &&
        state.sessionId == sessionId &&
        _hintGeneration == generation &&
        state.isHintLoading) {
      state = state.copyWith(isHintLoading: false);
    }
  }

  /// debrief 世代序號：換場／續玩／換一位時遞增。晚到的舊場結果（成功或
  /// 失敗）不得改寫目前場次、持久化到錯的 session，或確認錯的 requestId。
  int _debriefGeneration = 0;

  /// 過期 hint 回應統一丟棄點：已扣額度認列不回滾（server 事實），只是 UI 不
  /// 顯示誤導內容。過期 intent 絕不能碰目前場次的 loading：新場可能已有另一
  /// 個 formal Hint 在途。
  bool _dropStaleHint(int generation) {
    if (!mounted) return true;
    if (generation == _hintGeneration) return false;
    return true;
  }

  bool _isStaleDebrief(int generation, String sessionId) =>
      !mounted ||
      generation != _debriefGeneration ||
      state.sessionId != sessionId;

  /// 測試用：對外讀取目前狀態。
  @visibleForTesting
  PracticeChatState get currentState => state;

  /// 取回未過期的 draft；無／過期回 null。過期＝now 已到或超過 draft 的 nextResetAt
  /// （該草稿屬上一個重置視窗）。
  static PracticeDrawDraft? _validDraft(
    PracticeDrawDraftStore store,
    DateTime now,
  ) {
    final d = store.load();
    if (d == null) return null;
    if (!now.isBefore(d.nextResetAt)) return null; // now >= nextResetAt → 過期
    return d;
  }

  /// 進場初始 state：
  ///   1. 有未拆解 session → 還原該場（revealed）。
  ///   2. 否則有有效 draft → 還原同一位（revealed），不重抽。
  ///   3. 否則 → locked（不顯示任何對象，等使用者翻牌）。
  static PracticeChatState _initialState({
    required PracticeSession? initialSession,
    required PracticeDrawDraft? draft,
    required String? sessionId,
    required DateTime createdAt,
  }) {
    if (initialSession != null) return _stateFromSession(initialSession);
    if (draft != null) {
      final fromDraft = _stateFromDraft(draft);
      if (fromDraft != null) return fromDraft;
    }
    return _lockedState(sessionId: sessionId, createdAt: createdAt);
  }

  static PracticeChatState _lockedState({
    required String? sessionId,
    required DateTime createdAt,
  }) {
    final id = sessionId ?? const Uuid().v4();
    return PracticeChatState(
      sessionId: id,
      createdAt: createdAt,
      girl: null,
      personaId: '',
      personaLabel: '',
      difficulty: 'normal',
      difficultyLabel: practiceDifficultyLabel('normal'),
      drawStatus: PracticeDrawStatus.locked,
      visiblePracticeThreadId: id,
    );
  }

  /// 從 draft 還原「翻好但還沒開聊」的 revealed 狀態；profileId 無法解析回 null。
  static PracticeChatState? _stateFromDraft(PracticeDrawDraft draft) {
    final girl = girlProfileById(draft.profileId);
    if (girl == null) return null;
    final learningMode = _modeAllowedForGirl(draft.learningMode, girl);
    return PracticeChatState(
      sessionId: draft.sessionId,
      createdAt: draft.createdAt,
      girl: girl,
      personaId: draft.personaId,
      personaLabel: practicePersonaLabel(draft.personaId),
      difficulty: draft.difficulty,
      difficultyLabel: practiceDifficultyLabel(draft.difficulty),
      difficultyPreference: draft.difficultyPreference,
      drawStatus: PracticeDrawStatus.revealed,
      roundIndex: draft.roundIndex,
      visiblePracticeThreadId: draft.visiblePracticeThreadId,
      drawFreeAllowance: draft.freeAllowance,
      drawFreeUsed: draft.freeUsed,
      drawFreeRemaining: draft.freeRemaining,
      drawExtraCost: draft.extraCostMessages,
      drawNextResetAt: draft.nextResetAt.toIso8601String(),
      learningMode: learningMode,
      temperatureScore: learningMode.usesAssistedLearning
          ? draft.temperatureScore ??
              initialPracticeTemperatureScore(draft.difficulty)
          : null,
      familiarityScore: learningMode.usesAssistedLearning
          ? draft.familiarityScore ?? kInitialPracticeFamiliarityScore
          : null,
      relationshipStageLabel: learningMode.usesAssistedLearning
          ? draft.relationshipStageLabel ??
              kInitialPracticeRelationshipStageLabel
          : null,
      hintUsedCount: 0,
    );
  }

  static PracticeChatState _stateFromSession(PracticeSession session) {
    final gameBreakdown = PracticeGameBreakdown(
      phaseReached: session.debriefGamePhaseReached,
      missedVariable: session.debriefGameMissedVariable,
      failureState: session.debriefGameFailureState,
      nextFirstLine: session.debriefGameNextFirstLine,
      inviteDirection: session.debriefGameInviteDirection,
    );
    final debrief = session.hasDebrief
        ? PracticeDebrief(
            summary: session.debriefSummary ?? '',
            strengths: session.debriefStrengths,
            watchouts: session.debriefWatchouts,
            suggestedLine: session.debriefSuggestedLine ?? '',
            vibe: session.debriefVibe ?? '中性',
            dateChance: session.debriefDateChance,
            dateChanceReason: session.debriefDateChanceReason,
            nextInviteMove: session.debriefNextInviteMove,
            gameBreakdown: gameBreakdown.isEmpty ? null : gameBreakdown,
          )
        : null;
    // 對象身份：依 profileId 從 catalog 解析；舊場（無 profileId）兜底預設位。
    final girl =
        girlProfileById(session.profileId) ?? fallbackPracticeProfile().girl;
    final personaId = session.personaId ?? girl.personaId;
    final difficulty = session.difficulty ?? 'normal';
    final learningMode = _modeAllowedForGirl(
      PracticeLearningMode.fromWire(session.practiceMode),
      girl,
    );
    return PracticeChatState(
      sessionId: session.id,
      createdAt: session.createdAt,
      messages: session.messages,
      aiReplyCount: session.aiReplyCount,
      drawStatus: PracticeDrawStatus.revealed, // 既有場一定已有對象
      sessionComplete:
          debrief != null || session.aiReplyCount >= kMaxPracticeAiReplies,
      ended: debrief != null,
      debrief: debrief,
      debriefFailed: false,
      debriefRetryable: true,
      girl: girl,
      personaId: personaId,
      personaLabel: session.personaLabel ?? practicePersonaLabel(personaId),
      difficulty: difficulty,
      difficultyLabel:
          session.difficultyLabel ?? practiceDifficultyLabel(difficulty),
      roundIndex: session.roundIndex ?? 1,
      visiblePracticeThreadId: session.visiblePracticeThreadId ?? session.id,
      learningMode: learningMode,
      temperatureScore: learningMode.usesAssistedLearning
          ? session.temperatureScore ??
              initialPracticeTemperatureScore(difficulty)
          : null,
      familiarityScore: learningMode.usesAssistedLearning
          ? session.familiarityScore ?? kInitialPracticeFamiliarityScore
          : null,
      relationshipStageLabel: learningMode.usesAssistedLearning
          ? session.relationshipStageLabel ??
              kInitialPracticeRelationshipStageLabel
          : null,
      hintUsedCount:
          learningMode.usesAssistedLearning ? session.hintUsedCount ?? 0 : 0,
    );
  }

  void resumeSession(PracticeSession session) {
    if (session.id == state.sessionId) return;
    _hintGeneration++; // 換場：在途 hint 全部作廢
    _debriefGeneration++; // 換場：在途 debrief 成功／失敗全部作廢
    _clearPendingHintRequestId(); // 換場順手清：在途扣費 id 對舊場才有意義
    state = _stateFromSession(session);
    _notifyProfileUnlocked(state.girl?.profileId); // 圖鑑種子：還原場的對象
  }

  /// 圖鑑點已抽卡進對話：有未完成場次續玩、沒有就以該角色免費開新局。
  /// 不走 draw、不扣翻牌額度、不寫翻牌 draft／pending（都只由翻牌鏈路寫）。
  void startSessionWithProfile(String profileId) {
    // recentSessions 已依時間新到舊 → 第一筆吻合＝該對象最新一段未完成場。
    // 已拆解（hasDebrief）場不可續玩（比照歷史列表 _canResume 與
    // _latestOpenPracticeSession 的未完成判斷），否則 Free 會卡在拆解態的付費續聊 gate。
    for (final session in _repo.recentSessions()) {
      if (session.profileId == profileId &&
          !session.hasDebrief &&
          session.messages.isNotEmpty) {
        resumeSession(session);
        return;
      }
    }
    final girl = girlProfileById(profileId);
    if (girl == null) return; // catalog 解析不到：不碰 state
    _hintGeneration++; // 換場：在途 hint 全部作廢
    _debriefGeneration++; // 換場：在途 debrief 成功／失敗全部作廢
    _clearPendingHintRequestId(); // 換場順手清：在途扣費 id 對舊場才有意義
    final prior = state;
    final sessionId = const Uuid().v4();
    // 難度沿用目前已解析值（比照 drawNewPracticeGirl；未解析時回偏好預設）。
    final difficulty = prior.difficulty.isNotEmpty
        ? prior.difficulty
        : practiceDifficultyId(prior.difficultyPreference);
    final learningMode = _modeAllowedForGirl(prior.learningMode, girl);
    state = PracticeChatState(
      sessionId: sessionId,
      createdAt: DateTime.now(),
      girl: girl,
      personaId: girl.personaId,
      personaLabel: practicePersonaLabel(girl.personaId),
      difficulty: difficulty,
      difficultyLabel: practiceDifficultyLabel(difficulty),
      difficultyPreference: prior.difficultyPreference,
      drawStatus: PracticeDrawStatus.revealed,
      roundIndex: 1,
      visiblePracticeThreadId: sessionId,
      learningMode: learningMode,
      temperatureScore: learningMode.usesAssistedLearning
          ? initialPracticeTemperatureScore(difficulty)
          : null,
      familiarityScore: learningMode.usesAssistedLearning
          ? kInitialPracticeFamiliarityScore
          : null,
      relationshipStageLabel: learningMode.usesAssistedLearning
          ? kInitialPracticeRelationshipStageLabel
          : null,
      hintUsedCount: 0,
      // 非翻牌：額度快照沿用 prior（server 才是真實來源，這裡不造新值）。
      drawFreeAllowance: prior.drawFreeAllowance,
      drawFreeUsed: prior.drawFreeUsed,
      drawFreeRemaining: prior.drawFreeRemaining,
      drawExtraCost: prior.drawExtraCost,
      drawNextResetAt: prior.drawNextResetAt,
    );
    _notifyProfileUnlocked(girl.profileId); // 圖鑑：冪等，無害
  }

  /// 每日翻牌：呼叫 server 抽一位新對象並原子扣費。換一位（已 revealed 再抽）會帶上
  /// 目前這位以排除自己。成功 → 進 revealed、開全新一場（roundIndex 1）、存 draft。
  /// 任何失敗都**不**污染目前 profile／transcript（保留原狀態），只設對應旗標／訊息。
  Future<void> drawNewPracticeGirl() async {
    // A failed draw restores its captured prior state. Never let it capture a
    // transient turn-persistence flag whose owner may finish while draw is in
    // flight, otherwise the failure rollback can resurrect a permanent lock.
    if (state.isDrawing ||
        state.isPersistingTurn ||
        _activeSendPipelineToken != null) {
      return;
    }
    final prior = state;
    state = state.copyWith(
      drawStatus: PracticeDrawStatus.drawing,
      errorMessage: null,
      drawUpgradeRequired: false,
      drawQuotaExceeded: false,
      upgradeRequired: false,
      quotaExceeded: false,
    );

    // 翻牌扣費 idempotency（比照 hint pending 模式）：指紋（翻牌當下的
    // 目前對象）吻合就沿用在途 id——server 已入帳但回應丟失時，重試靠同
    // id 讓 server replay 同一位、不重扣。成功或 4xx 明確拒絕才 rotate。
    final priorProfileId = prior.girl?.profileId;
    final storedDraw = _pendingDrawStore.load();
    // TTL：null 指紋（locked 首抽）跨長時間會誤配陳年 id，超齡一律作廢。
    final drawRequestId = storedDraw != null &&
            storedDraw.currentProfileId == priorProfileId &&
            !storedDraw.isExpired
        ? storedDraw.requestId
        : const Uuid().v4();
    unawaited(_pendingDrawStore.save(PracticePendingDraw(
      currentProfileId: priorProfileId,
      requestId: drawRequestId,
      savedAt: DateTime.now(),
    )));

    try {
      final result = await _api.drawProfile(
        requestId: drawRequestId,
        currentProfileId: priorProfileId, // 換一位排除自己
        visiblePracticeThreadId: prior.visiblePracticeThreadId,
      );
      _rotateDrawRequestId(drawRequestId); // 成功 → rotate
      final girl = girlProfileById(result.profile.profileId) ??
          fallbackPracticeProfile().girl;
      final sessionId = const Uuid().v4();
      _hintGeneration++; // 換一位成功：在途 hint 對舊對象已無意義
      _debriefGeneration++; // 換一位成功：舊場 debrief 不得落到新對象
      _clearPendingHintRequestId(); // 換場順手清：在途扣費 id 對舊場才有意義
      // 難度沿用目前已解析值（換一位不重抽難度）；locked 首抽時為預設 normal。
      final difficulty = prior.difficulty.isNotEmpty
          ? prior.difficulty
          : practiceDifficultyId(prior.difficultyPreference);
      final learningMode = _modeAllowedForGirl(prior.learningMode, girl);

      state = PracticeChatState(
        sessionId: sessionId,
        createdAt: DateTime.now(),
        girl: girl,
        personaId: girl.personaId,
        personaLabel: practicePersonaLabel(girl.personaId),
        difficulty: difficulty,
        difficultyLabel: practiceDifficultyLabel(difficulty),
        difficultyPreference: prior.difficultyPreference,
        drawStatus: PracticeDrawStatus.revealed,
        roundIndex: 1,
        visiblePracticeThreadId: sessionId,
        learningMode: learningMode,
        temperatureScore: learningMode.usesAssistedLearning
            ? initialPracticeTemperatureScore(difficulty)
            : null,
        familiarityScore: learningMode.usesAssistedLearning
            ? kInitialPracticeFamiliarityScore
            : null,
        relationshipStageLabel: learningMode.usesAssistedLearning
            ? kInitialPracticeRelationshipStageLabel
            : null,
        hintUsedCount: 0,
        drawFreeAllowance: result.draw.freeAllowance,
        drawFreeUsed: result.draw.freeUsed,
        drawFreeRemaining: result.draw.freeRemaining,
        drawExtraCost: result.draw.extraCostMessages,
        drawNextResetAt: result.draw.nextResetAt,
      );
      await _saveDraftFromState(result.draw.nextResetAt);
      _notifyProfileUnlocked(girl.profileId); // 圖鑑：抽到即解鎖
      // 付費額外翻牌會扣一般 quota → 同步訂閱剩餘額度。
      if (result.draw.costMessages > 0) {
        _onUsageSynced?.call(
          monthlyRemaining: result.usage.monthlyRemaining,
          dailyRemaining: result.usage.dailyRemaining,
        );
      }
    } on PracticeDrawUpgradeRequiredException catch (e) {
      _rotateDrawRequestId(drawRequestId); // 4xx 明確拒絕 → rotate
      // Free 免費翻牌用完且不可付費額外：導升級。保留原狀態（不揭曉/不漂移）。
      state = prior.copyWith(
        drawUpgradeRequired: true,
        drawFreeAllowance: e.freeAllowance,
        drawExtraCost: e.extraCostMessages,
        drawNextResetAt: e.nextResetAt,
        errorMessage: '升級後每天可以翻更多陪練女孩。',
      );
    } on PracticeQuotaExceededException catch (e) {
      _rotateDrawRequestId(drawRequestId); // 4xx 明確拒絕 → rotate
      state = prior.copyWith(
        drawQuotaExceeded: true,
        errorMessage: e.message,
      );
    } catch (_) {
      // 網路／5xx：id 保留（不 rotate），重試沿用供 server replay 去重。
      // 一般失敗：revealed 時保留目前對象（只報錯）；locked 時標 error 讓 UI 可重抽。
      state = prior.copyWith(
        drawStatus: prior.isRevealed
            ? PracticeDrawStatus.revealed
            : PracticeDrawStatus.error,
        errorMessage: '翻牌失敗了，再試一次。',
      );
    }
  }

  /// 換一位開新陪練（== 翻一張新牌）。
  void lockDrawQuotaExceeded({
    String message = '今日額度已用完，明天再來或升級方案繼續練習。',
  }) {
    state = state.copyWith(
      drawQuotaExceeded: true,
      drawUpgradeRequired: false,
      errorMessage: message,
    );
  }

  /// 續玩「同一位」：開新 billing session，roundIndex+1，
  /// threadId 不變、訊息／角色／難度保留。不走 draw、不換對象、不消耗翻牌次數。
  /// beginner 溫度三元組沿用上一輪（續同一位保溫；delta／reason 歸零重來）。
  ///
  /// [isPaid]：Free 續同一位需升級，只觸發付費牆、不動 transcript／不扣費。
  void continueWithSamePartner({required bool isPaid}) {
    if (!isPaid) {
      state = state.copyWith(
        upgradeRequired: true,
        debriefFailed: false,
        debriefRetryable: true,
        errorMessage: '想和同一位繼續練習，升級後就能解鎖。',
      );
      return;
    }
    _hintGeneration++; // 開新一輪：在途 hint 全部作廢
    _debriefGeneration++; // 開新一輪：舊輪 debrief 不得落到新 session
    _clearPendingHintRequestId(); // 換場順手清：在途扣費 id 對舊場才有意義
    state = PracticeChatState(
      sessionId: const Uuid().v4(),
      createdAt: DateTime.now(),
      girl: state.girl, // 續同一位：身份不漂移
      personaId: state.personaId,
      personaLabel: state.personaLabel,
      difficulty: state.difficulty,
      difficultyLabel: state.difficultyLabel,
      difficultyPreference: state.difficultyPreference,
      drawStatus: PracticeDrawStatus.revealed,
      messages: state.messages,
      aiReplyCount: 0,
      roundIndex: state.roundIndex + 1,
      visiblePracticeThreadId: state.visiblePracticeThreadId,
      learningMode: state.learningMode,
      temperatureScore: state.isAssistedLearningMode
          ? (state.temperatureScore ??
              initialPracticeTemperatureScore(state.difficulty))
          : null,
      // 續同一位保溫：band 隨溫度三元組一起沿用（無值時 UI 用 score 鏡像兜底）。
      temperatureBand:
          state.isAssistedLearningMode ? state.temperatureBand : null,
      familiarityScore: state.isAssistedLearningMode
          ? (state.familiarityScore ?? kInitialPracticeFamiliarityScore)
          : null,
      relationshipStageLabel: state.isAssistedLearningMode
          ? (state.relationshipStageLabel ??
              kInitialPracticeRelationshipStageLabel)
          : null,
      hintUsedCount: 0,
    );
  }

  /// 由目前 state 組出 PracticeProfile（調難度的衍生用）。
  Future<void> setPracticeLearningMode(PracticeLearningMode mode) async {
    if (!state.canChangeLearningMode || state.learningMode == mode) return;
    if (mode == PracticeLearningMode.game && !state.canUseGameMode) return;
    final assisted = mode.usesAssistedLearning;
    state = state.copyWith(
      learningMode: mode,
      temperatureScore:
          assisted ? initialPracticeTemperatureScore(state.difficulty) : null,
      temperatureBand: null, // 重設為初始溫度：尚無 server band，UI 走 score 鏡像
      familiarityScore: assisted ? kInitialPracticeFamiliarityScore : null,
      relationshipStageLabel:
          assisted ? kInitialPracticeRelationshipStageLabel : null,
      lastTemperatureDelta: null,
      temperatureReason: null,
      isHintLoading: false,
      hintReplies: const [],
      hintCoaching: null,
      hintUsedCount: 0,
      hintLimitReached: false,
      errorMessage: null,
    );
    final nextReset = state.drawNextResetAt;
    if (nextReset != null) {
      await _saveDraftFromState(nextReset);
    }
  }

  PracticeProfile _stateProfile() => PracticeProfile(
        girl: state.girl!,
        personaId: state.personaId,
        personaLabel: state.personaLabel,
        difficulty: state.difficulty,
        difficultyLabel: state.difficultyLabel,
      );

  /// 送出一則使用者訊息並取得 AI 回覆。樂觀顯示使用者泡泡；任何失敗都回滾。
  /// 還沒翻牌（非 revealed）一律擋下並提示先翻開今日對象。
  Future<void> sendMessage(
    String text, {
    PracticeHintReplyType? appliedHintType,
    String? appliedHintText,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    if (!state.isRevealed || state.girl == null) {
      state = state.copyWith(errorMessage: '先翻開今日的陪練女孩，再開始聊天。');
      return;
    }
    if (!state.canSend || _activeSendPipelineToken != null) return;

    final priorState = state;
    final priorMessages = priorState.messages;
    final generationBeforeSend = _hintGeneration;
    final appliedHintTurnCountBeforeSend = _appliedHintTurns.length;
    void restoreAppliedHintTurns() {
      if (_appliedHintTurns.length > appliedHintTurnCountBeforeSend) {
        _appliedHintTurns.removeRange(
          appliedHintTurnCountBeforeSend,
          _appliedHintTurns.length,
        );
      }
    }

    bool ownsPriorSendState() =>
        mounted &&
        state.sessionId == priorState.sessionId &&
        _hintGeneration == generationBeforeSend;

    final learningMode = priorState.learningMode;
    final assisted = learningMode.usesAssistedLearning;
    final temperatureScore = assisted
        ? state.temperatureScore ??
            initialPracticeTemperatureScore(state.difficulty)
        : null;
    final familiarityScore = assisted
        ? state.familiarityScore ?? kInitialPracticeFamiliarityScore
        : null;
    final optimistic = [
      ...priorMessages,
      PracticeMessage(role: 'user', text: trimmed),
    ];
    state = state.copyWith(
      messages: optimistic,
      isSending: true,
      errorMessage: null,
      quotaExceeded: false,
      upgradeRequired: false,
      debriefFailed: false,
      debriefRetryable: true,
      restoreText: null,
      hintReplies: const [],
      hintCoaching: null,
      hintLimitReached: false,
    );
    // Keep the whole provider -> local persistence pipeline single-owner even
    // after the AI reply makes isSending false so Hint can await its placeholder.
    // Without this token, a second same-session send can start while the first
    // turn is persisting, then be erased by the older persistence rollback.
    final sendPipelineToken = Object();
    _activeSendPipelineToken = sendPipelineToken;

    try {
      final reply = await _api
          .sendMessage(
            sessionId: state.sessionId,
            profile: _profileDto(),
            turns: _turnDtosForPrompt(optimistic),
            memorySummary: _memorySummaryForPrompt(optimistic),
            continuationPartnerState: _lastPartnerStateForPrompt(priorMessages),
            roundIndex: state.roundIndex,
            visiblePracticeThreadId: state.visiblePracticeThreadId,
            practiceMode: learningMode,
            temperatureScore: temperatureScore,
            familiarityScore: familiarityScore,
            appliedHintType: assisted ? appliedHintType : null,
            appliedHintText: assisted ? appliedHintText : null,
          )
          .timeout(_sendMessageTimeout);
      if (!ownsPriorSendState()) return;
      _hintGeneration++; // 成功送出新訊息：舊 transcript 的在途 hint 已過期
      final completedTurnGeneration = _hintGeneration;
      final withAi = [
        ...optimistic,
        PracticeMessage(
          role: 'ai',
          text: reply.reply,
          mood: reply.partnerState?.mood,
          innerThought: reply.partnerState?.innerThought,
        ),
      ];
      final normalizedAppliedHintText = appliedHintText?.trim();
      if (assisted &&
          appliedHintType != null &&
          normalizedAppliedHintText != null &&
          normalizedAppliedHintText.isNotEmpty) {
        _appliedHintTurns.add(PracticeAppliedHintTurnDto(
          turnIndex: optimistic.length - 1,
          type: appliedHintType,
          originalHintText: normalizedAppliedHintText,
          sentText: trimmed,
          exact: normalizedAppliedHintText == trimmed,
        ));
        if (_appliedHintTurns.length > kMaxPracticeHintsPerRound) {
          _appliedHintTurns.removeRange(
            0,
            _appliedHintTurns.length - kMaxPracticeHintsPerRound,
          );
        }
      }
      final temperature = reply.temperature;
      final returnedFamiliarityScore =
          temperature?.familiarityScore ?? familiarityScore;
      state = state.copyWith(
        messages: withAi,
        isSending: false,
        isPersistingTurn: true,
        aiReplyCount: reply.aiTurnCount,
        sessionComplete: reply.sessionComplete,
        temperatureScore:
            assisted ? temperature?.score ?? temperatureScore : null,
        // band 真相源在 server：本回合沒回 temperature 就保留前值（與 score 同步）。
        temperatureBand:
            assisted ? temperature?.band ?? state.temperatureBand : null,
        familiarityScore: assisted ? returnedFamiliarityScore : null,
        relationshipStageLabel: assisted
            ? temperature?.stageLabel ?? state.relationshipStageLabel
            : null,
        lastTemperatureDelta: assisted ? temperature?.delta : null,
        temperatureReason: assisted ? temperature?.reason : null,
        hintUsedCount:
            assisted ? reply.hintUsedCount ?? state.hintUsedCount : 0,
      );
      // Establish the typed barrier synchronously before the first persistence
      // await. A Hint tap in this window must wait for durable session state and
      // must never retarget its billing intent to another session/turn.
      final hintPrefetchFlight = _prepareHintPrefetchFlight();
      try {
        await _persist();
      } catch (_) {
        final ownsFailedTurn = mounted &&
            state.sessionId == priorState.sessionId &&
            _hintGeneration == completedTurnGeneration &&
            state.aiReplyCount == reply.aiTurnCount;
        if (ownsFailedTurn) {
          _hintGeneration = generationBeforeSend;
          restoreAppliedHintTurns();
        }
        if (hintPrefetchFlight != null) {
          _markHintPrefetchPersistFailed(hintPrefetchFlight);
        }
        rethrow;
      }
      final ownsDurableTurn = mounted &&
          state.sessionId == priorState.sessionId &&
          _hintGeneration == completedTurnGeneration &&
          state.aiReplyCount == reply.aiTurnCount &&
          identical(_activeSendPipelineToken, sendPipelineToken);
      if (ownsDurableTurn) {
        state = state.copyWith(isPersistingTurn: false);
        // The authoritative turn is durable now. Release the chat/debrief gate
        // before non-critical draft and usage side channels; identity-checked
        // finally prevents this owner from clearing a newer send token.
        _activeSendPipelineToken = null;
      }
      _hintRequiresConversationAdvance = false;
      if (hintPrefetchFlight != null) {
        _launchHintPrefetchAfterPersist(hintPrefetchFlight);
      }
      // 第一則成功 → 草稿交棒給正式 session（之後靠 recentSessions 還原）。
      try {
        await _draftStore.clear();
      } catch (_) {
        // Session 已持久化；草稿清理失敗不得回滾已成功的 AI turn。
      }
      if (reply.costDeducted > 0 &&
          reply.monthlyRemaining != null &&
          reply.dailyRemaining != null) {
        try {
          _onUsageSynced?.call(
            monthlyRemaining: reply.monthlyRemaining!,
            dailyRemaining: reply.dailyRemaining!,
          );
        } catch (_) {
          // Usage UI sync is a side-channel after the durable session write.
        }
      }
    } on PracticeQuotaExceededException catch (e) {
      if (!ownsPriorSendState()) return;
      restoreAppliedHintTurns();
      state = priorState.copyWith(
        isSending: false,
        quotaExceeded: true,
        errorMessage: e.message,
        restoreText: trimmed,
      );
    } on PracticeSessionCompleteException {
      if (!ownsPriorSendState()) return;
      restoreAppliedHintTurns();
      state = priorState.copyWith(
        isSending: false,
        sessionComplete: true,
        errorMessage: '這場練習已達上限，看看教練拆解吧。',
        restoreText: trimmed,
      );
    } on PracticeModeLockedException {
      // 同一輪已用另一種模式進行中：只提示切回，絕不標 sessionComplete
      // （誤標會引導「續聊同一位」開新 billing session 多扣一則）、不鎖輸入。
      if (!ownsPriorSendState()) return;
      restoreAppliedHintTurns();
      state = priorState.copyWith(
        isSending: false,
        errorMessage: _practiceModeLockedMessage,
        restoreText: trimmed,
      );
    } on PracticeUpgradeRequiredException {
      if (!ownsPriorSendState()) return;
      restoreAppliedHintTurns();
      state = priorState.copyWith(
        isSending: false,
        upgradeRequired: true,
        errorMessage: '想和同一位繼續練習，升級後就能解鎖。',
        restoreText: trimmed,
      );
    } on PracticeApiException catch (e) {
      // 429＝server per-user 模型限流：顯示 server 稍等文案、不標 quota。
      if (!ownsPriorSendState()) return;
      restoreAppliedHintTurns();
      state = priorState.copyWith(
        isSending: false,
        errorMessage: e.status == 429 ? e.message : '生成失敗了，再試一次（這次不扣額度）。',
        restoreText: trimmed,
      );
    } on TimeoutException {
      // client 逾時：server 可能已完成並扣費，文案不得宣稱「這次不扣額度」。
      if (!ownsPriorSendState()) return;
      restoreAppliedHintTurns();
      state = priorState.copyWith(
        isSending: false,
        errorMessage: '回覆等太久了，請確認網路後再試一次。',
        restoreText: trimmed,
      );
    } catch (_) {
      if (!ownsPriorSendState()) return;
      restoreAppliedHintTurns();
      state = priorState.copyWith(
        isSending: false,
        errorMessage: '生成失敗了，再試一次（這次不扣額度）。',
        restoreText: trimmed,
      );
    } finally {
      if (identical(_activeSendPipelineToken, sendPipelineToken)) {
        _activeSendPipelineToken = null;
      }
    }
  }

  /// 結束練習，請伺服器產一張教練拆解卡（同場不另扣額度）。
  Future<void> requestHint() async {
    if (!state.canRequestHint) return;
    if (_hintRequiresConversationAdvance) {
      state = state.copyWith(
        isHintLoading: false,
        errorMessage: _hintStaleConversationMessage,
      );
      return;
    }
    final intentState = state;
    final intentSessionId = intentState.sessionId;
    final intentAiCount = intentState.aiReplyCount;
    final generation = _hintGeneration;
    final intentProfile = _profileDto();
    final intentTurns = _turnDtosForPrompt(intentState.messages);
    final intentMemorySummary = _memorySummaryForPrompt(intentState.messages);
    final intentPartnerState = _lastPartnerStateForPrompt(intentState.messages);
    final flight = _hintPrefetchFlight?.pending.sessionId == intentSessionId
        ? _hintPrefetchFlight
        : null;
    state = state.copyWith(
      isHintLoading: true,
      hintReplies: const [],
      hintCoaching: null,
      hintLimitReached: false,
      errorMessage: null,
      quotaExceeded: false,
      upgradeRequired: false,
    );

    _HintPrefetchFlightOutcome? flightOutcome;
    if (flight != null) {
      try {
        flightOutcome = await flight.outcome;
      } catch (_) {
        flightOutcome = _HintPrefetchFlightOutcome.readyAfterPrefetchFailure;
      }
    }

    final intentStillValid = _hintIntentStillValid(
      sessionId: intentSessionId,
      aiCount: intentAiCount,
      generation: generation,
    );
    if (flightOutcome == _HintPrefetchFlightOutcome.persistFailed ||
        !intentStillValid) {
      _releaseHintLoadingForIntent(
        sessionId: intentSessionId,
        generation: generation,
      );
      return;
    }

    final pendingWrite = _loadOrCreatePendingHint(
      sessionId: intentSessionId,
      aiCount: intentAiCount,
    );
    final requestId = pendingWrite.pending.requestId;
    unawaited(pendingWrite.saved);

    // Dispatch is the consumption boundary for the controller-only cost gate.
    // The DB still decides whether this exact request settles or generates.
    _hintPrefetchAttemptedSinceFormalDispatch = false;
    if (identical(_hintPrefetchFlight, flight)) {
      _hintPrefetchFlight = null;
    }

    try {
      final result = await _api
          .requestHint(
            sessionId: intentSessionId,
            requestId: requestId,
            profile: intentProfile,
            turns: intentTurns,
            expectedAiCount: intentAiCount,
            memorySummary: intentMemorySummary,
            continuationPartnerState: intentPartnerState,
            roundIndex: intentState.roundIndex,
            visiblePracticeThreadId: intentState.visiblePracticeThreadId,
            practiceMode: intentState.learningMode,
          )
          .timeout(_hintRequestTimeout);
      _rotateHintRequestId(requestId); // 成功 → rotate
      if (_dropStaleHint(generation)) {
        // 過期成功回應：內容不填、不持久化進新場；額度是 server 事實照樣同步。
        if (result.costDeducted > 0 &&
            result.monthlyRemaining != null &&
            result.dailyRemaining != null) {
          _onUsageSynced?.call(
            monthlyRemaining: result.monthlyRemaining!,
            dailyRemaining: result.dailyRemaining!,
          );
        }
        return;
      }
      state = state.copyWith(
        isHintLoading: false,
        hintReplies: result.replies,
        hintCoaching: result.coaching,
        hintUsedCount: result.hintUsedCount,
        hintLimitReached: result.hintUsedCount >= kMaxPracticeHintsPerRound,
      );
      await _persist();
      if (result.costDeducted > 0 &&
          result.monthlyRemaining != null &&
          result.dailyRemaining != null) {
        _onUsageSynced?.call(
          monthlyRemaining: result.monthlyRemaining!,
          dailyRemaining: result.dailyRemaining!,
        );
      }
    } on PracticeHintLimitException {
      _rotateHintRequestId(requestId); // 4xx 明確拒絕 → rotate
      if (_dropStaleHint(generation)) return;
      state = state.copyWith(
        isHintLoading: false,
        hintLimitReached: true,
        errorMessage: '這段練習的提示已用完，先試著用自己的話回覆看看。',
      );
    } on PracticeQuotaExceededException catch (e) {
      _rotateHintRequestId(requestId); // 4xx 明確拒絕 → rotate
      if (_dropStaleHint(generation)) return;
      state = state.copyWith(
        isHintLoading: false,
        quotaExceeded: true,
        errorMessage: e.message,
      );
    } on PracticeUpgradeRequiredException {
      _rotateHintRequestId(requestId); // 4xx 明確拒絕 → rotate
      if (_dropStaleHint(generation)) return;
      state = state.copyWith(
        isHintLoading: false,
        upgradeRequired: true,
        errorMessage: '這個提示會消耗訊息額度，升級後就能繼續使用。',
      );
    } on PracticeModeLockedException {
      _rotateHintRequestId(requestId); // 4xx 明確拒絕 → rotate
      if (_dropStaleHint(generation)) return;
      // 同 sendMessage 的 409 分流：提示切回原模式，不標 sessionComplete。
      state = state.copyWith(
        isHintLoading: false,
        errorMessage: _practiceModeLockedMessage,
      );
    } on PracticeApiException catch (e) {
      if (e.message == 'practice_hint_stale') {
        if (_dropStaleHint(generation)) return;
        // Keep the exact stale id as a persistent fence. Minting a fresh id
        // against the locally stale transcript could generate and charge a
        // Hint for the wrong server turn. A successful chat response advances
        // aiReplyCount, naturally replaces the fingerprint, and clears this
        // process-local block.
        _hintRequiresConversationAdvance = true;
        state = state.copyWith(
          isHintLoading: false,
          errorMessage: _hintStaleConversationMessage,
        );
        return;
      }
      // 429＝server per-user 模型限流：沒打模型、沒扣費、沒占 latch，
      // id 保留供等待後重試（沿用同 id 可吃 server replay 去重）。
      if (e.status == 429) {
        if (_dropStaleHint(generation)) return;
        state = state.copyWith(
          isHintLoading: false,
          errorMessage: e.message,
        );
        return;
      }
      // 403 practice_hint_in_flight＝原請求還在 server 跑（latch 占用中），
      // 不是明確拒絕：rotate 會把 id 從記憶體＋store 清掉，等原請求以舊 id
      // 寫入已扣費快照後，新 id 重試＝replay miss＝重新生成＝重複扣費。
      // 比照 429：id 保留，稍候重試沿用同 id 吃 server replay 去重。
      if (e.message == 'practice_hint_in_flight') {
        if (_dropStaleHint(generation)) return;
        state = state.copyWith(
          isHintLoading: false,
          errorMessage: _hintApiErrorMessage(e.message),
        );
        return;
      }
      _rotateHintRequestId(requestId); // 4xx 明確拒絕 → rotate
      if (_dropStaleHint(generation)) return;
      state = state.copyWith(
        isHintLoading: false,
        errorMessage: _hintApiErrorMessage(e.message),
      );
    } on PracticeGenerationFailedException catch (e) {
      // 5xx／格式壞掉：id 保留，重試沿用（server 可靠 ledger 去重）。
      if (_dropStaleHint(generation)) return;
      state = state.copyWith(
        isHintLoading: false,
        errorMessage: _hintGenerationErrorMessage(e.message),
      );
    } on TimeoutException {
      // client 逾時：不 rotate requestId，重試沿用同 id——server 若已完成
      // 會 replay 同一份結果，不會重複扣額度。
      if (_dropStaleHint(generation)) return;
      state = state.copyWith(
        isHintLoading: false,
        errorMessage: '提示等太久沒回應，請再試一次（不會重複扣額度）。',
      );
    } catch (_) {
      // 網路失敗：id 保留，重試沿用。
      if (_dropStaleHint(generation)) return;
      state = state.copyWith(
        isHintLoading: false,
        errorMessage: '提示暫時產生失敗，等一下再試。',
      );
    }
  }

  Future<void> endPractice() async {
    if (!state.canDebrief || _activeSendPipelineToken != null) return;
    final requestState = state;
    final requestSessionId = requestState.sessionId;
    final requestProfile = _profileDto();
    final requestTurns = _turnDtosForPrompt(requestState.messages);
    final requestMemorySummary = _memorySummaryForPrompt(requestState.messages);
    final requestPartnerState = _lastPartnerStateForPrompt(
      requestState.messages,
    );
    final requestAppliedHints = requestState.isAssistedLearningMode
        ? List<PracticeAppliedHintTurnDto>.unmodifiable(_appliedHintTurns)
        : const <PracticeAppliedHintTurnDto>[];
    final generation = ++_debriefGeneration;
    state = state.copyWith(
      isDebriefing: true,
      ended: true,
      debriefFailed: false,
      debriefRetryable: true,
      errorMessage: null,
      quotaExceeded: false,
      upgradeRequired: false,
    );
    try {
      final debrief = await _api.requestDebrief(
        sessionId: requestSessionId,
        profile: requestProfile,
        turns: requestTurns,
        practiceMode: requestState.learningMode,
        memorySummary: requestMemorySummary,
        continuationPartnerState: requestPartnerState,
        roundIndex: requestState.roundIndex,
        visiblePracticeThreadId: requestState.visiblePracticeThreadId,
        appliedHintTurns: requestAppliedHints,
      );
      if (_isStaleDebrief(generation, requestSessionId)) return;
      state = state.copyWith(
        isDebriefing: false,
        sessionComplete: true,
        debrief: debrief,
      );
      final completedState = state;
      await _persist();
      final debriefRequestId = debrief.idempotencyRequestId;
      if (debriefRequestId != null) {
        // Retire the transport replay key only after the card is durable. If
        // the app dies before this point, restart retry still replays the same
        // server result instead of consuming another debrief slot.
        await _api.confirmDebriefPersisted(
          sessionId: requestSessionId,
          requestId: debriefRequestId,
        );
      }
      final girl = completedState.girl;
      if (girl != null) {
        await _recordPracticeHistoryEvent(completedState, girl.profileId);
      }
    } on PracticeQuotaExceededException catch (e) {
      if (_isStaleDebrief(generation, requestSessionId)) return;
      state = state.copyWith(
        isDebriefing: false,
        ended: true,
        debriefFailed: true,
        debriefRetryable: true,
        quotaExceeded: true,
        errorMessage: e.message,
      );
    } on PracticeUpgradeRequiredException {
      if (_isStaleDebrief(generation, requestSessionId)) return;
      state = state.copyWith(
        isDebriefing: false,
        ended: true,
        debriefFailed: true,
        debriefRetryable: true,
        upgradeRequired: true,
        errorMessage: '這個拆解會消耗訊息額度，升級後就能繼續使用。',
      );
    } on PracticeModeLockedException {
      if (_isStaleDebrief(generation, requestSessionId)) return;
      state = state.copyWith(
        isDebriefing: false,
        ended: true,
        debriefFailed: true,
        debriefRetryable: true,
        errorMessage: _practiceModeLockedMessage,
      );
    } on PracticeApiException catch (e) {
      if (_isStaleDebrief(generation, requestSessionId)) return;
      final debriefLimitReached = e.message == 'practice_debrief_limit';
      state = state.copyWith(
        isDebriefing: false,
        ended: true,
        sessionComplete: debriefLimitReached ? true : state.sessionComplete,
        debriefFailed: true,
        debriefRetryable: !debriefLimitReached,
        errorMessage: debriefLimitReached
            ? '這場練習的拆解次數已用完。'
            : e.status == 429
                ? e.message
                : _debriefApiErrorMessage(e.message),
      );
    } on PracticeGenerationFailedException catch (e) {
      if (_isStaleDebrief(generation, requestSessionId)) return;
      state = state.copyWith(
        isDebriefing: false,
        ended: true,
        debriefFailed: true,
        debriefRetryable: true,
        errorMessage: _debriefGenerationErrorMessage(e.message),
      );
    } catch (_) {
      if (_isStaleDebrief(generation, requestSessionId)) return;
      state = state.copyWith(
        isDebriefing: false,
        ended: true,
        debriefFailed: true,
        debriefRetryable: true,
        errorMessage: '網路不穩，拆解卡生成失敗，可以再按一次。',
      );
    }
  }

  void clearError() {
    state = state.copyWith(
      errorMessage: null,
      quotaExceeded: false,
      upgradeRequired: false,
      drawUpgradeRequired: false,
      drawQuotaExceeded: false,
    );
  }

  /// 開場前調整難度偏好：只換難度、保留目前這位對象（兩個控制各自獨立）。
  /// 送出第一則後鎖定（messages 非空即 no-op）；尚未翻牌（girl null）亦 no-op。
  /// 若目前是「翻好但未送出」的 draft 狀態，同步把難度寫回 draft。
  void setDifficultyPreference(PracticeDifficultyPreference preference) {
    if (!state.isRevealed || state.messages.isNotEmpty || state.girl == null) {
      return;
    }
    final resolved = _stateProfile().withDifficulty(preference);
    state = state.copyWith(
      difficultyPreference: preference,
      difficulty: resolved.difficulty,
      difficultyLabel: resolved.difficultyLabel,
    );
    final nextReset = state.drawNextResetAt;
    if (nextReset != null) {
      _saveDraftFromState(nextReset); // 草稿難度同步（pre-message）
    }
  }

  /// 本場送往 Edge 的對象 metadata：只送 allowlisted id（含 catalog-profile 身份）。
  List<PracticeTurnDto> _turnDtosForPrompt(List<PracticeMessage> messages) {
    final start = messages.length > kPracticePromptRecentTurns
        ? messages.length - kPracticePromptRecentTurns
        : 0;
    return messages
        .skip(start)
        .map((m) => PracticeTurnDto(role: m.role, text: m.text))
        .toList();
  }

  PracticePartnerState? _lastPartnerStateForPrompt(
    List<PracticeMessage> messages,
  ) {
    for (final message in messages.reversed) {
      if (message.role != 'ai') continue;
      final mood = message.mood?.trim();
      if (mood == null || !_practicePartnerMoodValues.contains(mood)) {
        return null;
      }
      final innerThought = (message.innerThought ?? '')
          .replaceAll(
              _practiceRawImageFilenamePattern, '[image concept omitted]')
          .trim()
          .replaceAll(RegExp(r'\s+'), ' ');
      return PracticePartnerState(
        mood: mood,
        innerThought: _clipMemoryText(innerThought, 80),
      );
    }
    return null;
  }

  String? _memorySummaryForPrompt(List<PracticeMessage> messages) {
    final olderCount = messages.length - kPracticePromptRecentTurns;
    if (olderCount <= 0) return null;
    final olderMessages = messages.take(olderCount).toList(growable: false);
    final buffer = StringBuffer('更早對話摘要（自動節錄 $olderCount 則）：');
    for (final message in _memorySummarySample(olderMessages)) {
      final text = _compactMemoryText(message.text);
      if (text.isEmpty) continue;
      final speaker = message.role == 'user' ? '你' : '她';
      buffer.write('$speaker：${_clipMemoryText(text, 48)}；');
      if (buffer.length >= kPracticeMemorySummaryMaxChars) break;
    }
    final summary = _clipMemoryText(
      buffer.toString(),
      kPracticeMemorySummaryMaxChars,
    );
    return summary.trim().isEmpty ? null : summary;
  }

  Iterable<PracticeMessage> _memorySummarySample(
    List<PracticeMessage> olderMessages,
  ) {
    if (olderMessages.length <= 24) return olderMessages;
    return [
      ...olderMessages.take(8),
      ...olderMessages.skip(olderMessages.length - 16),
    ];
  }

  String _compactMemoryText(String text) => text
      .replaceAll(_practiceRawImageFilenamePattern, '[image concept omitted]')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');

  String _clipMemoryText(String text, int maxChars) {
    if (text.length <= maxChars) return text;
    if (maxChars <= 3) return text.substring(0, maxChars);
    return '${text.substring(0, maxChars - 3)}...';
  }

  PracticeProfileDto _profileDto() {
    final girl = state.girl!;
    return PracticeProfileDto(
      personaId: state.personaId,
      difficulty: state.difficulty,
      profileId: girl.profileId,
      nameId: girl.nameId,
      professionId: girl.professionId,
      photoId: girl.photoId,
    );
  }

  /// 把目前「翻好但未送出第一則」的狀態寫成 draft（不寫進 recent sessions）。
  Future<void> _saveDraftFromState(String nextResetAtIso) async {
    final s = state;
    final girl = s.girl;
    if (girl == null) return;
    final nextReset = DateTime.tryParse(nextResetAtIso);
    if (nextReset == null) return;
    await _draftStore.save(PracticeDrawDraft(
      sessionId: s.sessionId,
      visiblePracticeThreadId: s.visiblePracticeThreadId ?? s.sessionId,
      roundIndex: s.roundIndex,
      profileId: girl.profileId,
      personaId: s.personaId,
      difficulty: s.difficulty,
      difficultyPreference: s.difficultyPreference,
      freeAllowance: s.drawFreeAllowance ?? 0,
      freeUsed: s.drawFreeUsed ?? 0,
      freeRemaining: s.drawFreeRemaining ?? 0,
      extraCostMessages: s.drawExtraCost ?? 0,
      learningMode: s.learningMode,
      temperatureScore: s.isAssistedLearningMode ? s.temperatureScore : null,
      familiarityScore: s.isAssistedLearningMode ? s.familiarityScore : null,
      relationshipStageLabel:
          s.isAssistedLearningMode ? s.relationshipStageLabel : null,
      nextResetAt: nextReset,
      createdAt: s.createdAt,
    ));
  }

  Future<void> _persist() async {
    final s = state;
    final girl = s.girl;
    if (girl == null) return; // 防呆：未翻牌不持久化
    await _repo.save(PracticeSession(
      id: s.sessionId,
      createdAt: s.createdAt,
      messages: s.messages,
      aiReplyCount: s.aiReplyCount,
      debriefSummary: s.debrief?.summary,
      debriefStrengths: s.debrief?.strengths ?? const [],
      debriefWatchouts: s.debrief?.watchouts ?? const [],
      debriefSuggestedLine: s.debrief?.suggestedLine,
      debriefVibe: s.debrief?.vibe,
      debriefDateChance: s.debrief?.dateChance,
      debriefDateChanceReason: s.debrief?.dateChanceReason,
      debriefNextInviteMove: s.debrief?.nextInviteMove,
      debriefGamePhaseReached: s.debrief?.gameBreakdown?.phaseReached,
      debriefGameMissedVariable: s.debrief?.gameBreakdown?.missedVariable,
      debriefGameFailureState: s.debrief?.gameBreakdown?.failureState,
      debriefGameNextFirstLine: s.debrief?.gameBreakdown?.nextFirstLine,
      debriefGameInviteDirection: s.debrief?.gameBreakdown?.inviteDirection,
      personaId: s.personaId,
      personaLabel: s.personaLabel,
      difficulty: s.difficulty,
      difficultyLabel: s.difficultyLabel,
      visiblePracticeThreadId: s.visiblePracticeThreadId,
      roundIndex: s.roundIndex,
      profileId: girl.profileId,
      practiceMode: s.learningMode.wireName,
      temperatureScore: s.isAssistedLearningMode ? s.temperatureScore : null,
      familiarityScore: s.isAssistedLearningMode ? s.familiarityScore : null,
      relationshipStageLabel:
          s.isAssistedLearningMode ? s.relationshipStageLabel : null,
      hintUsedCount: s.isAssistedLearningMode ? s.hintUsedCount : null,
    ));
  }

  /// 案2：練習溫度歷史事件（best-effort：失敗只 debugPrint 絕不 rethrow，
  /// 收操流程完全不受影響）。只掛 endPractice 的 debrief 成功路徑——
  /// 每局收操記一筆終溫；局中 _persist（送訊息/hint）絕不寫，避免同局多筆。
  /// 只在輔助模式且 temperatureScore 有值時寫——
  /// 標準模式三元組全 null，是畫不出來的空點（設計拍板）。
  Future<void> _recordPracticeHistoryEvent(
    PracticeChatState s,
    String profileId,
  ) async {
    final history = _historyRepository;
    if (history == null) return;
    final temperature = s.isAssistedLearningMode ? s.temperatureScore : null;
    if (temperature == null) return;
    try {
      await history.append(AnalysisHistoryEvent.practice(
        id: const Uuid().v4(),
        createdAt: DateTime.now(),
        profileId: profileId,
        roundIndex: s.roundIndex,
        temperatureScore: temperature,
        familiarityScore: s.isAssistedLearningMode ? s.familiarityScore : null,
        relationshipStageLabel:
            s.isAssistedLearningMode ? s.relationshipStageLabel : null,
      ));
    } catch (e) {
      debugPrint('AnalysisHistory practice append failed: $e');
    }
  }
}

const _hintGenericErrorMessage = '提示暫時產生失敗，等一下再試。';
const _hintStaleConversationMessage = '對話進度已往前，請先送出一則訊息同步，再取提示。';
const _debriefGenericErrorMessage = '拆解卡生成失敗，可以再按一次。';
const _debriefServiceUnavailableMessage = '拆解服務暫時無法使用，請稍後再試。';

/// 409 practice_mode_locked 共用文案（chat / hint 兩路徑同文案）。
const _practiceModeLockedMessage = '這位陪練女孩這一輪已用另一種模式進行中，請切回原本的模式繼續';

String _hintApiErrorMessage(String code) {
  switch (code) {
    case 'practice_hint_in_flight':
      return '提示正在產生中，等一下再試。';
    case 'invalid_hint_no_ai_turns':
    case 'invalid_hint_last_turn_must_be_ai':
    case 'practice_session_not_started':
      return '要等對方回覆後，才能請 Hint。';
    case 'practice_hint_beginner_only':
    case 'practice_mode_locked':
      return '這場不是新手模式，下一場切到新手模式再用 Hint。';
    case 'practice_hint_not_ready':
      return '提示服務正在更新中，請稍後再試。';
    default:
      return _hintGenericErrorMessage;
  }
}

String _hintGenerationErrorMessage(String code) {
  switch (code) {
    case 'practice_hint_not_ready':
      return '提示服務正在更新中，請稍後再試。';
    default:
      return _hintGenericErrorMessage;
  }
}

String _debriefApiErrorMessage(String code) {
  switch (code) {
    case 'practice_debrief_in_flight':
      return '拆解還在完成中，請稍等幾秒再試。';
    case 'practice_session_not_started':
      return _debriefGenericErrorMessage;
    default:
      return _debriefGenericErrorMessage;
  }
}

String _debriefGenerationErrorMessage(String code) {
  switch (code) {
    case 'practice_learning_not_ready':
    case 'config_missing':
      return _debriefServiceUnavailableMessage;
    default:
      return _debriefGenericErrorMessage;
  }
}

// ── providers ────────────────────────────────────────────────────────

final practiceChatApiServiceProvider = Provider<PracticeChatApiService>((ref) {
  return PracticeChatApiService(
    pendingDebriefStore: ref.read(practicePendingDebriefStoreProvider),
  );
});

final practiceSessionRepositoryProvider =
    Provider<PracticeSessionRepository>((ref) {
  return PracticeSessionRepository(StorageService.practiceSessionsBox);
});

/// 翻牌草稿本地存取（JSON 存進加密 settings box，不新增 Hive typeId）。
final practiceDrawDraftStoreProvider = Provider<PracticeDrawDraftStore>((ref) {
  return HivePracticeDrawDraftStore(StorageService.settingsBox);
});

/// 在途 hint requestId 本地存取（JSON 存進加密 settings box）。controller 是
/// autoDispose，靠它讓失敗未 rotate 的 requestId 活過重建，server 才能 replay
/// 已扣費的結果不雙扣。
final practicePendingHintStoreProvider =
    Provider<PracticePendingHintStore>((ref) {
  // box getter 延遲取用：box 沒開的環境（headless／widget 測試）只退化成
  // 不持久化，不在 provider 建構期丟例外。
  return HivePracticePendingHintStore(() => StorageService.settingsBox);
});

/// 在途 debrief requestId 本地存取；只保存 payload SHA-256 digest，不保存逐字稿。
/// 讓 response 遺失後的 retry 即使跨 App 重啟也能吃 server replay，不重複計次。
final practicePendingDebriefStoreProvider =
    Provider<PracticePendingDebriefStore>((ref) {
  return HivePracticePendingDebriefStore(() => StorageService.settingsBox);
});

/// 在途翻牌 requestId 本地存取（JSON 存進加密 settings box）。讓翻牌失敗
/// 未 rotate 的 requestId 活過 autoDispose 重建，server 才能 replay 已入帳
/// 的抽卡結果不雙扣。
final practicePendingDrawStoreProvider =
    Provider<PracticePendingDrawStore>((ref) {
  return HivePracticePendingDrawStore(() => StorageService.settingsBox);
});

/// 角色圖鑑解鎖記錄本地存取（JSON list 存進加密 settings box）。
final practiceCollectionStoreProvider =
    Provider<PracticeCollectionStore>((ref) {
  return HivePracticeCollectionStore(StorageService.settingsBox);
});

/// 已解鎖 profileId 集合（角色圖鑑）。app 存活期間常駐；翻牌成功／還原
/// 舊場即時 +1，收藏頁與 learning 入口 chip 都 watch 它。
class PracticeCollectionNotifier extends StateNotifier<Set<String>> {
  PracticeCollectionNotifier(this._store) : super(_store.load());

  final PracticeCollectionStore _store;

  Future<void> add(String profileId) async {
    if (profileId.isEmpty || state.contains(profileId)) return;
    state = {...state, profileId};
    await _store.add(profileId);
  }
}

final practiceCollectionProvider =
    StateNotifierProvider<PracticeCollectionNotifier, Set<String>>((ref) {
  return PracticeCollectionNotifier(ref.read(practiceCollectionStoreProvider));
});

/// 已解鎖數（只數 catalog 內成員，避免髒資料把 N 撐超過 catalog 長度）。
final unlockedPracticeGirlCountProvider = Provider<int>((ref) {
  final unlocked = ref.watch(practiceCollectionProvider);
  return practiceGirlProfiles
      .where((p) => unlocked.contains(p.profileId))
      .length;
});

/// autoDispose：離開畫面即重置，下次進來是全新一場練習。
final practiceChatControllerProvider = StateNotifierProvider.autoDispose<
    PracticeChatController, PracticeChatState>((ref) {
  final repository = ref.read(practiceSessionRepositoryProvider);
  // 案2：歷史事件 repository 是 best-effort side-channel——拿不到（如 Hive box
  // 未開）絕不擋 controller 建構，練習主流程完全不受影響。
  AnalysisHistoryRepository? historyRepository;
  try {
    historyRepository = ref.read(analysisHistoryRepositoryProvider);
  } catch (e) {
    debugPrint('AnalysisHistory repository unavailable: $e');
  }
  return PracticeChatController(
    api: ref.read(practiceChatApiServiceProvider),
    repository: repository,
    draftStore: ref.read(practiceDrawDraftStoreProvider),
    pendingHintStore: ref.read(practicePendingHintStoreProvider),
    pendingDrawStore: ref.read(practicePendingDrawStoreProvider),
    initialSession: _latestOpenPracticeSession(repository.recentSessions()),
    onUsageSynced: ({required monthlyRemaining, required dailyRemaining}) {
      ref.read(subscriptionProvider.notifier).syncUsageFromServer(
            monthlyRemaining: monthlyRemaining,
            dailyRemaining: dailyRemaining,
          );
    },
    onProfileUnlocked: (profileId) {
      ref.read(practiceCollectionProvider.notifier).add(profileId);
    },
    historyRepository: historyRepository,
  );
});

/// 最近 5 場練習（read-only 歷史）。
final recentPracticeSessionsProvider =
    Provider.autoDispose<List<PracticeSession>>((ref) {
  return ref.read(practiceSessionRepositoryProvider).recentSessions();
});

PracticeSession? _latestOpenPracticeSession(List<PracticeSession> sessions) {
  for (final session in sessions) {
    if (!session.hasDebrief && session.messages.isNotEmpty) {
      return session;
    }
  }
  return null;
}
