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

class CoachingOutcomeRecorder {
  CoachingOutcomeRecorder(this._ref);

  final Ref _ref;

  Future<CoachingOutcomeEvent> recordCoachResultOutcome({
    required CoachChatResult result,
    required CoachingUserAction userAction,
    required CoachingOutcomeSignal outcome,
  }) async {
    final repo = _ref.read(coachingOutcomeRepositoryProvider);
    final now = _ref.read(coachingOutcomeNowProvider);
    final event = CoachingOutcomeEvent.create(
      id: coachingOutcomeIdForCoachResult(result.id),
      partnerId: result.partnerId,
      conversationId: result.conversationId,
      source: CoachingOutcomeSource.coach,
      adviceId: result.id,
      adviceType: result.mode,
      suggestedMoveSummary: _coachMoveSummary(result),
      userAction: userAction,
      outcome: outcome,
      createdAt: now(),
    );
    await repo.put(event);
    _ref.invalidate(coachingOutcomeEventProvider(event.id));
    final partnerId = CoachingOutcomeEvent.normalizeScope(event.partnerId);
    if (partnerId != null) {
      _ref.invalidate(coachingOutcomesByPartnerProvider(partnerId));
      _ref.invalidate(coachingOutcomeDigestProvider(partnerId));
    } else {
      _ref.invalidate(coachingUnboundOutcomesProvider);
      _ref.invalidate(coachingUnboundOutcomeDigestProvider);
    }
    return event;
  }

  /// 第二段回報：只更新 outcome，保留第一段的 userAction 與其他欄位。
  ///
  /// 只在第一段回報為 sentAsIs / editedAndSent（有發出）時才合法；
  /// 沒有第一段紀錄或第一段是 didNotSend / askedCoach 時回傳 null 不寫入。
  Future<CoachingOutcomeEvent?> recordCoachResultReaction({
    required CoachChatResult result,
    required CoachingOutcomeSignal outcome,
  }) async {
    final repo = _ref.read(coachingOutcomeRepositoryProvider);
    final now = _ref.read(coachingOutcomeNowProvider);
    final id = coachingOutcomeIdForCoachResult(result.id);
    final existing = repo.get(id);
    final action = existing?.userAction;
    if (existing == null ||
        (action != CoachingUserAction.sentAsIs &&
            action != CoachingUserAction.editedAndSent)) {
      return null;
    }
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
    _ref.invalidate(coachingOutcomeEventProvider(updated.id));
    final partnerId = CoachingOutcomeEvent.normalizeScope(updated.partnerId);
    if (partnerId != null) {
      _ref.invalidate(coachingOutcomesByPartnerProvider(partnerId));
      _ref.invalidate(coachingOutcomeDigestProvider(partnerId));
    } else {
      _ref.invalidate(coachingUnboundOutcomesProvider);
      _ref.invalidate(coachingUnboundOutcomeDigestProvider);
    }
    return updated;
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
