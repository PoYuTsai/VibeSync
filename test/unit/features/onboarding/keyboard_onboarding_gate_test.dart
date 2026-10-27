// test/unit/features/onboarding/keyboard_onboarding_gate_test.dart
//
// 轉化診斷 Tier 1-4：鍵盤設定 4 頁的觸發閘門。
// 兩個新規則：
//   1. 非 iOS 一律不觸發（頁面文案與 deep link 是 iOS 專屬，Android
//      看到的是對他無效的流程）。
//   2. 主 onboarding「同一個 session 剛完成」不觸發——按「略過」想快點
//      進 App 的人不該立刻被丟進 4 頁鍵盤設定；延到下次冷啟動再出現。
// onboarding 轉換第 13 步（2026-10-27）再加兩條：
//   3. 成功分析滿 2 次才觸發——不在他趕著分析時擋路。
//   4. 網頁版一律不觸發——iPhone Safari 開網頁版時平台也是 iOS，只看平台會
//      跳出裝不了的鍵盤教學（設定頁的鍵盤區早就排除 Web）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/features/onboarding/data/onboarding_service.dart';
import 'package:vibesync/features/onboarding/domain/keyboard_onboarding_gate.dart';

bool _gate({
  TargetPlatform platform = TargetPlatform.iOS,
  bool isWeb = false,
  bool splashComplete = true,
  bool isAuthenticated = true,
  bool onboardingCompleted = true,
  bool onboardingCompletedThisSession = false,
  bool keyboardOnboardingCompleted = false,
  bool alreadyPending = false,
  int successfulAnalysisCount = 2,
}) =>
    shouldScheduleKeyboardOnboarding(
      platform: platform,
      isWeb: isWeb,
      splashComplete: splashComplete,
      isAuthenticated: isAuthenticated,
      onboardingCompleted: onboardingCompleted,
      onboardingCompletedThisSession: onboardingCompletedThisSession,
      keyboardOnboardingCompleted: keyboardOnboardingCompleted,
      alreadyPending: alreadyPending,
      successfulAnalysisCount: successfulAnalysisCount,
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

    test('成功分析 0、1 次 → 不觸發；滿 2 次（含以上）→ 觸發', () {
      expect(_gate(successfulAnalysisCount: 0), isFalse);
      expect(_gate(successfulAnalysisCount: 1), isFalse);
      expect(_gate(successfulAnalysisCount: 2), isTrue);
      expect(_gate(successfulAnalysisCount: 7), isTrue);
      expect(keyboardOnboardingMinSuccessfulAnalyses, 2);
    });

    test('分析滿 2 次也不蓋過其他條件：同 session 剛完成 onboarding 仍不觸發', () {
      expect(
        _gate(successfulAnalysisCount: 5, onboardingCompletedThisSession: true),
        isFalse,
      );
      expect(
        _gate(successfulAnalysisCount: 5, keyboardOnboardingCompleted: true),
        isFalse,
      );
    });

    test('網頁版（含 iPhone Safari 開的）一律不觸發', () {
      expect(_gate(isWeb: true), isFalse);
      expect(_gate(isWeb: true, successfulAnalysisCount: 10), isFalse);
    });
  });

  group('isKeyboardSetupAvailable', () {
    test('只有 iOS App 有鍵盤設定；網頁版與 Android 都沒有', () {
      expect(
        isKeyboardSetupAvailable(platform: TargetPlatform.iOS, isWeb: false),
        isTrue,
      );
      expect(
        isKeyboardSetupAvailable(platform: TargetPlatform.iOS, isWeb: true),
        isFalse,
        reason: 'iPhone Safari 開網頁版時平台也是 iOS，不能只看平台',
      );
      expect(
        isKeyboardSetupAvailable(
          platform: TargetPlatform.android,
          isWeb: false,
        ),
        isFalse,
      );
      expect(
        isKeyboardSetupAvailable(platform: TargetPlatform.android, isWeb: true),
        isFalse,
      );
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
