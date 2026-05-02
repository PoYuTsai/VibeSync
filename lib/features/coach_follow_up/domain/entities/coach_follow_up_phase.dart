/// Spec 5 Coach Follow-up — phase taxonomy.
///
/// Three life-stage windows where a follow-up coaching card adds value:
///   - prepareInvite    準備邀約 — user hasn't asked yet / opened but no reply / opened wrong
///   - preDateReminder  約會前提醒 — date locked, meeting soon
///   - postDateReflection 約會後復盤 — just met / met recently, needs pacing reflection
///
/// `.name` keys are the WIRE FORMAT — they ride on:
///   - the Edge function request body (`phase` field)
///   - Hive persistence (`CoachFollowUpResult.phase` as String)
///   - server-side telemetry (`coach_follow_up_invoked.phase`)
///
/// 繁中 [displayLabel] stays in the UI layer ONLY. NEVER persist or send the
/// label on the wire — design §1 stable-key discipline.
enum CoachFollowUpPhase {
  prepareInvite,
  preDateReminder,
  postDateReflection;

  /// Parse a stable English key back to the enum. Returns null for unknown,
  /// empty, or null input. Display labels (繁中) are intentionally NOT accepted
  /// — they are presentation-only and have no inverse mapping by design.
  static CoachFollowUpPhase? fromString(String? value) {
    if (value == null || value.isEmpty) return null;
    for (final v in CoachFollowUpPhase.values) {
      if (v.name == value) return v;
    }
    return null;
  }

  String get displayLabel {
    switch (this) {
      case CoachFollowUpPhase.prepareInvite:
        return '準備邀約';
      case CoachFollowUpPhase.preDateReminder:
        return '約會前提醒';
      case CoachFollowUpPhase.postDateReflection:
        return '約會後復盤';
    }
  }
}
