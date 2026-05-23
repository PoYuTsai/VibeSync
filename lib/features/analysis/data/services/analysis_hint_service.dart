import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// First-run hint dismissal flags for the analysis screen.
///
/// Pattern mirrors [OnboardingService] / [PartnerBannerService]: static
/// helpers over a SharedPreferences boolean flag, no instance state.
class AnalysisHintService {
  // v2 intentionally ignores the older boolean key. Early dogfood builds could
  // mark the hint as seen before the trigger point was fixed, which then hid
  // the coach mark forever even after users updated the app.
  static const _editMessageKey = 'analysis_edit_message_hint_seen_v2';

  static Future<bool> hasSeenEditMessage() async {
    // Debug build：永遠當成沒看過，dogfood 階段可以反覆驗證 coach mark
    // 觸發點而不用刪 app / 處理 SharedPreferences race。Release/TestFlight
    // 不受影響，維持 first-run only 行為。
    if (kDebugMode) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_editMessageKey) ?? false;
  }

  static Future<void> markEditMessageSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_editMessageKey, true);
  }
}
