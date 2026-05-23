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

  /// Debug-only：清除旗標，讓下次符合條件的 build 重新浮出 coach mark。
  /// dogfood 階段重複驗證觸發點時用，production 不會呼叫到。
  static Future<void> resetEditMessageSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_editMessageKey);
  }
}
