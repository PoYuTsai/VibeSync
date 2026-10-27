// lib/features/onboarding/domain/keyboard_onboarding_gate.dart
//
// 2026-08-01 轉化診斷 Tier 1-4：首次鍵盤設定（4 頁）的觸發閘門，
// 從 app.dart 抽成純函式讓決策可單元測試。
//
// 2026-10-27 改時機（onboarding 轉換第 13 步，Eric「全部都做 照夥伴預設 開工」，
// 夥伴規格決策表第 5 題）：原本第 2 次打開 App 就自動跳；可是那常常是「她回了、
// 他回來趕快分析」的時刻，教學擋在路上。改成這台裝置成功分析滿 2 次之後的下一次
// 打開才跳（次數一個 session 只讀一次，見 KeyboardOnboardingScheduler）。
// 「稍後設定」與關閉仍算完成、每個 session 最多跳一次，都不變。
import 'package:flutter/foundation.dart';

/// 成功分析滿幾次才自動提示鍵盤設定。
const keyboardOnboardingMinSuccessfulAnalyses = 2;

/// 這台裝置有沒有 VibeSync AI 鍵盤的設定與教學：只有 iOS App 有。
///
/// 網頁版一律沒有——在 iPhone Safari 開網頁版時 [defaultTargetPlatform] 也是
/// iOS，只看平台會讓網頁版跳出裝不了的鍵盤教學（設定頁的鍵盤區早就排除
/// Web：settings_screen.dart 的 `!kIsWeb && …iOS`）。
bool isKeyboardSetupAvailable({
  required TargetPlatform platform,
  required bool isWeb,
}) =>
    !isWeb && platform == TargetPlatform.iOS;

/// 是否該自動 push 首次鍵盤設定（`/settings/keyboard?firstRun=1`）。
///
/// - 只在 iOS App 觸發（[isKeyboardSetupAvailable]）：頁面文案與
///   `app-settings:` deep link 是 iOS 專屬，Android 與網頁版會看到對他無效的
///   流程。
/// - 主 onboarding「同一個 session 剛完成」不觸發：按「略過」想快點進 App
///   的人不該立刻被丟進 4 頁鍵盤設定；延到下次啟動落在首頁再出現。
/// - 成功分析未滿 [keyboardOnboardingMinSuccessfulAnalyses] 次不觸發：等他熟了
///   再提示，不在他趕著分析時擋路。
bool shouldScheduleKeyboardOnboarding({
  required TargetPlatform platform,
  required bool isWeb,
  required bool splashComplete,
  required bool isAuthenticated,
  required bool onboardingCompleted,
  required bool onboardingCompletedThisSession,
  required bool keyboardOnboardingCompleted,
  required bool alreadyPending,
  required int successfulAnalysisCount,
}) {
  if (!isKeyboardSetupAvailable(platform: platform, isWeb: isWeb)) {
    return false;
  }
  if (!splashComplete || !isAuthenticated) return false;
  if (!onboardingCompleted || keyboardOnboardingCompleted) return false;
  if (onboardingCompletedThisSession) return false;
  if (alreadyPending) return false;
  if (successfulAnalysisCount < keyboardOnboardingMinSuccessfulAnalyses) {
    return false;
  }
  return true;
}
