import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/services/storage_service.dart';
import '../../../subscription/data/providers/subscription_providers.dart';
import '../../domain/entities/practice_draw_draft.dart';
import '../../domain/entities/practice_message.dart';
import '../../domain/entities/practice_profile.dart';
import '../../domain/entities/practice_session.dart';
import '../repositories/practice_draw_draft_store.dart';
import '../repositories/practice_session_repository.dart';
import '../services/practice_chat_api_service.dart';

/// 一場練習最多 20 則 AI 回覆（與伺服器 MAX_AI_REPLIES 同步）。
const int kMaxPracticeAiReplies = 20;

/// 同一位對象最多 3 輪（與伺服器 MAX_PRACTICE_ROUNDS 同步）；到頂不再顯示續玩。
const int kMaxPracticeRounds = 3;

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
  final bool debriefFailed; // 拆解失敗但仍可重試／完成，不回到普通輸入列
  final String? errorMessage;
  final bool quotaExceeded;
  final bool upgradeRequired; // Free 續同一位被擋（402）：導向付費牆，與額度用罄分開
  final String? restoreText; // 失敗時把使用者剛打的字還回輸入列

  // ── 每日翻牌：揭曉狀態與免費額度狀態 ──
  /// 翻牌揭曉狀態。locked / drawing 時 [girl] 為 null，畫面不得顯示任何對象。
  final PracticeDrawStatus drawStatus;

  /// 本場對象（60-profile）：display-only 身份；尚未翻牌（locked/drawing）時為 null。
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
    this.errorMessage,
    this.quotaExceeded = false,
    this.upgradeRequired = false,
    this.restoreText,
    this.roundIndex = 1,
    this.visiblePracticeThreadId,
  });

  bool get isRevealed => drawStatus == PracticeDrawStatus.revealed;
  bool get isDrawing => drawStatus == PracticeDrawStatus.drawing;
  bool get isLocked => drawStatus != PracticeDrawStatus.revealed;

  int get remainingReplies =>
      (kMaxPracticeAiReplies - aiReplyCount).clamp(0, kMaxPracticeAiReplies);

  /// 必須先翻好牌（revealed）才能送訊息。
  bool get canSend =>
      isRevealed && !isSending && !isDebriefing && !ended && !sessionComplete;

  /// 至少有一則 AI 回覆、尚未拆解，才能結束練習看拆解卡。
  bool get canDebrief =>
      aiReplyCount >= 1 && !isDebriefing && !isSending && debrief == null;

  PracticeChatState copyWith({
    List<PracticeMessage>? messages,
    bool? isSending,
    bool? isDebriefing,
    int? aiReplyCount,
    bool? sessionComplete,
    bool? ended,
    bool? debriefFailed,
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
    Object? debrief = _sentinel,
    Object? errorMessage = _sentinel,
    Object? restoreText = _sentinel,
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
    void Function({required int monthlyRemaining, required int dailyRemaining})?
        onUsageSynced,
    PracticeSession? initialSession,
    String? sessionId,
    DateTime? createdAt,
    DateTime? now,
  }) : this._(
          api: api,
          repository: repository,
          draftStore: draftStore ?? InMemoryPracticeDrawDraftStore(),
          onUsageSynced: onUsageSynced,
          initialSession: initialSession,
          sessionId: sessionId,
          createdAt: createdAt,
          now: now ?? DateTime.now(),
        );

  PracticeChatController._({
    required PracticeChatApiService api,
    required PracticeSessionRepository repository,
    required PracticeDrawDraftStore draftStore,
    required void Function(
            {required int monthlyRemaining, required int dailyRemaining})?
        onUsageSynced,
    required PracticeSession? initialSession,
    required String? sessionId,
    required DateTime? createdAt,
    required DateTime now,
  })  : _api = api,
        _repo = repository,
        _draftStore = draftStore,
        _onUsageSynced = onUsageSynced,
        super(_initialState(
          initialSession: initialSession,
          draft: _validDraft(draftStore, now),
          sessionId: sessionId,
          createdAt: createdAt ?? now,
        ));

  final PracticeChatApiService _api;
  final PracticeSessionRepository _repo;
  final PracticeDrawDraftStore _draftStore;
  final void Function(
      {required int monthlyRemaining,
      required int dailyRemaining})? _onUsageSynced;

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
      girl: girl,
      personaId: personaId,
      personaLabel: session.personaLabel ?? practicePersonaLabel(personaId),
      difficulty: difficulty,
      difficultyLabel:
          session.difficultyLabel ?? practiceDifficultyLabel(difficulty),
      roundIndex: session.roundIndex ?? 1,
      visiblePracticeThreadId: session.visiblePracticeThreadId ?? session.id,
    );
  }

  void resumeSession(PracticeSession session) {
    state = _stateFromSession(session);
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

    try {
      final result = await _api.drawProfile(
        requestId: const Uuid().v4(),
        currentProfileId: prior.girl?.profileId, // 換一位排除自己
        visiblePracticeThreadId: prior.visiblePracticeThreadId,
      );
      final girl = girlProfileById(result.profile.profileId) ??
          fallbackPracticeProfile().girl;
      final sessionId = const Uuid().v4();
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
        drawFreeAllowance: result.draw.freeAllowance,
        drawFreeUsed: result.draw.freeUsed,
        drawFreeRemaining: result.draw.freeRemaining,
        drawExtraCost: result.draw.extraCostMessages,
        drawNextResetAt: result.draw.nextResetAt,
      );
      await _saveDraftFromState(result.draw.nextResetAt);
      // 付費額外翻牌會扣一般 quota → 同步訂閱剩餘額度。
      if (result.draw.costMessages > 0) {
        _onUsageSynced?.call(
          monthlyRemaining: result.usage.monthlyRemaining,
          dailyRemaining: result.usage.dailyRemaining,
        );
      }
    } on PracticeDrawUpgradeRequiredException catch (e) {
      // Free 免費翻牌用完且不可付費額外：導升級。保留原狀態（不揭曉/不漂移）。
      state = prior.copyWith(
        drawUpgradeRequired: true,
        drawFreeAllowance: e.freeAllowance,
        drawExtraCost: e.extraCostMessages,
        drawNextResetAt: e.nextResetAt,
        errorMessage: '升級後每天可以翻更多陪練女孩。',
      );
    } on PracticeQuotaExceededException catch (e) {
      state = prior.copyWith(
        drawQuotaExceeded: true,
        errorMessage: e.message,
      );
    } catch (_) {
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

  Future<void> startNewPartner() => drawNewPracticeGirl();

  /// 開場前換一位（== 翻一張新牌；server 會排除目前這位）。
  Future<void> regeneratePersona() => drawNewPracticeGirl();

  /// 續玩「同一位」：開新 billing session，roundIndex+1（封頂 [kMaxPracticeRounds]），
  /// threadId 不變、訊息／角色／難度保留。不走 draw、不換對象、不消耗翻牌次數。
  ///
  /// [isPaid]：Free 續同一位需升級，只觸發付費牆、不動 transcript／不扣費。
  void continueWithSamePartner({required bool isPaid}) {
    if (!isPaid) {
      state = state.copyWith(
        upgradeRequired: true,
        debriefFailed: false,
        errorMessage: '想和同一位繼續練習，升級後就能解鎖。',
      );
      return;
    }
    if (state.roundIndex >= kMaxPracticeRounds) return;
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
    );
  }

  /// 由目前 state 組出 PracticeProfile（調難度的衍生用）。
  PracticeProfile _stateProfile() => PracticeProfile(
        girl: state.girl!,
        personaId: state.personaId,
        personaLabel: state.personaLabel,
        difficulty: state.difficulty,
        difficultyLabel: state.difficultyLabel,
      );

  /// 送出一則使用者訊息並取得 AI 回覆。樂觀顯示使用者泡泡；任何失敗都回滾。
  /// 還沒翻牌（非 revealed）一律擋下並提示先翻開今日對象。
  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    if (!state.isRevealed || state.girl == null) {
      state = state.copyWith(errorMessage: '先翻開今日的練習對象，再開始聊天。');
      return;
    }
    if (!state.canSend) return;

    final priorMessages = state.messages;
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
      restoreText: null,
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
      );
      final withAi = [
        ...optimistic,
        PracticeMessage(role: 'ai', text: reply.reply),
      ];
      state = state.copyWith(
        messages: withAi,
        isSending: false,
        aiReplyCount: reply.aiTurnCount,
        sessionComplete: reply.sessionComplete,
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
    } on PracticeUpgradeRequiredException {
      state = state.copyWith(
        messages: priorMessages,
        isSending: false,
        upgradeRequired: true,
        errorMessage: '想和同一位繼續練習，升級後就能解鎖。',
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
  Future<void> endPractice() async {
    if (!state.canDebrief) return;
    state = state.copyWith(
      isDebriefing: true,
      ended: true,
      debriefFailed: false,
      errorMessage: null,
      quotaExceeded: false,
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
    } catch (_) {
      state = state.copyWith(
        isDebriefing: false,
        ended: true,
        debriefFailed: true,
        errorMessage: '拆解卡生成失敗，可以再按一次。',
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

  /// 本場送往 Edge 的對象 metadata：只送 allowlisted id（含 60-profile 身份）。
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
    ));
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

/// autoDispose：離開畫面即重置，下次進來是全新一場練習。
final practiceChatControllerProvider = StateNotifierProvider.autoDispose<
    PracticeChatController, PracticeChatState>((ref) {
  final repository = ref.read(practiceSessionRepositoryProvider);
  return PracticeChatController(
    api: ref.read(practiceChatApiServiceProvider),
    repository: repository,
    draftStore: ref.read(practiceDrawDraftStoreProvider),
    initialSession: _latestOpenPracticeSession(repository.recentSessions()),
    onUsageSynced: ({required monthlyRemaining, required dailyRemaining}) {
      ref.read(subscriptionProvider.notifier).syncUsageFromServer(
            monthlyRemaining: monthlyRemaining,
            dailyRemaining: dailyRemaining,
          );
    },
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
