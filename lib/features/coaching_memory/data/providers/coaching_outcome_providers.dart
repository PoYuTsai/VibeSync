import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/storage_service.dart';
import '../../../coach_chat/domain/entities/coach_chat_result.dart';
import '../../domain/entities/coaching_outcome_digest.dart';
import '../../domain/entities/coaching_outcome_event.dart';
import '../../domain/repositories/coaching_outcome_repository.dart';
import '../repositories/coaching_outcome_repository_impl.dart';

final coachingOutcomeRepositoryProvider =
    Provider<CoachingOutcomeRepository>((ref) {
  return CoachingOutcomeRepositoryImpl(StorageService.coachingOutcomeEventsBox);
});

final coachingOutcomeNowProvider = Provider<DateTime Function()>((ref) {
  return DateTime.now;
});

final coachingOutcomeEventProvider =
    Provider.family<CoachingOutcomeEvent?, String>((ref, eventId) {
  final repo = ref.watch(coachingOutcomeRepositoryProvider);
  return repo.get(eventId);
});

final coachingOutcomesByPartnerProvider =
    Provider.family<List<CoachingOutcomeEvent>, String>((ref, partnerId) {
  final repo = ref.watch(coachingOutcomeRepositoryProvider);
  return repo.listByPartner(partnerId);
});

final coachingUnboundOutcomesProvider =
    Provider<List<CoachingOutcomeEvent>>((ref) {
  final repo = ref.watch(coachingOutcomeRepositoryProvider);
  return repo.listUnbound();
});

final coachingOutcomeDigestProvider =
    Provider.family<CoachingOutcomeDigest, String>((ref, partnerId) {
  final events = ref.watch(coachingOutcomesByPartnerProvider(partnerId));
  return CoachingOutcomeDigest.fromEvents(
    partnerId: partnerId,
    events: events,
  );
});

final coachingUnboundOutcomeDigestProvider =
    Provider<CoachingOutcomeDigest>((ref) {
  final events = ref.watch(coachingUnboundOutcomesProvider);
  return CoachingOutcomeDigest.fromEvents(
    partnerId: null,
    events: events,
  );
});

final coachingOutcomeRecorderProvider =
    Provider<CoachingOutcomeRecorder>((ref) {
  return CoachingOutcomeRecorder(ref);
});

String coachingOutcomeIdForCoachResult(String resultId) =>
    'coach:${resultId.trim()}';

/// 兩段式規則單點：send 類→pending（等第二段）、未送類→unknown（終態）。
CoachingOutcomeSignal coachingOutcomeForUserAction(CoachingUserAction action) {
  return action == CoachingUserAction.sentAsIs ||
          action == CoachingUserAction.editedAndSent
      ? CoachingOutcomeSignal.pending
      : CoachingOutcomeSignal.unknown;
}

/// 一則建議在 outcome 帳本裡的身分。opener/analyze 的 [eventId] 直接用
/// adviceId（一 advice 一 event）；coach 沿用 `coach:<resultId>`。
class CoachingAdviceContext {
  const CoachingAdviceContext({
    required this.eventId,
    this.partnerId,
    this.conversationId,
    required this.source,
    this.adviceId,
    this.adviceType,
    required this.suggestedMoveSummary,
  });

  final String eventId;
  final String? partnerId;
  final String? conversationId;
  final CoachingOutcomeSource source;
  final String? adviceId;
  final String? adviceType;
  final String suggestedMoveSummary;
}

class CoachingOutcomeRecorder {
  CoachingOutcomeRecorder(this._ref);

  final Ref _ref;

  /// 複製即自動記 pending。冪等：該 eventId 已有事件（不管狀態）→ no-op
  /// 回 null，絕不覆蓋使用者已作答內容。
  Future<CoachingOutcomeEvent?> recordAdviceCopied(
    CoachingAdviceContext advice,
  ) async {
    final repo = _ref.read(coachingOutcomeRepositoryProvider);
    if (repo.get(advice.eventId) != null) return null;
    final now = _ref.read(coachingOutcomeNowProvider);
    final event = CoachingOutcomeEvent.create(
      id: advice.eventId,
      partnerId: advice.partnerId,
      conversationId: advice.conversationId,
      source: advice.source,
      adviceId: advice.adviceId,
      adviceType: advice.adviceType,
      suggestedMoveSummary: clampSuggestedMoveSummary(
        advice.suggestedMoveSummary,
      ),
      userAction: CoachingUserAction.sentAsIs,
      outcome: CoachingOutcomeSignal.pending,
      createdAt: now(),
    );
    await repo.put(event);
    _invalidateFor(event);
    return event;
  }

