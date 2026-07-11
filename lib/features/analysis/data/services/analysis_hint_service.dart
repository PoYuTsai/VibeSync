import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// First-run hint dismissal flags for the analysis screen.
///
/// Pattern mirrors [OnboardingService] / [PartnerBannerService]: static
/// helpers over a SharedPreferences boolean flag, no instance state.
class AnalysisHintService {
  static const _editMessagePartnerKeyPrefix =
      'analysis_edit_message_hint_seen_v2_partner_';
  static const _editMessageGlobalKey =
      'analysis_edit_message_hint_seen_v2_global';
  static const _ocrSwipeTutorialGlobalKey =
      'analysis_ocr_swipe_tutorial_seen_v1_global';

  static String _editMessageKey(String? partnerId) {
    final trimmedPartnerId = partnerId?.trim();
    if (trimmedPartnerId != null && trimmedPartnerId.isNotEmpty) {
      return '$_editMessagePartnerKeyPrefix$trimmedPartnerId';
    }
    return _editMessageGlobalKey;
  }

  static Future<bool> hasSeenEditMessage({String? partnerId}) async {
    // Debug build：永遠當成沒看過，dogfood 階段可以反覆驗證 coach mark
    // 觸發點而不用刪 app / 處理 SharedPreferences race。Release/TestFlight
    // 不受影響，維持 first-run only 行為。
    if (kDebugMode) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_editMessageKey(partnerId)) ?? false;
  }

  static Future<void> markEditMessageSeen({String? partnerId}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_editMessageKey(partnerId), true);
  }

  /// Whether this device has already auto-played the OCR side-correction
  /// tutorial.
  ///
  /// This flag intentionally does not use the debug-only bypass from
  /// [hasSeenEditMessage]. The OCR dialog always keeps a replay button, so
  /// repeatedly auto-playing the motion in debug would hide first-run bugs.
  static Future<bool> hasSeenOcrSwipeTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_ocrSwipeTutorialGlobalKey) ?? false;
  }

  static Future<void> markOcrSwipeTutorialSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_ocrSwipeTutorialGlobalKey, true);
  }
}
