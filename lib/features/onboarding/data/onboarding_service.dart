// lib/features/onboarding/data/onboarding_service.dart
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingService {
  static const _key = 'onboarding_completed';
  static const _keyboardKey = 'keyboard_onboarding_completed';

  // In-memory mirror of the persisted flag. The router redirect is synchronous
  // and must not await storage on every navigation, so it reads this cache via
  // [isCompletedSync]. Primed by [load] at startup; kept in sync by
  // [markCompleted] / [reset].
  static bool _completedCache = false;

  // 鍵盤旗標用 ValueNotifier：起步清單在設定流程 pop 回首頁時要即時亮勾，
  // 純靜態快取 UI 監聽不到變化。
  static final ValueNotifier<bool> keyboardCompletedListenable =
      ValueNotifier<bool>(false);

  // 本次 session 內才完成主 onboarding（未持久化，重啟即清）。
  // 鍵盤設定閘門靠它把首次自動 push 延到下次啟動（Tier 1-4）。
  static bool _completedThisSession = false;

  /// Synchronous completion state for the router redirect.
  static bool get isCompletedSync => _completedCache;

  /// 主 onboarding 是否在本次 session 內剛完成。
  static bool get completedThisSessionSync => _completedThisSession;

  /// First-run keyboard setup is a separate, optional onboarding. It must not
  /// become part of the core app onboarding gate because users can dismiss it
  /// and continue using VibeSync without enabling the extension.
  static bool get isKeyboardCompletedSync => keyboardCompletedListenable.value;

  /// Loads the persisted flag into the in-memory cache. Must run during app
  /// startup before the router first evaluates redirects, otherwise a returning
  /// user who already finished onboarding could be misrouted back to it.
  static Future<bool> load() async {
    final prefs = await SharedPreferences.getInstance();
    _completedCache = prefs.getBool(_key) ?? false;
    keyboardCompletedListenable.value = prefs.getBool(_keyboardKey) ?? false;
    return _completedCache;
  }

  static Future<bool> isCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    _completedCache = prefs.getBool(_key) ?? false;
    keyboardCompletedListenable.value = prefs.getBool(_keyboardKey) ?? false;
    return _completedCache;
  }

  static Future<void> markCompleted() async {
    // Flip the cache synchronously so the redirect fired by the immediate
    // post-completion context.go('/') already observes completion.
    _completedCache = true;
    _completedThisSession = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
  }

  static const _pendingGoalsKey = 'onboarding_pending_goals';
  static const _pendingRouteKey = 'onboarding_pending_route';

  /// 登入前完成 onboarding 時暫存問卷目標與分流目的地
  /// （2026-08-18：onboarding 移到登入前），登入後由 MainShell 的
  /// OnboardingHandoffApplier 取走套用。
  static Future<void> stashPendingHandoff({
    required List<String> goalNames,
    required String route,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_pendingGoalsKey, goalNames);
    await prefs.setString(_pendingRouteKey, route);
  }

  /// 取走暫存（讀完即清）。沒有暫存回 null。
  static Future<({List<String> goalNames, String route})?>
      takePendingHandoff() async {
    final prefs = await SharedPreferences.getInstance();
    final route = prefs.getString(_pendingRouteKey);
    if (route == null) return null;
    final goals = prefs.getStringList(_pendingGoalsKey) ?? const [];
    await prefs.remove(_pendingRouteKey);
    await prefs.remove(_pendingGoalsKey);
    return (goalNames: goals, route: route);
  }

  static Future<void> reset() async {
    _completedCache = false;
    _completedThisSession = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  static Future<void> markKeyboardCompleted() async {
    keyboardCompletedListenable.value = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyboardKey, true);
  }

  static Future<void> resetKeyboard() async {
    keyboardCompletedListenable.value = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyboardKey);
  }
}
