import '../entities/coach_follow_up_result.dart';

/// Spec 5 — local persistence contract for the latest follow-up card.
///
/// Latest-only by design (§3.1): each new generation overwrites the previous
/// card for that partner. No list view, no history, no chronology — the UI
/// surfaces "the most recent coaching prompt" and that's it.
///
/// Implementations live in `data/repositories/`. The interface stays in
/// `domain/` so providers + state controllers (Phase C) can depend on the
/// abstraction rather than the Hive-backed concrete class — keeps tests
/// trivially fakeable without dragging Hive into widget tests.
abstract class CoachFollowUpRepository {
  /// Returns the stored card for [partnerId], or null if none exists.
  CoachFollowUpResult? get(String partnerId);

  /// Persists [result], keyed by `result.partnerId`. If a card for that
  /// partner already exists, it is OVERWRITTEN (latest-only).
  Future<void> put(CoachFollowUpResult result);

  /// Removes the card for [partnerId]. Used by partner-delete cascade (B15).
  /// No-op when no card exists for that partner.
  Future<void> delete(String partnerId);

  /// Wipes every entry. Called by `StorageService.clearAll()` on account
  /// deletion (B14 wires this).
  Future<void> clearAll();
}
