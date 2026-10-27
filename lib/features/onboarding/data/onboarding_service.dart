// lib/features/onboarding/data/onboarding_service.dart
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/onboarding_intent.dart';

/// 登入前完成 onboarding 時暫存的交接，登入後由 MainShell 的
/// OnboardingHandoffApplier 套用（種目標、導到第 1 頁選的地方）。
///
/// onboarding 轉換第 12 步起存成一份有版本號的 JSON；第 12 步以前的版本存在
/// 兩個舊鍵、只有目標與目的地，讀回來時 [intent]、[quizCorrect]、[stashedAt]
/// 都是 null。
@immutable
class OnboardingHandoff {
  const OnboardingHandoff({
    required this.route,
    this.intent,
    this.goalNames = const [],
    this.quizCorrect,
    this.stashedAt,
  });

  /// 第 1 頁選的路徑；舊鍵沒有。
  final OnboardingIntent? intent;

  /// 登入後要 push 的目的地，原樣保存（含 query，例如 `?next=screenshot`）。
  final String route;

  /// 第 3 頁選的目標（`PracticeGoal.name`）。
  final List<String> goalNames;

  /// 第 2 頁那一題答對沒有；null＝沒作答（按了「直接開始」，或舊鍵）。
  final bool? quizCorrect;

  /// 暫存的時間（UTC）；舊鍵沒有。
  final DateTime? stashedAt;
}

class OnboardingService {
  // 這個鍵不能改名：改了會把已經登入、看過 onboarding 的舊用戶強制拉回 onboarding。
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

  /// 交接暫存的鍵（onboarding 轉換第 12 步）：一份 JSON，格式見
  /// [stashPendingHandoff]。
  @visibleForTesting
  static const pendingHandoffKey = 'onboarding_pending_handoff';

  /// 暫存 JSON 的版本號。讀到別的版本當作讀不懂：清掉、不套用。
  @visibleForTesting
  static const pendingHandoffVersion = 2;

  /// 第 12 步以前的兩個鍵（版本 1）：讀得到就照舊套用，清除時一起清。
  @visibleForTesting
  static const legacyPendingGoalsKey = 'onboarding_pending_goals';
  @visibleForTesting
  static const legacyPendingRouteKey = 'onboarding_pending_route';

  /// 暫存超過這麼久就不套用、直接清掉：太久以前的可能是別人用這支手機時
  /// 留下的（跟登入前事件佇列的 7 天同一個理由，FunnelTracker.pendingMaxAge），
  /// 也讓「套用成功才清除」有上限，一直套用不成功的暫存不會永遠留著。
  /// 舊鍵沒有時間，照舊套用。
  static const pendingHandoffMaxAge = Duration(days: 7);

  // 同一時間只套用一份：讀取到清除之間有 await，MainShell 重建時再掛一次
  // applier 也不會把同一份暫存套用兩次（導兩次頁）。
  static Future<void>? _applyingHandoff;

  /// 登入前完成 onboarding 時暫存交接（2026-08-18：onboarding 移到登入前）。
  ///
  /// 存成一份有版本號的 JSON：`version`、第 1 頁的路徑 `intent`、登入後要去的
  /// `route`、第 3 頁的目標 `goals`、第 2 頁答對沒有 `quizCorrect`（沒作答是
  /// null）、暫存時間 `stashedAt`（UTC ISO 8601）。舊鍵若還在一起清掉，免得
  /// 套用兩次。
  static Future<void> stashPendingHandoff({
    required OnboardingIntent intent,
    required String route,
    required List<String> goalNames,
    required bool? quizCorrect,
    DateTime? now,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      pendingHandoffKey,
      jsonEncode(<String, Object?>{
        'version': pendingHandoffVersion,
        'intent': intent.wire,
        'route': route,
        'goals': goalNames,
        'quizCorrect': quizCorrect,
        'stashedAt': (now ?? DateTime.now()).toUtc().toIso8601String(),
      }),
    );
    await prefs.remove(legacyPendingRouteKey);
    await prefs.remove(legacyPendingGoalsKey);
  }

  /// 讀暫存，不清除。沒有暫存回 null；新格式讀不懂（壞掉、版本不對）或過期的
  /// 永遠套用不了，順手清掉再回 null。沒有新格式時讀舊鍵。
  static Future<OnboardingHandoff?> readPendingHandoff({DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(pendingHandoffKey)) {
      final handoff = _parseHandoff(
        prefs.get(pendingHandoffKey),
        now: now ?? DateTime.now(),
      );
      if (handoff != null) return handoff;
      await clearPendingHandoff();
      return null;
    }
    final route = prefs.get(legacyPendingRouteKey);
    if (route is! String) return null;
    final goals = prefs.get(legacyPendingGoalsKey);
    return OnboardingHandoff(
      route: route,
      goalNames: goals is List
          ? goals.whereType<String>().toList(growable: false)
          : const [],
    );
  }

  /// 清掉暫存（新格式與舊鍵）。只在套用成功之後呼叫。
  static Future<void> clearPendingHandoff() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(pendingHandoffKey);
    await prefs.remove(legacyPendingRouteKey);
    await prefs.remove(legacyPendingGoalsKey);
  }

  /// 讀取 → 套用 → 確認成功才清除（onboarding 轉換第 12 步）。
  ///
  /// [apply] 回 true＝已經套用（導頁做完）才清掉暫存；回 false 或丟錯＝這次沒
  /// 套用，暫存留著，下次進首頁再試（過期前）。同一時間只跑一份，第二個呼叫
  /// 等同一份結果、不會再套用一次。沒有暫存時什麼都不做。
  static Future<void> applyPendingHandoff(
    Future<bool> Function(OnboardingHandoff handoff) apply, {
    DateTime? now,
  }) =>
      _applyingHandoff ??= _applyPendingHandoffOnce(apply, now: now)
          .whenComplete(() => _applyingHandoff = null);

  static Future<void> _applyPendingHandoffOnce(
    Future<bool> Function(OnboardingHandoff handoff) apply, {
    DateTime? now,
  }) async {
    try {
      final handoff = await readPendingHandoff(now: now);
      if (handoff == null) return;
      if (await apply(handoff)) await clearPendingHandoff();
    } catch (e) {
      debugPrint('[OnboardingService] 交接沒套用成功，暫存留著下次再試：$e');
    }
  }

  static OnboardingHandoff? _parseHandoff(
    Object? raw, {
    required DateTime now,
  }) {
    if (raw is! String) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['version'] != pendingHandoffVersion) {
        return null;
      }
      final route = decoded['route'];
      final stashedAtRaw = decoded['stashedAt'];
      if (route is! String || !route.startsWith('/')) return null;
      if (stashedAtRaw is! String) return null;
      final stashedAt = DateTime.tryParse(stashedAtRaw)?.toUtc();
      if (stashedAt == null) return null;
      // 時鐘被調過、跑到未來的也一樣看差距（同登入前事件佇列）。
      if (now.toUtc().difference(stashedAt).abs() > pendingHandoffMaxAge) {
        return null;
      }
      final goals = decoded['goals'];
      final quizCorrect = decoded['quizCorrect'];
      return OnboardingHandoff(
        intent: OnboardingIntent.fromWire(decoded['intent']),
        route: route,
        goalNames: goals is List
            ? goals.whereType<String>().toList(growable: false)
            : const [],
        quizCorrect: quizCorrect is bool ? quizCorrect : null,
        stashedAt: stashedAt,
      );
    } catch (_) {
      return null;
    }
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
