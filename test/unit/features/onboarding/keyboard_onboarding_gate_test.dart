// test/unit/features/onboarding/keyboard_onboarding_gate_test.dart
//
// 轉化診斷 Tier 1-4：鍵盤設定 4 頁的觸發閘門。
// 兩個新規則：
//   1. 非 iOS 一律不觸發（頁面文案與 deep link 是 iOS 專屬，Android
//      看到的是對他無效的流程）。
//   2. 主 onboarding「同一個 session 剛完成」不觸發——按「略過」想快點
//      進 App 的人不該立刻被丟進 4 頁鍵盤設定；延到下次冷啟動再出現。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/features/onboarding/data/onboarding_service.dart';
import 'package:vibesync/features/onboarding/domain/keyboard_onboarding_gate.dart';

bool _gate({
  TargetPlatform platform = TargetPlatform.iOS,
  bool splashComplete = true,
  bool isAuthenticated = true,
  bool onboardingCompleted = true,
  bool onboardingCompletedThisSession = false,
  bool keyboardOnboardingCompleted = false,
  bool alreadyPending = false,
}) =>
    shouldScheduleKeyboardOnboarding(
      platform: platform,
      splashComplete: splashComplete,
      isAuthenticated: isAuthenticated,
      onboardingCompleted: onboardingCompleted,
      onboardingCompletedThisSession: onboardingCompletedThisSession,
      keyboardOnboardingCompleted: keyboardOnboardingCompleted,
      alreadyPending: alreadyPending,
    );

void main() {
  group('shouldScheduleKeyboardOnboarding', () {
    test('iOS＋條件齊備（跨 session 回訪）→ 觸發', () {
      expect(_gate(), isTrue);
    });

    test('非 iOS 一律不觸發', () {
      expect(_gate(platform: TargetPlatform.android), isFalse);
      expect(_gate(platform: TargetPlatform.macOS), isFalse);
    });

    test('主 onboarding 同 session 剛完成 → 不觸發（延到下次啟動）', () {
      expect(_gate(onboardingCompletedThisSession: true), isFalse);
    });

    test('splash 未完成／未登入／主 onboarding 未完成 → 不觸發', () {
      expect(_gate(splashComplete: false), isFalse);
      expect(_gate(isAuthenticated: false), isFalse);
      expect(_gate(onboardingCompleted: false), isFalse);
    });

    test('鍵盤設定已完成或已在排程中 → 不觸發', () {
      expect(_gate(keyboardOnboardingCompleted: true), isFalse);
      expect(_gate(alreadyPending: true), isFalse);
    });
  });

  group('OnboardingService session 旗標', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('markCompleted 同時立起 session 旗標；reset 清掉', () async {
      await OnboardingService.reset();
      expect(OnboardingService.completedThisSessionSync, isFalse);

      await OnboardingService.markCompleted();
      expect(OnboardingService.completedThisSessionSync, isTrue);

      await OnboardingService.reset();
      expect(OnboardingService.completedThisSessionSync, isFalse);
    });

    test('load（模擬下次啟動讀持久旗標）不會立起 session 旗標', () async {
      await OnboardingService.reset();
      SharedPreferences.setMockInitialValues({'onboarding_completed': true});

      await OnboardingService.load();
      expect(OnboardingService.isCompletedSync, isTrue);
      expect(OnboardingService.completedThisSessionSync, isFalse);
    });
  });
}
