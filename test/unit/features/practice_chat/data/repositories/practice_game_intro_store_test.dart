import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/features/practice_chat/data/repositories/practice_game_intro_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InMemoryPracticeGameIntroStore', () {
    test('預設未看過；markSeen 後為看過；reset 清回未看過', () async {
      final store = InMemoryPracticeGameIntroStore();
      expect(await store.isSeen(), isFalse);

      await store.markSeen();
      expect(await store.isSeen(), isTrue);

      await store.reset();
      expect(await store.isSeen(), isFalse);
    });

    test('seed seen=true 直接回看過', () async {
      final store = InMemoryPracticeGameIntroStore(seen: true);
      expect(await store.isSeen(), isTrue);
    });
  });

  group('SharedPrefsPracticeGameIntroStore', () {
    test('markSeen 寫入 practice_game_intro_seen_v1；reset 移除', () async {
      SharedPreferences.setMockInitialValues({});
      final store = SharedPrefsPracticeGameIntroStore();
      expect(await store.isSeen(), isFalse);

      await store.markSeen();
      expect(await store.isSeen(), isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getBool(SharedPrefsPracticeGameIntroStore.storageKey),
        isTrue,
      );

      await store.reset();
      expect(await store.isSeen(), isFalse);
      expect(
        prefs.containsKey(SharedPrefsPracticeGameIntroStore.storageKey),
        isFalse,
      );
    });

    test('既有旗標存在時 isSeen 直接回 true', () async {
      SharedPreferences.setMockInitialValues({
        SharedPrefsPracticeGameIntroStore.storageKey: true,
      });
      expect(await SharedPrefsPracticeGameIntroStore().isSeen(), isTrue);
    });
  });
}
