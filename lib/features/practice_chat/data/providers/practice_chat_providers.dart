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
import '../../domain/entities/practice_hint.dart';
import '../../domain/entities/practice_learning_mode.dart';
import '../../domain/entities/practice_message.dart';
import '../../domain/entities/practice_profile.dart';
import '../../domain/entities/practice_session.dart';
import '../repositories/practice_collection_store.dart';
import '../repositories/practice_draw_draft_store.dart';
import '../repositories/practice_pending_draw_store.dart';
import '../repositories/practice_pending_hint_store.dart';
import '../repositories/practice_session_repository.dart';
import '../services/practice_chat_api_service.dart';

/// 一場練習最多 20 則 AI 回覆（與伺服器 MAX_AI_REPLIES 同步）。
const int kMaxPracticeAiReplies = 20;

/// 新手模式同一輪最多 5 次 Hint（與伺服器 MAX_HINTS_PER_ROUND 同步）。
const int kMaxPracticeHintsPerRound = 5;

/// 同一位對象最多 3 輪（與伺服器 MAX_PRACTICE_ROUNDS 同步）；到頂不再顯示續玩。
const int kMaxPracticeRounds = 3;

// 溫度開場 fallback 隨難度走：見 initialPracticeTemperatureScore（practice_profile.dart，
// 鏡像 server DIFFICULTY_TUNING）。
const int kInitialPracticeFamiliarityScore = 0;
const String kInitialPracticeRelationshipStageLabel = '建立熟悉中';

const _sentinel = Object();

/// 每日翻牌的揭曉狀態。locked＝今天還沒翻牌（不顯示任何對象）；drawing＝抽牌中；
/// revealed＝已有今日對象可開聊；error＝抽牌失敗（locked 情境下用，仍可重抽）。
enum PracticeDrawStatus { locked, drawing, revealed, error }

class PracticeChatState {
  final String sessionId;
  final DateTime createdAt;
  final List<PracticeMessage> messages;
  final bool isSending;
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

  // ── 續玩同一位：roundIndex 第幾輪（1..3）；threadId 跨輪穩定識別（log 用）──
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
      !isDebriefing &&
      !isHintLoading &&
      !ended &&
      !sessionComplete;

  bool get isBeginnerMode => learningMode == PracticeLearningMode.beginner;

  bool get canChangeLearningMode =>
      isRevealed && messages.isEmpty && !isSending && !isDebriefing;

  bool get canRequestHint =>
      isBeginnerMode &&
      isRevealed &&
      !hintLimitReached &&
      hintUsedCount < kMaxPracticeHintsPerRound &&
      !isHintLoading &&
      !isSending &&
      !isDebriefing &&
      !ended &&
      !sessionComplete &&
      girl != null &&
      messages.isNotEmpty &&
      messages.last.role == 'ai';

  /// 至少有一則 AI 回覆、尚未拆解，才能結束練習看拆解卡。
  bool get canDebrief =>
      aiReplyCount >= 1 &&
      !isDebriefing &&
      !isSending &&
      debrief == null &&
      (!debriefFailed || debriefRetryable);

  PracticeChatState copyWith({
    List<PracticeMessage>? messages,
    bool? isSending,
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
  })  : _api = api,
        _repo = repository,
        _draftStore = draftStore,
        _pendingHintStore = pendingHintStore,
        _pendingDrawStore = pendingDrawStore,
        _onUsageSynced = onUsageSynced,
        _onProfileUnlocked = onProfileUnlocked,
        _historyRepository = historyRepository,
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
  /// 才清空 rotate。
  String? _pendingHintRequestId;

  /// 成功或 4xx 明確拒絕 → rotate：清記憶體＋清持久化 store。5xx/timeout
  /// **不**走這裡（兩者都保留，重試與重建後沿用）。dispose 也不清——在途 id
  /// 必須活過 autoDispose 重建，server 才能 replay 不雙扣。
  /// 只在完成的 [completedId] 仍是當前 pending id 時才清：過期舊回應完成時
  /// pending 可能已被較新的 hint 覆寫，不得把新 id 連帶清掉（會失去 replay 保護）。
  void _rotateHintRequestId(String completedId) {
    if (_pendingHintRequestId == completedId) {
      _pendingHintRequestId = null;
    }
    // store 是跨 controller 共用的：autoDispose 後舊 controller 的在途請求
    // 可能晚到，這時 store 裡已是新 controller 的 id——只有 store 現值就是
    // 完成中的 id 才清，絕不誤刪別人的 replay 保護。
    final stored = _pendingHintStore.load();
    if (stored != null && stored.requestId == completedId) {
      unawaited(_pendingHintStore.clear());
    }
  }

