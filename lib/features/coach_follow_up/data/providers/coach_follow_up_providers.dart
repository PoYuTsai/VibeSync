// Spec 5 C20 — coach-follow-up Riverpod provider graph + AsyncNotifier
// controller.
//
// Wires the privacy-controlled C17 hint helper (only place the API hint is
// built), the C18 chip-suggestion resolver (UI nudge only — never sent), the
// C19 API service (sole HTTP wire), and the B13 repository (sole local
// persistence) into the provider graph the partner-detail UI consumes.
//
// Key contracts:
//   • coachFollowUpPartnerHintProvider is the SOLE caller of
//     buildCoachFollowUpPartnerHint — the controller never rebuilds it
//     inline.
//   • The controller is the SOLE writer to the local Hive box. UI never
//     calls repo.put / delete directly.
//   • Failed API calls leave the box untouched (no rollback needed because
//     we never write before success).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/storage_service.dart';
import '../../../analysis/domain/entities/game_stage.dart';
import '../../../conversation/domain/entities/conversation.dart';
import '../../../conversation/domain/entities/message.dart';
import '../../../partner/presentation/providers/partner_providers.dart';
import '../../../subscription/data/providers/subscription_providers.dart';
import '../../../user_profile/data/providers/data_quality_flag_provider.dart';
import '../../domain/entities/coach_follow_up_phase.dart';
import '../../domain/entities/coach_follow_up_result.dart';
import '../../domain/repositories/coach_follow_up_repository.dart';
import '../../domain/services/coach_follow_up_hint_resolver.dart';
import '../../domain/services/coach_follow_up_partner_hint_builder.dart';
import '../repositories/coach_follow_up_repository_impl.dart';
import '../services/coach_follow_up_api_service.dart';

// ── Service / repository singletons ──────────────────────────────────────

/// Hive-backed repo. Single instance; box is opened once by StorageService
/// at app startup and closed on account-clear (B14 wires `clearAll`).
final coachFollowUpRepositoryProvider =
    Provider<CoachFollowUpRepository>((ref) {
  return CoachFollowUpRepositoryImpl(StorageService.coachFollowUpResultsBox);
});

/// Edge function HTTP client. Stateless — single instance is fine. Tests
/// override this with a fake invoker (see C19 test pattern).
final coachFollowUpApiServiceProvider = Provider<CoachFollowUpApiService>(
  (ref) => CoachFollowUpApiService(),
);

/// Time source for local-only hint derivation. Tests override this so the
/// post-date "long quiet" heuristic does not depend on wall-clock time.
final coachFollowUpNowProvider = Provider<DateTime Function()>((ref) {
  return DateTime.now;
});

/// Refreshes the subscription/usage snapshot after a successful generation.
///
/// The Edge function performs the authoritative deduction; this hook only makes
/// the paywall/remaining-quota UI catch up immediately. Tests override it with
/// a no-op/recorder so provider tests do not instantiate the real subscription
/// graph.
final coachFollowUpUsageSyncProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    await ref.read(subscriptionProvider.notifier).refresh();
  };
});

// ── Read-only derived providers ──────────────────────────────────────────

/// The currently-stored card for [partnerId], or null if none exists.
/// Watches the repository instance — invalidate the repository (e.g., after
/// account swap) to force a re-read.
final coachFollowUpResultProvider =
    Provider.family<CoachFollowUpResult?, String>((ref, partnerId) {
  final repo = ref.watch(coachFollowUpRepositoryProvider);
  return repo.get(partnerId);
});

/// "Current conversation" for the partner = the most-recently-updated one.
/// `conversationsByPartnerProvider` already returns the list in updated-desc
/// order (see partner_providers.dart sort at `_partnerLastInteractionProvider`).
///
/// Design choice (C20): we use updated-desc instead of "most-recently-viewed"
/// because tracking view state is extra UX surface area we don't need yet —
/// the freshest conversation is almost always what the user is iterating on.
final _currentConversationProvider =
    Provider.family<Conversation?, String>((ref, partnerId) {
  final list = ref.watch(conversationsByPartnerProvider(partnerId));
  return list.isEmpty ? null : list.first;
});

