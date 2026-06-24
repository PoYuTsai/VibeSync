import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/services/storage_service.dart';
import '../../../subscription/data/providers/subscription_providers.dart';
import '../../domain/entities/practice_message.dart';
import '../../domain/entities/practice_session.dart';
import '../repositories/practice_session_repository.dart';
import '../services/practice_chat_api_service.dart';

/// 一場練習最多 10 則 AI 回覆（與伺服器 MAX_AI_REPLIES 同步）。
const int kMaxPracticeAiReplies = 10;

const _sentinel = Object();

class PracticeChatState {
  final String sessionId;
  final DateTime createdAt;
  final List<PracticeMessage> messages;
  final bool isSending;
  final bool isDebriefing;
  final int aiReplyCount;
  final bool sessionComplete; // 已達 10 則
  final bool ended; // 使用者已結束練習，輸入鎖定
  final PracticeDebrief? debrief;
  final String? errorMessage;
  final bool quotaExceeded;
  final String? restoreText; // 失敗時把使用者剛打的字還回輸入列

  const PracticeChatState({
    required this.sessionId,
    required this.createdAt,
    this.messages = const [],
    this.isSending = false,
    this.isDebriefing = false,
    this.aiReplyCount = 0,
    this.sessionComplete = false,
    this.ended = false,
    this.debrief,
    this.errorMessage,
    this.quotaExceeded = false,
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
    void Function({required int monthlyRemaining, required int dailyRemaining})?
        onUsageSynced,
    PracticeSession? initialSession,
    String? sessionId,
    DateTime? createdAt,
  })  : _api = api,
        _repo = repository,
        _onUsageSynced = onUsageSynced,
        super(initialSession != null
            ? _stateFromSession(initialSession)
            : PracticeChatState(
                sessionId: sessionId ?? const Uuid().v4(),
                createdAt: createdAt ?? DateTime.now(),
              ));

  final PracticeChatApiService _api;
  final PracticeSessionRepository _repo;
  final void Function(
      {required int monthlyRemaining,
      required int dailyRemaining})? _onUsageSynced;

  /// 測試用：對外讀取目前狀態（`state` 為 protected，避免測試用已 deprecated 的 debugState）。
  @visibleForTesting
  PracticeChatState get currentState => state;

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
    return PracticeChatState(
      sessionId: session.id,
      createdAt: session.createdAt,
      messages: session.messages,
      aiReplyCount: session.aiReplyCount,
      sessionComplete:
          debrief != null || session.aiReplyCount >= kMaxPracticeAiReplies,
      ended: debrief != null,
      debrief: debrief,
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
      restoreText: null,
    );

    try {
      final reply = await _api.sendMessage(
        sessionId: state.sessionId,
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
    state = state.copyWith(errorMessage: null, quotaExceeded: false);
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
