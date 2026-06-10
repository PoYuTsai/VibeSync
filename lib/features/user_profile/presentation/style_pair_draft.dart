import 'package:flutter/foundation.dart';

import '../domain/entities/user_profile.dart';

/// Ordered (主, 副) interaction-style selection — style pair 2026-06-10.
///
/// Pure tap state machine shared by AboutMeScreen and PartnerStyleEditScreen
/// so both surfaces behave identically. Legal states only: `secondary` is
/// never non-null while `primary` is null, and 副 != 主 — guaranteed by
/// construction as long as callers only mutate via [tap] / [cleared].
///
/// | 點擊 | 行為 |
/// |---|---|
/// | 未選 chip，0 選 | 成為主 |
/// | 未選 chip，1 選 | 成為副 |
/// | 未選 chip，2 選 | 取代副（主不被路過點擊偷換） |
/// | 主 chip | 取消主；有副 → 副升格為主 |
/// | 副 chip | 取消副 |
@immutable
class StylePairDraft {
  final InteractionStyle? primary;
  final InteractionStyle? secondary;

  const StylePairDraft({this.primary, this.secondary});

  static const StylePairDraft empty = StylePairDraft();

  /// Returns the next state after tapping [style]'s chip.
  StylePairDraft tap(InteractionStyle style) {
    if (style == primary) {
      // 取消主；副（若有）升格為主。
      return StylePairDraft(primary: secondary);
    }
    if (style == secondary) {
      return StylePairDraft(primary: primary);
    }
    if (primary == null) {
      return StylePairDraft(primary: style);
    }
    // 1 選 → 成為副；2 選 → 取代副。主永遠不被路過點擊偷換。
    return StylePairDraft(primary: primary, secondary: style);
  }

  bool contains(InteractionStyle style) =>
      style == primary || style == secondary;

  /// '主' / '副' badge text for [style]'s chip, or null when unselected.
  String? badgeOf(InteractionStyle style) {
    if (style == primary) return '主';
    if (style == secondary) return '副';
    return null;
  }
}
