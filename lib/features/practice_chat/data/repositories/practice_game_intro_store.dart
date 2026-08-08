import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Game 模式教學卡的一次性旗標。仿 OnboardingService 的 SharedPreferences
/// pattern，但不進 router redirect，不需要同步 cache——單純 async 讀寫即可。
abstract class PracticeGameIntroStore {
  Future<bool> isSeen();
  Future<void> markSeen();
  Future<void> reset();
}

class SharedPrefsPracticeGameIntroStore implements PracticeGameIntroStore {
  static const String storageKey = 'practice_game_intro_seen_v1';

  @override
  Future<bool> isSeen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(storageKey) ?? false;
  }

  @override
  Future<void> markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(storageKey, true);
  }

  @override
  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(storageKey);
  }
}

/// 測試／無持久化情境用的記憶體版本。
class InMemoryPracticeGameIntroStore implements PracticeGameIntroStore {
  InMemoryPracticeGameIntroStore({bool seen = false}) : _seen = seen;

  bool _seen;

  @override
  Future<bool> isSeen() async => _seen;

  @override
  Future<void> markSeen() async => _seen = true;

  @override
  Future<void> reset() async => _seen = false;
}

final practiceGameIntroStoreProvider = Provider<PracticeGameIntroStore>(
  (ref) => SharedPrefsPracticeGameIntroStore(),
);