  /// 第一段回報。同值重按→no-op 回既有事件（不洗第二段、不刷 createdAt）；
  /// 改選不同值→保留 preview/note、換 userAction、outcome 用呼叫端依
  /// [coachingOutcomeForUserAction] 算好的值（第二段答案刻意洗回）。
  Future<CoachingOutcomeEvent> recordAdviceUserAction({
    required CoachingAdviceContext advice,
    required CoachingUserAction userAction,
    required CoachingOutcomeSignal outcome,
  }) async {
    final repo = _ref.read(coachingOutcomeRepositoryProvider);
    final now = _ref.read(coachingOutcomeNowProvider);
    final existing = repo.get(advice.eventId);
    if (existing != null && existing.userAction == userAction) {
      return existing;
    }
    final event = existing == null
        ? CoachingOutcomeEvent.create(
            id: advice.eventId,
            partnerId: advice.partnerId,
            conversationId: advice.conversationId,
            source: advice.source,
            adviceId: advice.adviceId,
            adviceType: advice.adviceType,
            suggestedMoveSummary: clampSuggestedMoveSummary(
              advice.suggestedMoveSummary,
            ),
            userAction: userAction,
            outcome: outcome,
            createdAt: now(),
          )
        : CoachingOutcomeEvent(
            id: existing.id,
            partnerId: existing.partnerId,
            conversationId: existing.conversationId,
            source: existing.source,
            adviceId: existing.adviceId,
            adviceType: existing.adviceType,
            suggestedMoveSummary: existing.suggestedMoveSummary,
            userAction: userAction,
            outcome: outcome,
            outcomeTextPreview: existing.outcomeTextPreview,
            userNote: existing.userNote,
            createdAt: now(),
          );
    await repo.put(event);
    _invalidateFor(event);
    return event;
  }

  /// 第二段回報：只更新 outcome。沒有第一段紀錄、或第一段是未送類→回 null
  /// 不寫入；同值重按→no-op 回既有事件（不刷 createdAt）。
  Future<CoachingOutcomeEvent?> recordAdviceReaction({
    required String eventId,
    required CoachingOutcomeSignal outcome,
  }) async {
    final repo = _ref.read(coachingOutcomeRepositoryProvider);
    final now = _ref.read(coachingOutcomeNowProvider);
    final existing = repo.get(eventId);
    final action = existing?.userAction;
    if (existing == null ||
        (action != CoachingUserAction.sentAsIs &&
            action != CoachingUserAction.editedAndSent)) {
      return null;
    }
    if (existing.outcome == outcome) return existing;
    final updated = CoachingOutcomeEvent(
      id: existing.id,
      partnerId: existing.partnerId,
      conversationId: existing.conversationId,
      source: existing.source,
      adviceId: existing.adviceId,
      adviceType: existing.adviceType,
      suggestedMoveSummary: existing.suggestedMoveSummary,
      userAction: existing.userAction,
      outcome: outcome,
      outcomeTextPreview: existing.outcomeTextPreview,
      userNote: existing.userNote,
      createdAt: now(),
    );
    await repo.put(updated);
    _invalidateFor(updated);
    return updated;
  }

  Future<CoachingOutcomeEvent> recordCoachResultOutcome({
    required CoachChatResult result,
    required CoachingUserAction userAction,
    required CoachingOutcomeSignal outcome,
  }) {
    return recordAdviceUserAction(
      advice: _coachAdviceContext(result),
      userAction: userAction,
      outcome: outcome,
    );
  }

  /// 第二段回報：只更新 outcome，保留第一段的 userAction 與其他欄位。
  ///
  /// 只在第一段回報為 sentAsIs / editedAndSent（有發出）時才合法；
  /// 沒有第一段紀錄或第一段是 didNotSend / askedCoach 時回傳 null 不寫入。
  Future<CoachingOutcomeEvent?> recordCoachResultReaction({
    required CoachChatResult result,
    required CoachingOutcomeSignal outcome,
  }) {
    return recordAdviceReaction(
      eventId: coachingOutcomeIdForCoachResult(result.id),
      outcome: outcome,
    );
  }

  CoachingAdviceContext _coachAdviceContext(CoachChatResult result) {
    return CoachingAdviceContext(
      eventId: coachingOutcomeIdForCoachResult(result.id),
      partnerId: result.partnerId,
      conversationId: result.conversationId,
      source: CoachingOutcomeSource.coach,
      adviceId: result.id,
      adviceType: result.mode,
      suggestedMoveSummary: _coachMoveSummary(result),
    );
  }

  void _invalidateFor(CoachingOutcomeEvent event) {
    _ref.invalidate(coachingOutcomeEventProvider(event.id));
    final partnerId = CoachingOutcomeEvent.normalizeScope(event.partnerId);
    if (partnerId != null) {
      _ref.invalidate(coachingOutcomesByPartnerProvider(partnerId));
      _ref.invalidate(coachingOutcomeDigestProvider(partnerId));
    } else {
      _ref.invalidate(coachingUnboundOutcomesProvider);
      _ref.invalidate(coachingUnboundOutcomeDigestProvider);
    }
  }

  /// 複製文/卡片內容進 summary 前先裁 160（entity create 超長會 throw）。
  static String clampSuggestedMoveSummary(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '建議內容';
    if (trimmed.length <= CoachingOutcomeEvent.maxSuggestedMoveSummaryLength) {
      return trimmed;
    }
    return trimmed
        .substring(0, CoachingOutcomeEvent.maxSuggestedMoveSummaryLength)
        .trimRight();
  }

  String _coachMoveSummary(CoachChatResult result) {
    final raw = [
      result.nextStep,
      if (result.suggestedLine != null) result.suggestedLine!,
    ].map((part) => part.trim()).where((part) => part.isNotEmpty).join(' / ');
    if (raw.isEmpty) return result.headline.trim();
    if (raw.length <= CoachingOutcomeEvent.maxSuggestedMoveSummaryLength) {
      return raw;
    }
    return raw
        .substring(0, CoachingOutcomeEvent.maxSuggestedMoveSummaryLength)
        .trimRight();
  }
}
