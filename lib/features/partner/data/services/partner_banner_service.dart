import 'package:shared_preferences/shared_preferences.dart';

/// Per-account dismissal state for the same-name dedupe banner.
///
/// Key is suffixed with `uid` so one user's "dismissed" never bleeds into
/// another user's session on the same device (D-P4-5 cross-account
/// isolation invariant).
///
/// Pattern mirrors [OnboardingService]: static helpers over a single
/// SharedPreferences boolean flag, no instance state.
class PartnerBannerService {
  static String _key(String uid) => 'partner_dedupe_banner_dismissed_$uid';

  static Future<bool> isDismissed(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key(uid)) ?? false;
  }

  static Future<void> markDismissed(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(uid), true);
  }
}
