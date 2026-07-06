// lib/core/constants/ai_privacy_disclosure.dart
//
// R1-4 / F5-A7 —「AI 與你的隱私」靜態揭露文案的單一來源。
// onboarding 第 4 頁與設定頁的 AI 隱私頁共用，避免雙份文案漂移。
// 純文案常數：實際同意仍由各 AI 功能首次使用前的 AiDataSharingConsent
// 同意閘把關，這裡不含任何同意邏輯。
class AiPrivacyDisclosure {
  const AiPrivacyDisclosure._();

  static const String title = 'AI 與你的隱私';

  // 共用單句，避免 onboarding 與設定頁雙份漂移。
  static const String _openingLine =
      '你送出的對話與截圖，會經 VibeSync 後端傳送至第三方 AI';

  // 廠商行：只在設定頁 AI 隱私頁揭露。onboarding 刻意不列，
  // 避免使用者誤以為練習室女孩「背後就是 DeepSeek」。
  static const String _vendorLine =
      '（分析與教練用 Anthropic Claude，練習室用 DeepSeek）';

  static const String _consentLine = '每個 AI 功能首次使用前，都會先徵求你的同意';

  static const String _uploadParagraph =
      '當你回報建議的採用情況時，僅去識別化的統計（採用了哪類建議、\n'
      '後來互動概況）會上傳以改善服務；你的對話原文與筆記永遠只存在手機';

  /// 設定頁 AI 隱私頁：完整揭露，含第三方 AI 廠商名與去識別化上傳說明。
  static const String description =
      '$_openingLine\n$_vendorLine\n$_consentLine\n\n$_uploadParagraph';

  /// Onboarding 第 4 頁：只保留「送第三方 AI」與「同意閘」兩句，
  /// 不列廠商名（避免誤解練習室女孩＝DeepSeek）。完整揭露留在設定頁。
  static const String onboardingDescription = '$_openingLine\n$_consentLine';
}