/// UI nudge: which phase chip should be highlighted as the "default" choice.
/// This is presentation-only — the user can still tap any chip. The resolver
/// is conservative (returns null when uncertain).
///
/// Privacy: scans LOCAL message text only. Never sent to the Edge function.
final coachFollowUpHintProvider =
    Provider.family<CoachFollowUpPhase?, String>((ref, partnerId) {
  final convo = ref.watch(_currentConversationProvider(partnerId));
  if (convo == null) return null;

  // Last 5 messages is enough text for the keyword-scan heuristics in C18
  // without making the resolver scan an entire chat history.
  final recent = convo.messages
      .skip(convo.messages.length > 5 ? convo.messages.length - 5 : 0)
      .map((m) => m.content)
      .toList(growable: false);
  final lastMessage = convo.lastMessage;
  final averageInterval = _averageMessageInterval(convo.messages);

  return CoachFollowUpHintResolver.resolve(CoachFollowUpHintInput(
    gameStage: convo.currentGameStage != null
        ? GameStage.fromString(convo.currentGameStage!)
        : null,
    heatScore: convo.lastEnthusiasmScore,
    recentMessageBodies: recent,
    timeSinceLastMessage: lastMessage == null
        ? null
        : ref.watch(coachFollowUpNowProvider)().difference(
              lastMessage.timestamp,
            ),
    averageMessageInterval: averageInterval,
  ));
});

Duration? _averageMessageInterval(List<Message> messages) {
  if (messages.length < 2) return null;

  final sorted = [...messages]
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  int totalMs = 0;
  var gaps = 0;
  for (var i = 1; i < sorted.length; i++) {
    final gap = sorted[i].timestamp.difference(sorted[i - 1].timestamp);
    if (gap <= Duration.zero) continue;
    totalMs += gap.inMilliseconds;
    gaps++;
  }
  if (gaps == 0) return null;
  return Duration(milliseconds: totalMs ~/ gaps);
}

/// API-bound `partnerHint` — the SOLE place this payload is built. The
/// controller reads this and forwards it to the API service verbatim. The
/// C17 helper enforces the privacy contract at the type boundary.
final coachFollowUpPartnerHintProvider =
    Provider.family<CoachFollowUpPartnerHint?, String>((ref, partnerId) {
  final partner = ref.watch(partnerByIdProvider(partnerId));
  if (partner == null) return null;
  final convo = ref.watch(_currentConversationProvider(partnerId));
  final flag = ref.watch(dataQualityFlagProvider(partnerId));
  final stageRaw = convo?.currentGameStage;
  return buildCoachFollowUpPartnerHint(
    partner: partner,
    currentConversation: convo,
    dataQualityFlag: flag,
    heatScore: convo?.lastEnthusiasmScore,
    gameStage: stageRaw != null ? GameStage.fromString(stageRaw) : null,
  );
});

// ── Controller ───────────────────────────────────────────────────────────

/// AsyncNotifier managing generate / regenerate. Persists the new card on
/// success. On failure, the local box is left untouched (no write before
/// success → no rollback needed).
final coachFollowUpControllerProvider = AsyncNotifierProvider.family<
    CoachFollowUpController, CoachFollowUpResult?, String>(
  CoachFollowUpController.new,
);

class CoachFollowUpController
    extends FamilyAsyncNotifier<CoachFollowUpResult?, String> {
  // Manual debounce flag rather than `state.isLoading` because the latter
  // is also true during the initial `build()` call — using it here would
  // race with first-mount UI.
  bool _inFlight = false;

  @override
  Future<CoachFollowUpResult?> build(String partnerId) async {
    final repo = ref.read(coachFollowUpRepositoryProvider);
    return repo.get(partnerId);
  }

  /// Generate a new card and persist on success. While in-flight, additional
  /// `generate()` / `regenerate()` calls are silent no-ops.
  Future<void> generate({
    required CoachFollowUpPhase phase,
    required CoachFollowUpAnswers answers,
  }) async {
    if (_inFlight) return;
    _inFlight = true;
    try {
      state = const AsyncValue.loading();
      final partnerId = arg;
      final api = ref.read(coachFollowUpApiServiceProvider);
      final repo = ref.read(coachFollowUpRepositoryProvider);
      final hint = ref.read(coachFollowUpPartnerHintProvider(partnerId));

      try {
        final result = await api.generate(
          partnerId: partnerId,
          phase: phase,
          answers: answers,
          partnerHint: hint,
        );
        await repo.put(result);
        state = AsyncValue.data(result);
        await _syncUsageSnapshot();
      } catch (e, st) {
        state = AsyncValue.error(e, st);
      }
    } finally {
      _inFlight = false;
    }
  }

  /// Same wire as `generate()` — the UI distinction ("生成" vs "重新生成")
  /// is purely visual. Both overwrite the stored card on success per the
  /// latest-only design (§3.1).
  Future<void> regenerate({
    required CoachFollowUpPhase phase,
    required CoachFollowUpAnswers answers,
  }) =>
      generate(phase: phase, answers: answers);

  Future<void> _syncUsageSnapshot() async {
    final syncUsage = ref.read(coachFollowUpUsageSyncProvider);
    try {
      await syncUsage();
    } catch (_) {
      // The card generation already succeeded and was persisted. A failed
      // UI-only usage refresh must not turn a valid card into an error state;
      // the next subscription refresh/paywall open will catch up from DB.
    }
  }
}
