// lib/features/onboarding/data/onboarding_service.dart
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingService {
  static const _key = 'onboarding_completed';

  // In-memory mirror of the persisted flag. The router redirect is synchronous
  // and must not await storage on every navigation, so it reads this cache via
  // [isCompletedSync]. Primed by [load] at startup; kept in sync by
  // [markCompleted] / [reset].
  static bool _completedCache = false;

  /// Synchronous completion state for the router redirect.
  static bool get isCompletedSync => _completedCache;

  /// Loads the persisted flag into the in-memory cache. Must run during app
  /// startup before the router first evaluates redirects, otherwise a returning
  /// user who already finished onboarding could be misrouted back to it.
  static Future<bool> load() async {
    final prefs = await SharedPreferences.getInstance();
    _completedCache = prefs.getBool(_key) ?? false;
    return _completedCache;
  }

  static Future<bool> isCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    _completedCache = prefs.getBool(_key) ?? false;
    return _completedCache;
  }

  static Future<void> markCompleted() async {
    // Flip the cache synchronously so the redirect fired by the immediate
    // post-completion context.go('/') already observes completion.
    _completedCache = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
  }

  static Future<void> reset() async {
    _completedCache = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
