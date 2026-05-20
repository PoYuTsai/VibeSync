import 'package:shared_preferences/shared_preferences.dart';

/// First-run hint dismissal flags for the analysis screen.
///
/// Pattern mirrors [OnboardingService] / [PartnerBannerService]: static
/// helpers over a SharedPreferences boolean flag, no instance state.
class AnalysisHintService {
  static const _editMessageKey = 'analysis_edit_message_hint_seen';

  static Future<bool> hasSeenEditMessage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_editMessageKey) ?? false;
  }

  static Future<void> markEditMessageSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_editMessageKey, true);
  }
}