  /// 換場（送出新訊息／續玩／換一位／還原場次）時的無條件清：在途扣費 id
  /// 只對舊場有意義。
  void _clearPendingHintRequestId() {
    _pendingHintRequestId = null;
    unawaited(_pendingHintStore.clear());
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

  /// 過期 hint 回應統一丟棄點：已扣額度認列不回滾（server 事實），只是 UI 不
  /// 顯示誤導內容；僅復位 loading 旗標。
  bool _dropStaleHint(int generation) {
    if (generation == _hintGeneration) return false;
    if (state.isHintLoading) {
      state = state.copyWith(isHintLoading: false);
    }
    return true;
  }

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
    final learningMode = draft.learningMode;
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
      temperatureScore: learningMode == PracticeLearningMode.beginner
          ? draft.temperatureScore ??
              initialPracticeTemperatureScore(draft.difficulty)
          : null,
      familiarityScore: learningMode == PracticeLearningMode.beginner
          ? draft.familiarityScore ?? kInitialPracticeFamiliarityScore
          : null,
      relationshipStageLabel: learningMode == PracticeLearningMode.beginner
          ? draft.relationshipStageLabel ??
              kInitialPracticeRelationshipStageLabel
          : null,
      hintUsedCount: 0,
    );
  }

  static PracticeChatState _stateFromSession(PracticeSession session) {
    final debrief = session.hasDebrief
        ? PracticeDebrief(
            summary: session.debriefSummary ?? '',
            strengths: session.debriefStrengths,
            watchouts: session.debriefWatchouts,
            suggestedLine: session.debriefSuggestedLine ?? '',
            vibe: session.debriefVibe ?? '中性',
          )
        : null;
    // 對象身份：依 profileId 從 catalog 解析；舊場（無 profileId）兜底預設位。
    final girl =
        girlProfileById(session.profileId) ?? fallbackPracticeProfile().girl;
    final personaId = session.personaId ?? girl.personaId;
    final difficulty = session.difficulty ?? 'normal';
    final learningMode = PracticeLearningMode.fromWire(session.practiceMode);
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
      temperatureScore: learningMode == PracticeLearningMode.beginner
          ? session.temperatureScore ??
              initialPracticeTemperatureScore(difficulty)
          : null,
      familiarityScore: learningMode == PracticeLearningMode.beginner
          ? session.familiarityScore ?? kInitialPracticeFamiliarityScore
          : null,
      relationshipStageLabel: learningMode == PracticeLearningMode.beginner
          ? session.relationshipStageLabel ??
              kInitialPracticeRelationshipStageLabel
          : null,
      hintUsedCount: learningMode == PracticeLearningMode.beginner
          ? session.hintUsedCount ?? 0
          : 0,
    );
  }

  void resumeSession(PracticeSession session) {
    _hintGeneration++; // 換場：在途 hint 全部作廢
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
    _clearPendingHintRequestId(); // 換場順手清：在途扣費 id 對舊場才有意義
    final prior = state;
    final sessionId = const Uuid().v4();
    // 難度沿用目前已解析值（比照 drawNewPracticeGirl；未解析時回偏好預設）。
    final difficulty = prior.difficulty.isNotEmpty
        ? prior.difficulty
        : practiceDifficultyId(prior.difficultyPreference);
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
      learningMode: prior.learningMode,
      temperatureScore: prior.learningMode == PracticeLearningMode.beginner
          ? initialPracticeTemperatureScore(difficulty)
          : null,
      familiarityScore: prior.learningMode == PracticeLearningMode.beginner
          ? kInitialPracticeFamiliarityScore
          : null,
      relationshipStageLabel:
          prior.learningMode == PracticeLearningMode.beginner
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
    if (state.isDrawing) return; // 防連點
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
      _clearPendingHintRequestId(); // 換場順手清：在途扣費 id 對舊場才有意義
      // 難度沿用目前已解析值（換一位不重抽難度）；locked 首抽時為預設 normal。
      final difficulty = prior.difficulty.isNotEmpty
          ? prior.difficulty
          : practiceDifficultyId(prior.difficultyPreference);

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
        learningMode: prior.learningMode,
        temperatureScore: prior.learningMode == PracticeLearningMode.beginner
            ? initialPracticeTemperatureScore(difficulty)
            : null,
        familiarityScore: prior.learningMode == PracticeLearningMode.beginner
            ? kInitialPracticeFamiliarityScore
            : null,
        relationshipStageLabel:
            prior.learningMode == PracticeLearningMode.beginner
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

  /// 續玩「同一位」：開新 billing session，roundIndex+1（封頂 [kMaxPracticeRounds]），
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
    if (state.roundIndex >= kMaxPracticeRounds) return;
    _hintGeneration++; // 開新一輪：在途 hint 全部作廢
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
      temperatureScore: state.isBeginnerMode
          ? (state.temperatureScore ??
              initialPracticeTemperatureScore(state.difficulty))
          : null,
      familiarityScore: state.isBeginnerMode
          ? (state.familiarityScore ?? kInitialPracticeFamiliarityScore)
          : null,
      relationshipStageLabel: state.isBeginnerMode
          ? (state.relationshipStageLabel ??
              kInitialPracticeRelationshipStageLabel)
          : null,
      hintUsedCount: 0,
    );
  }

  /// 由目前 state 組出 PracticeProfile（調難度的衍生用）。
  Future<void> setPracticeLearningMode(PracticeLearningMode mode) async {
    if (!state.canChangeLearningMode || state.learningMode == mode) return;
    final beginner = mode == PracticeLearningMode.beginner;
    state = state.copyWith(
      learningMode: mode,
      temperatureScore: beginner
          ? initialPracticeTemperatureScore(state.difficulty)
          : null,
      familiarityScore: beginner ? kInitialPracticeFamiliarityScore : null,
      relationshipStageLabel:
          beginner ? kInitialPracticeRelationshipStageLabel : null,
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
    if (!state.canSend) return;

    final priorMessages = state.messages;
    final learningMode = state.learningMode;
    final temperatureScore = learningMode == PracticeLearningMode.beginner
        ? state.temperatureScore ??
            initialPracticeTemperatureScore(state.difficulty)
        : null;
    final familiarityScore = learningMode == PracticeLearningMode.beginner
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

    try {
      final reply = await _api.sendMessage(
        sessionId: state.sessionId,
        profile: _profileDto(),
        turns: optimistic
            .map((m) => PracticeTurnDto(role: m.role, text: m.text))
            .toList(),
        roundIndex: state.roundIndex,
        visiblePracticeThreadId: state.visiblePracticeThreadId,
        practiceMode: learningMode,
        temperatureScore: temperatureScore,
        familiarityScore: familiarityScore,
        appliedHintType: learningMode == PracticeLearningMode.beginner
            ? appliedHintType
            : null,
        appliedHintText: learningMode == PracticeLearningMode.beginner
            ? appliedHintText
            : null,
      );
      _hintGeneration++; // 成功送出新訊息：舊 transcript 的在途 hint 已過期
      final withAi = [
        ...optimistic,
        PracticeMessage(role: 'ai', text: reply.reply),
      ];
      final temperature = reply.temperature;
      final returnedFamiliarityScore =
          temperature?.familiarityScore ?? familiarityScore;
      state = state.copyWith(
        messages: withAi,
        isSending: false,
        aiReplyCount: reply.aiTurnCount,
        sessionComplete: reply.sessionComplete,
        temperatureScore: learningMode == PracticeLearningMode.beginner
            ? temperature?.score ?? temperatureScore
            : null,
        familiarityScore: learningMode == PracticeLearningMode.beginner
            ? returnedFamiliarityScore
            : null,
        relationshipStageLabel: learningMode == PracticeLearningMode.beginner
            ? temperature?.stageLabel ?? state.relationshipStageLabel
            : null,
        lastTemperatureDelta: learningMode == PracticeLearningMode.beginner
            ? temperature?.delta
            : null,
        temperatureReason: learningMode == PracticeLearningMode.beginner
            ? temperature?.reason
            : null,
        hintUsedCount: learningMode == PracticeLearningMode.beginner
            ? reply.hintUsedCount ?? state.hintUsedCount
            : 0,
      );
      await _persist();
      // 第一則成功 → 草稿交棒給正式 session（之後靠 recentSessions 還原）。
      await _draftStore.clear();
      if (reply.costDeducted > 0 &&
          reply.monthlyRemaining != null &&
          reply.dailyRemaining != null) {
        _onUsageSynced?.call(
          monthlyRemaining: reply.monthlyRemaining!,
          dailyRemaining: reply.dailyRemaining!,
        );
      }
    } on PracticeQuotaExceededException catch (e) {
      state = state.copyWith(
        messages: priorMessages,
        isSending: false,
        quotaExceeded: true,
        errorMessage: e.message,
        restoreText: trimmed,
      );
    } on PracticeSessionCompleteException {
      state = state.copyWith(
        messages: priorMessages,
        isSending: false,
        sessionComplete: true,
        errorMessage: '這場練習已達上限，看看教練拆解吧。',
        restoreText: trimmed,
      );
    } on PracticeModeLockedException {
      // 同一輪已用另一種模式進行中：只提示切回，絕不標 sessionComplete
      // （誤標會引導「續聊同一位」開新 billing session 多扣一則）、不鎖輸入。
      state = state.copyWith(
        messages: priorMessages,
        isSending: false,
        errorMessage: _practiceModeLockedMessage,
        restoreText: trimmed,
      );
    } on PracticeUpgradeRequiredException {
      state = state.copyWith(
        messages: priorMessages,
        isSending: false,
        upgradeRequired: true,
        errorMessage: '想和同一位繼續練習，升級後就能解鎖。',
        restoreText: trimmed,
      );
    } on PracticeApiException catch (e) {
      // 429＝server per-user 模型限流：顯示 server 稍等文案、不標 quota。
      state = state.copyWith(
        messages: priorMessages,
        isSending: false,
        errorMessage: e.status == 429 ? e.message : '生成失敗了，再試一次（這次不扣額度）。',
        restoreText: trimmed,
      );
    } catch (_) {
      state = state.copyWith(
        messages: priorMessages,
        isSending: false,
        errorMessage: '生成失敗了，再試一次（這次不扣額度）。',
        restoreText: trimmed,
      );
    }
  }

  /// 結束練習，請伺服器產一張教練拆解卡（同場不另扣額度）。
  Future<void> requestHint() async {
    if (!state.canRequestHint) return;
    state = state.copyWith(
      isHintLoading: true,
      hintReplies: const [],
      hintCoaching: null,
      hintLimitReached: false,
      errorMessage: null,
      quotaExceeded: false,
      upgradeRequired: false,
    );

    // 發起時若無在途 id 才鑄新的：失敗重試沿用同一 id，server 才能去重雙扣。
    // 記憶體優先；controller 是 autoDispose，重建後記憶體 id 消失 → 讀持久化
    // store，指紋（sessionId＋當下 AI 回覆數）吻合才沿用，否則作廢鑄新 id。
    var requestId = _pendingHintRequestId;
    if (requestId == null) {
      final stored = _pendingHintStore.load();
      if (stored != null &&
          stored.sessionId == state.sessionId &&
          stored.aiCount == state.aiReplyCount) {
        requestId = stored.requestId;
      }
    }
    requestId ??= const Uuid().v4();
    _pendingHintRequestId = requestId;
    // 無論 id 來源都寫回 store（覆寫舊指紋），讓在途 id 活過重建；store 實作
    // 自身防呆，寫失敗只是退回「重建後鑄新 id」，不阻斷 hint 主流程。
    // 刻意 fire-and-forget：不得在 API 呼叫前引入新的 await 縫隙，
    // 否則世代序號（_hintGeneration）的捕捉時序會被打亂。
    unawaited(_pendingHintStore.save(PracticePendingHint(
      sessionId: state.sessionId,
      aiCount: state.aiReplyCount,
      requestId: requestId,
    )));
    // 捕捉當下世代：回應到達時序號不符＝過期回應，丟棄不填 state。
    final generation = _hintGeneration;

    try {
      final result = await _api.requestHint(
        sessionId: state.sessionId,
        requestId: requestId,
        profile: _profileDto(),
        turns: state.messages
            .map((m) => PracticeTurnDto(role: m.role, text: m.text))
            .toList(),
        roundIndex: state.roundIndex,
        visiblePracticeThreadId: state.visiblePracticeThreadId,
      );
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
    } catch (_) {
      // timeout／網路失敗：id 保留，重試沿用。
      if (_dropStaleHint(generation)) return;
      state = state.copyWith(
        isHintLoading: false,
        errorMessage: '提示暫時產生失敗，等一下再試。',
      );
    }
  }

  Future<void> endPractice() async {
    if (!state.canDebrief) return;
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
        sessionId: state.sessionId,
        profile: _profileDto(),
        turns: state.messages
            .map((m) => PracticeTurnDto(role: m.role, text: m.text))
            .toList(),
        roundIndex: state.roundIndex,
        visiblePracticeThreadId: state.visiblePracticeThreadId,
      );
      state = state.copyWith(
        isDebriefing: false,
        sessionComplete: true,
        debrief: debrief,
      );
      await _persist();
      final s = state;
      final girl = s.girl;
      if (girl != null) {
        await _recordPracticeHistoryEvent(s, girl.profileId);
      }
    } on PracticeQuotaExceededException catch (e) {
      state = state.copyWith(
        isDebriefing: false,
        ended: true,
        debriefFailed: true,
        debriefRetryable: true,
        quotaExceeded: true,
        errorMessage: e.message,
      );
    } on PracticeUpgradeRequiredException {
      state = state.copyWith(
        isDebriefing: false,
        ended: true,
        debriefFailed: true,
        debriefRetryable: true,
        upgradeRequired: true,
        errorMessage: '這個拆解會消耗訊息額度，升級後就能繼續使用。',
      );
    } on PracticeModeLockedException {
      state = state.copyWith(
        isDebriefing: false,
        ended: true,
        debriefFailed: true,
        debriefRetryable: true,
        errorMessage: _practiceModeLockedMessage,
      );
    } on PracticeApiException catch (e) {
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
      state = state.copyWith(
        isDebriefing: false,
        ended: true,
        debriefFailed: true,
        debriefRetryable: true,
        errorMessage: _debriefGenerationErrorMessage(e.message),
      );
    } catch (_) {
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
      temperatureScore: s.isBeginnerMode ? s.temperatureScore : null,
      familiarityScore: s.isBeginnerMode ? s.familiarityScore : null,
      relationshipStageLabel:
          s.isBeginnerMode ? s.relationshipStageLabel : null,
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
      personaId: s.personaId,
      personaLabel: s.personaLabel,
      difficulty: s.difficulty,
      difficultyLabel: s.difficultyLabel,
      visiblePracticeThreadId: s.visiblePracticeThreadId,
      roundIndex: s.roundIndex,
      profileId: girl.profileId,
      practiceMode: s.learningMode.wireName,
      temperatureScore: s.isBeginnerMode ? s.temperatureScore : null,
      familiarityScore: s.isBeginnerMode ? s.familiarityScore : null,
      relationshipStageLabel:
          s.isBeginnerMode ? s.relationshipStageLabel : null,
      hintUsedCount: s.isBeginnerMode ? s.hintUsedCount : null,
    ));
  }

  /// 案2：練習溫度歷史事件（best-effort：失敗只 debugPrint 絕不 rethrow，
  /// 收操流程完全不受影響）。只掛 endPractice 的 debrief 成功路徑——
  /// 每局收操記一筆終溫；局中 _persist（送訊息/hint）絕不寫，避免同局多筆。
  /// 只在新手模式且 temperatureScore 有值時寫——
  /// 非新手模式三元組全 null，是畫不出來的空點（設計拍板）。
  Future<void> _recordPracticeHistoryEvent(
    PracticeChatState s,
    String profileId,
  ) async {
    final history = _historyRepository;
    if (history == null) return;
    final temperature = s.isBeginnerMode ? s.temperatureScore : null;
    if (temperature == null) return;
    try {
      await history.append(AnalysisHistoryEvent.practice(
        id: const Uuid().v4(),
        createdAt: DateTime.now(),
        profileId: profileId,
        roundIndex: s.roundIndex,
        temperatureScore: temperature,
        familiarityScore: s.isBeginnerMode ? s.familiarityScore : null,
        relationshipStageLabel:
            s.isBeginnerMode ? s.relationshipStageLabel : null,
      ));
    } catch (e) {
      debugPrint('AnalysisHistory practice append failed: $e');
    }
  }
}

const _hintGenericErrorMessage = '提示暫時產生失敗，等一下再試。';
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
  return PracticeChatApiService();
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
