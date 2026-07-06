// lib/core/constants/ai_privacy_disclosure.dart
//
// R1-4 / F5-A7 —「AI 與你的隱私」靜態揭露文案的單一來源。
// onboarding 第 4 頁與設定頁的 AI 隱私頁共用，避免雙份文案漂移。
// 純文案常數：實際同意仍由各 AI 功能首次使用前的 AiDataSharingConsent
// 同意閘把關，這裡不含任何同意邏輯。
class AiPrivacyDisclosure {
  const AiPrivacyDisclosure._();

  static const String title = 'AI 與你的隱私';

  static const String description =
      '你送出的對話與截圖，會經 VibeSync 後端傳送至第三方 AI\n'
      '（分析與教練用 Anthropic Claude，練習室用 DeepSeek）\n'
      '每個 AI 功能首次使用前，都會先徵求你的同意\n'
      '\n'
      '當你回報建議的採用情況時，僅去識別化的統計（採用了哪類建議、\n'
      '後來互動概況）會上傳以改善服務；你的對話原文與筆記永遠只存在手機';
}
