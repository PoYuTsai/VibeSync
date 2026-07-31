// lib/features/onboarding/domain/keyboard_onboarding_gate.dart
//
// 2026-08-01 轉化診斷 Tier 1-4：首次鍵盤設定（4 頁）的觸發閘門，
// 從 app.dart 抽成純函式讓決策可單元測試。
import 'package:flutter/foundation.dart';

/// 是否該自動 push 首次鍵盤設定（`/settings/keyboard?firstRun=1`）。
///
/// - 非 iOS 一律不觸發：頁面文案與 `app-settings:` deep link 是 iOS 專屬，
///   Android 會看到對他無效的流程。
/// - 主 onboarding「同一個 session 剛完成」不觸發：按「略過」想快點進 App
///   的人不該立刻被丟進 4 頁鍵盤設定；延到下次啟動落在首頁再出現。
bool shouldScheduleKeyboardOnboarding({
  required TargetPlatform platform,
  required bool splashComplete,
  required bool isAuthenticated,
  required bool onboardingCompleted,
  required bool onboardingCompletedThisSession,
  required bool keyboardOnboardingCompleted,
  required bool alreadyPending,
}) {
  if (platform != TargetPlatform.iOS) return false;
  if (!splashComplete || !isAuthenticated) return false;
  if (!onboardingCompleted || keyboardOnboardingCompleted) return false;
  if (onboardingCompletedThisSession) return false;
  if (alreadyPending) return false;
  return true;
}
