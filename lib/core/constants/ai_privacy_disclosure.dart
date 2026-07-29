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
  static const String _openingLine = '你送出的對話與截圖，會經 VibeSync 後端傳送至第三方 AI';

  // 廠商行：只在設定頁 AI 隱私頁揭露。onboarding 刻意不列，
  // 避免使用者誤以為練習室女孩「背後就是 DeepSeek」。
  static const String _vendorLine = '（分析與教練用 Anthropic Claude，練習室用 DeepSeek）';

  static const String _consentLine = '每個 AI 功能首次使用前，都會先徵求你的同意';

  static const String _uploadParagraph = '當你回報建議的採用情況時，僅去識別化的統計（採用了哪類建議、\n'
      '後來互動概況）會上傳以改善服務；你的對話原文與筆記永遠只存在手機';

  // 「我幫你修」與「再調一下」走同一條重播流程、同一份保留期，所以同一段
  // 揭露涵蓋兩者。漏掉微調會讓這頁與實際送出的資料對不上。
  static const String _optimizeReplayParagraph =
      '使用「我幫你修」或「再調一下」時，為了在網路中斷後恢復同一結果並避免重複扣額度，\n'
      'VibeSync 後端的可用重播資料保留 7 天並每小時清除，只存 AI 產生的結果句與理由，不另存原始草稿、微調指令或完整對話輸入；AI 生成文字仍可能反映你提供的內容，刪除後的備份副本依 Supabase 備份週期處理';

  /// 設定頁 AI 隱私頁：完整揭露，含第三方 AI 廠商名與去識別化上傳說明。
  static const String _keyboardReplayParagraph =
      '使用 AI 鍵盤時，只有你主動載入並送出的文字會傳給 Anthropic 產生回覆；原文不會寫入回覆重播紀錄。\n'
      '裝置的共享 Keychain 會暫存 request ID、使用者 ID 與不含原文的指紋；重試資格約 23 小時，成功後或鍵盤下次啟用時會盡力清理，若未再啟用則實體項目可能延後移除。伺服器重播資料保存 24 小時並每小時清理，因此實際刪除可能接近 25 小時；備份與 PITR 依 Supabase 的獨立保存週期處理。';

  /// 「最近截圖」是預設關閉、需要獨立同意的選用功能，因此單獨成段，
  /// 不與上面的文字回覆流程混在一起。
  static const String _keyboardScreenshotParagraph =
      '若你另行同意並啟用鍵盤的「最近截圖」輔助，鍵盤開啟時會在本機尋找最近 3 分鐘的系統截圖並自動分析一張，不會再逐次詢問。\n'
      '上傳前會裁掉截圖裡 VibeSync 鍵盤自己佔的區塊，鍵盤上也會一直顯示這次用的是哪一張。後端不保存截圖或 OCR 逐字稿，你可以隨時在「設定 > 鍵盤」撤回同意並清除鍵盤脈絡。';

  static const String description =
      '$_openingLine\n$_vendorLine\n$_consentLine\n\n$_uploadParagraph\n\n$_optimizeReplayParagraph\n\n$_keyboardReplayParagraph\n\n$_keyboardScreenshotParagraph';

  /// Onboarding 第 4 頁：只保留「送第三方 AI」與「同意閘」兩句，
  /// 不列廠商名（避免誤解練習室女孩＝DeepSeek）。完整揭露留在設定頁。
  static const String onboardingDescription = '$_openingLine\n$_consentLine';
}
