// lib/app/keyboard_onboarding_scheduler.dart
//
// 首次鍵盤設定自動 push 的排程接線，從 app.dart 抽出來讓時序可測
// （純條件已在 keyboard_onboarding_gate.dart，這裡管「何時觸發、對哪個
// router 狀態判斷」）。
import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

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
  bool _detached = false;

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
    if (_shownThisSession) return;
    if (!shouldScheduleKeyboardOnboarding(
      platform: defaultTargetPlatform,
      splashComplete: isSplashComplete(),
      isAuthenticated: isAuthenticated(),
      onboardingCompleted: OnboardingService.isCompletedSync,
      onboardingCompletedThisSession:
          OnboardingService.completedThisSessionSync,
      keyboardOnboardingCompleted: OnboardingService.isKeyboardCompletedSync,
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
      trackShown();
      unawaited(
        router.push('/settings/keyboard?firstRun=1').whenComplete(() {
          _pending = false;
        }),
      );
    });
  }
}
