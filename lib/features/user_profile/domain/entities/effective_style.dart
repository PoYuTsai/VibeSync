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

  /// 副風格 — always resolved as an atomic (主, 副) pair with
  /// [interactionStyle]; never mixed across layers (see resolver doc).
  final InteractionStyle? secondaryStyle;
  final List<PracticeGoal> practiceGoals;
  final String? notes;

  /// 我現在卡在哪 — global only, never merged with a partner override
  /// (there is no per-partner concept of "現在卡在哪").
  final List<StuckPoint> stuckPoints;

  const EffectiveStyle({
    this.interactionStyle,
    this.secondaryStyle,
    this.practiceGoals = const [],
    this.notes,
    this.stuckPoints = const [],
  });
}
