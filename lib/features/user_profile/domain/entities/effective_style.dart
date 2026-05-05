import 'package:flutter/foundation.dart';

import 'user_profile.dart';

/// The resolved per-partner style after merging global About Me with the
/// per-partner override. Pure value object; produced by
/// [resolveEffectiveStyle] in `domain/services/resolve_effective_style.dart`.
///
/// Spec 2.5 turns this contract into prompt context through
/// `EffectiveStylePromptBuilder`. UI still uses [EffectiveStyle] for
/// placeholder hints ("沿用全域：穩重") on the edit screen.
@immutable
class EffectiveStyle {
  final InteractionStyle? interactionStyle;
  final List<PracticeGoal> practiceGoals;
  final String? notes;

  const EffectiveStyle({
    this.interactionStyle,
    this.practiceGoals = const [],
    this.notes,
  });
}
