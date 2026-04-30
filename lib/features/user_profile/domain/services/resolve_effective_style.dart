import '../entities/effective_style.dart';
import '../entities/partner_style_override.dart';
import '../entities/user_profile.dart';

/// Per-field merge of the global About Me with a partner-scoped override.
///
/// Inheritance rules (Spec 2 design Q3 = "B per-field"):
/// - `interactionStyle`: partner wins if non-null, else global.
/// - `practiceGoals`: partner wins **only if non-empty**; an explicitly-empty
///   partner override falls back to global goals (avoids "set then cleared"
///   trapping the user with no goals at all).
/// - `notes`: partner wins if non-null, else global.
///
/// Both layers may be null (e.g. fresh user before any About Me set up);
/// resolver returns all-null / empty in that case so callers can render
/// "尚未設定" placeholders without null-guarding every field.
EffectiveStyle resolveEffectiveStyle({
  UserProfile? global,
  PartnerStyleOverride? partner,
}) {
  return EffectiveStyle(
    interactionStyle: partner?.interactionStyle ?? global?.interactionStyle,
    practiceGoals: (partner?.practiceGoals.isNotEmpty ?? false)
        ? partner!.practiceGoals
        : (global?.practiceGoals ?? const []),
    notes: partner?.notes ?? global?.notes,
  );
}
