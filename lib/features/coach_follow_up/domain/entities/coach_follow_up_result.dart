import 'package:hive_ce/hive_ce.dart';

part 'coach_follow_up_result.g.dart';

/// Spec 5 Coach Follow-up — local persistence of the latest server-generated
/// card, keyed by `partnerId`. Repository overwrites on each new generation
/// (latest-only — design §3.1: no history, no list view).
///
/// Fields mirror the server response card 1:1:
///   - [phase] — `CoachFollowUpPhase.name` String (stable English wire key)
///   - [headline] / [observation] / [task] / [boundaryReminder] — display text
///     already truncated by the Edge function `truncateCard` (caps 30/80/30/60)
///     and screened by `assertCardSafe` (banned-token validator)
///   - [suggestedLine] — optional, can be null
///   - [generatedAt] — server-stamped at success-path response
///   - [modelUsed] — `claude-haiku-4-5-20251001` | `claude-sonnet-4-6`
///
/// Persistence scope: device-local, NOT synced to Supabase. Account-clear
/// (deleteAccount → StorageService.clearAll) is wired in B14. Per-partner
/// cleanup on partner deletion is wired in B15.
///
/// typeId 16 was verified free at 2026-05-02 (highest claimed: 15 NamePair).
@HiveType(typeId: 16)
class CoachFollowUpResult {
  @HiveField(0)
  final String partnerId;

  @HiveField(1)
  final String phase;

  @HiveField(2)
  final String headline;

  @HiveField(3)
  final String observation;

  @HiveField(4)
  final String task;

  @HiveField(5)
  final String? suggestedLine;

  @HiveField(6)
  final String boundaryReminder;

  @HiveField(7)
  final DateTime generatedAt;

  @HiveField(8)
  final String modelUsed;

  const CoachFollowUpResult({
    required this.partnerId,
    required this.phase,
    required this.headline,
    required this.observation,
    required this.task,
    this.suggestedLine,
    required this.boundaryReminder,
    required this.generatedAt,
    required this.modelUsed,
  });
}
