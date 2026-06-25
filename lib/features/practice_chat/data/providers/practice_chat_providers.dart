import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/services/storage_service.dart';
import '../../../subscription/data/providers/subscription_providers.dart';
import '../../domain/entities/practice_message.dart';
import '../../domain/entities/practice_profile.dart';
import '../../domain/entities/practice_session.dart';
import '../repositories/practice_session_repository.dart';
import '../services/practice_chat_api_service.dart';

/// 一場練習最多 20 則 AI 回覆（與伺服器 MAX_AI_REPLIES 同步）。
const int kMaxPracticeAiReplies = 20;

const _sentinel = Object();

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
  final String? errorMessage;
  final bool quotaExceeded;
  final bool upgradeRequired; // Free 續同一位被擋（402）：導向付費牆，與額度用罄分開
  final String? restoreText; // 失敗時把使用者剛打的字還回輸入列

  // ── 本場角色＋難度（開場前可改；送出第一則後鎖定）──
  final PracticeDifficultyPreference difficultyPreference;
  final String personaId;
  final String personaLabel;
  final String difficulty;
  final String difficultyLabel;

  const PracticeChatState({
    required this.sessionId,
    required this.createdAt,
    required this.personaId,
    required this.personaLabel,
    required this.difficulty,
    required this.difficultyLabel,
    this.difficultyPreference = PracticeDifficultyPreference.normal,
    this.messages = const [],
    this.isSending = false,
    this.isDebriefing = false,
    this.aiReplyCount = 0,
    this.sessionComplete = false,
    this.ended = false,
    this.debrief,
    this.errorMessage,
    this.quotaExceeded = false,
    this.upgradeRequired = false,
    this.restoreText,
  });

  int get remainingReplies =>
      (kMaxPracticeAiReplies - aiReplyCount).clamp(0, kMaxPracticeAiReplies);

  bool get canSend => !isSending && !isDebriefing && !ended && !sessionComplete;

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
    bool? quotaExceeded,
    bool? upgradeRequired,
    PracticeDifficultyPreference? difficultyPreference,
    String? personaId,
    String? personaLabel,
    String? difficulty,
    String? difficultyLabel,
    Object? debrief = _sentinel,
    Object? errorMessage = _sentinel,
    Object? restoreText = _sentinel,
  }) {
    return PracticeChatState(
      sessionId: sessionId,
      createdAt: createdAt,
      messages: messages ?? this.messages,
      isSending: isSending ?? this.isSending,
      isDebriefing: isDebriefing ?? this.isDebriefing,
      aiReplyCount: aiReplyCount ?? this.aiReplyCount,
      sessionComplete: sessionComplete ?? this.sessionComplete,
      ended: ended ?? this.ended,
      quotaExceeded: quotaExceeded ?? this.quotaExceeded,
      upgradeRequired: upgradeRequired ?? this.upgradeRequired,
      difficultyPreference: difficultyPreference ?? this.difficultyPreference,
      personaId: personaId ?? this.personaId,
      personaLabel: personaLabel ?? this.personaLabel,
      difficulty: difficulty ?? this.difficulty,
      difficultyLabel: difficultyLabel ?? this.difficultyLabel,
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

  /// 換角色 / 改難度時，把已解析的 profile 套進 state（開場前才會被呼叫）。
  PracticeChatState copyWithProfile(
    PracticeProfile profile, {
    PracticeDifficultyPreference? difficultyPreference,
  }) {
    return copyWith(
      difficultyPreference: difficultyPreference ?? this.difficultyPreference,
      personaId: profile.personaId,
      personaLabel: profile.personaLabel,
      difficulty: profile.difficulty,
      difficultyLabel: profile.difficultyLabel,
    );
  }
}

class PracticeChatController extends StateNotifier<PracticeChatState> {
  PracticeChatController({
    required PracticeChatApiService api,
    required PracticeSessionRepository repository,
    void Function({required int monthlyRemaining, required int dailyRemaining})?
        onUsageSynced,
    PracticeSession? initialSession,
    PracticeProfile? initialProfile,
    String? sessionId,
    DateTime? createdAt,
  })  : _api = api,
        _repo = repository,
        _onUsageSynced = onUsageSynced,
        super(_initialState(
          initialSession: initialSession,
          initialProfile: initialProfile,
          sessionId: sessionId,
          createdAt: createdAt,
        ));

  final PracticeChatApiService _api;
  final PracticeSessionRepository _repo;
  final void Function(
      {required int monthlyRemaining,
      required int dailyRemaining})? _onUsageSynced;

  /// 測試用：對外讀取目前狀態（`state` 為 protected，避免測試用已 deprecated 的 debugState）。
  @visibleForTesting
  PracticeChatState get currentState => state;

  /// 進場初始 state：續聊既有 session 用其 profile；全新一場用 [initialProfile]
  /// 或現抽一組（隨機角色 + 一般難度）。
  static PracticeChatState _initialState({
    required PracticeSession? initialSession,
    required PracticeProfile? initialProfile,
    required String? sessionId,
    required DateTime? createdAt,
  }) {
    if (initialSession != null) return _stateFromSession(initialSession);
    final profile = initialProfile ?? createPracticeProfile();
    return PracticeChatState(
      sessionId: sessionId ?? const Uuid().v4(),
      createdAt: createdAt ?? DateTime.now(),
      personaId: profile.personaId,
      personaLabel: profile.personaLabel,
      difficulty: profile.difficulty,
      difficultyLabel: profile.difficultyLabel,
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
    // 舊場（personaId == null）兜底成 slow_worker + normal，與 Edge fallback 一致。
    final fallback = fallbackPracticeProfile();
    final profile = session.personaId == null
        ? fallback
        : PracticeProfile(
            personaId: session.personaId!,
            personaLabel: session.personaLabel ?? fallback.personaLabel,
            difficulty: session.difficulty ?? 'normal',
            difficultyLabel: session.difficultyLabel ?? '一般',
          );
    return PracticeChatState(
      sessionId: session.id,
      createdAt: session.createdAt,
      messages: session.messages,
      aiReplyCount: session.aiReplyCount,
      sessionComplete:
          debrief != null || session.aiReplyCount >= kMaxPracticeAiReplies,
      ended: debrief != null,
      debrief: debrief,
      personaId: profile.personaId,
      personaLabel: profile.personaLabel,
      difficulty: profile.difficulty,
      difficultyLabel: profile.difficultyLabel,
    );
  }

  void resumeSession(PracticeSession session) {
    state = _stateFromSession(session);
  }

  /// 送出一則使用者訊息並取得 AI（模擬對象）回覆。
  /// 樂觀顯示使用者泡泡；任何失敗都回滾，不留半截、不扣額度。
  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || !state.canSend) return;

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
      restoreText: null,
    );

    try {
      final reply = await _api.sendMessage(
        sessionId: state.sessionId,
        profile: PracticeProfileDto(
          personaId: state.personaId,
          difficulty: state.difficulty,
        ),
        turns: optimistic
            .map((m) => PracticeTurnDto(role: m.role, text: m.text))
            .toList(),
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
      // Free 帳號續同一位被擋：導向付費牆，回滾樂觀泡泡並還原文字。
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
      errorMessage: null,
      quotaExceeded: false,
    );
    try {
      final debrief = await _api.requestDebrief(
        sessionId: state.sessionId,
        profile: PracticeProfileDto(
          personaId: state.personaId,
          difficulty: state.difficulty,
        ),
        turns: state.messages
            .map((m) => PracticeTurnDto(role: m.role, text: m.text))
            .toList(),
      );
      state = state.copyWith(
        isDebriefing: false,
        sessionComplete: true,
        debrief: debrief,
      );
      await _persist();
    } catch (_) {
      // 拆解失敗不鎖死：解開 ended 讓使用者可重試或繼續。
      state = state.copyWith(
        isDebriefing: false,
        ended: false,
        errorMessage: '拆解卡生成失敗，可以再按一次。',
      );
    }
  }

  void clearError() {
    state = state.copyWith(
      errorMessage: null,
      quotaExceeded: false,
      upgradeRequired: false,
    );
  }

  /// 開場前「換一位」：只重抽角色，難度維持目前已解析的值。
  /// 即使偏好是「隨機」也不重抽難度——換人與調難度兩個控制各自獨立。
  /// 送出第一則後鎖定（messages 非空即 no-op）。
  void regeneratePersona() {
    if (state.messages.isNotEmpty) return;
    final profile = createPracticeProfile();
    state = state.copyWith(
      personaId: profile.personaId,
      personaLabel: profile.personaLabel,
    );
  }

  /// 開場前調整難度偏好：只換難度、保留目前這位對象（兩個控制各自獨立）。
  /// `隨機` 會立刻解析成 easy/normal/challenge 其一。送出第一則後鎖定。
  void setDifficultyPreference(PracticeDifficultyPreference preference) {
    if (state.messages.isNotEmpty) return;
    final resolved = createPracticeProfile(difficultyPreference: preference);
    state = state.copyWith(
      difficultyPreference: preference,
      difficulty: resolved.difficulty,
      difficultyLabel: resolved.difficultyLabel,
    );
  }

  Future<void> _persist() async {
    final s = state;
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

/// autoDispose：離開畫面即重置，下次進來是全新一場練習。
final practiceChatControllerProvider = StateNotifierProvider.autoDispose<
    PracticeChatController, PracticeChatState>((ref) {
  final repository = ref.read(practiceSessionRepositoryProvider);
  return PracticeChatController(
    api: ref.read(practiceChatApiServiceProvider),
    repository: repository,
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
