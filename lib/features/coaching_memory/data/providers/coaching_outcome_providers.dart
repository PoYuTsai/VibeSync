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
