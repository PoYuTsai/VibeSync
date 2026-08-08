// lib/app/keyboard_onboarding_scheduler.dart
//
// 首次鍵盤設定自動 push 的排程接線，從 app.dart 抽出來讓時序可測
// （純條件已在 keyboard_onboarding_gate.dart，這裡管「何時觸發、對哪個
// router 狀態判斷」）。
import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../features/keyboard/data/keyboard_setup_resume_marker.dart';
import '../features/onboarding/data/onboarding_service.dart';
import '../features/onboarding/domain/keyboard_onboarding_gate.dart';

/// 監聽 router 與外部觸發（splash 完成、auth 事件），條件齊備且人在首頁
/// 時自動 push `/settings/keyboard?firstRun=1`。
class KeyboardOnboardingScheduler {
  KeyboardOnboardingScheduler({
    required this.router,
    required this.isAuthenticated,
    required this.isSplashComplete,
    required this.trackShown,
  });

  final GoRouter router;
  final bool Function() isAuthenticated;
  final bool Function() isSplashComplete;
  final void Function() trackShown;

  bool _pending = false;
  bool _shownThisSession = false;
  bool _resumePending = false;
  bool _detached = false;

  /// 冷啟動讀「切完整取用中斷」旗標：有旗標＝上次是在設定流程裡被 iOS
  /// 殺掉（切權限開關必殺 App），要無視 gate 條件把設定頁推回來——
  /// 已完成過鍵盤引導的人從起步清單／設定頁重走一樣會中斷（2026-08-07
  /// 真機重測命中），gate 的 completed 條件會把他們擋在首頁。
  Future<void> primeFullAccessResume() async {
    if (!await KeyboardSetupResumeMarker.isSet()) return;
    if (_detached) return;
    _resumePending = true;
    maybeSchedule();
  }

  // 監聽對象必須是 routerDelegate：redirect 與 app 內導航只會 notify
  // delegate；routeInformationProvider 的 routerReportsNewRouteInformation
  // 靜默更新 _value、不通知 listener（go_router 14.8.1 源碼＋探針證實），
  // 掛在它上面等於冷啟動後永遠沒有重觸發機會。
  void attach() {
    router.routerDelegate.addListener(maybeSchedule);
  }

  void detach() {
    _detached = true;
    router.routerDelegate.removeListener(maybeSchedule);
  }

  void maybeSchedule() {
    // 自動 push 一個 session 至多一次：delegate 每次導航都會 notify，
    // 沒有這道閂，使用者按 X 關掉回首頁會立刻被再推一次，變騷擾迴圈。
    if (_shownThisSession || _pending) return;
    if (!_resumePending &&
        !shouldScheduleKeyboardOnboarding(
          platform: defaultTargetPlatform,
          splashComplete: isSplashComplete(),
          isAuthenticated: isAuthenticated(),
          onboardingCompleted: OnboardingService.isCompletedSync,
          onboardingCompletedThisSession:
              OnboardingService.completedThisSessionSync,
          keyboardOnboardingCompleted:
              OnboardingService.isKeyboardCompletedSync,
          alreadyPending: _pending,
        )) {
      return;
    }

    _pending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_detached) return;
      // 路徑讀 routerDelegate.currentConfiguration：冷啟動 splash 完成的
      // postFrame 當下 routeInformationProvider.value 還停在 initialLocation
      // '/login'（redirect 結果晚一步才回寫），讀它會誤判不在首頁而放棄。
      final currentPath = router.routerDelegate.currentConfiguration.uri.path;
      if (currentPath != '/') {
        _pending = false;
        return;
      }
      _shownThisSession = true;
      if (_resumePending) {
        // 中斷復原：非 firstRun（關閉走 pop 回首頁），也不打
        // keyboard_setup_shown——這不是首次曝光，會污染採用漏斗。
        // 旗標本體由設定頁 initState 消費並跳回「允許完整取用」後的
        // 相片權限（截圖輔助）頁。
        _resumePending = false;
        unawaited(
          router.push('/settings/keyboard').whenComplete(() {
            _pending = false;
          }),
        );
        return;
      }
      trackShown();
      unawaited(
        router.push('/settings/keyboard?firstRun=1').whenComplete(() {
          _pending = false;
        }),
      );
    });
  }
}
