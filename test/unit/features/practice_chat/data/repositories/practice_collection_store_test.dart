import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/practice_chat/data/repositories/practice_collection_store.dart';

void main() {
  group('InMemoryPracticeCollectionStore', () {
    test('add → load 累積；重複 add 不重複', () async {
      final store = InMemoryPracticeCollectionStore();
      expect(store.load(), isEmpty);

      await store.add('practice_girl_001');
      await store.add('practice_girl_002');
      await store.add('practice_girl_001');

      expect(store.load(), {'practice_girl_001', 'practice_girl_002'});
    });

    test('空白 profileId 護欄：不寫入', () async {
      final store = InMemoryPracticeCollectionStore();
      await store.add('');
      expect(store.load(), isEmpty);
    });
  });

  group('HivePracticeCollectionStore', () {
    late Box box;

    setUp(() async {
      Hive.init('./.dart_tool/test_hive_collection');
      final ts = DateTime.now().microsecondsSinceEpoch;
      box = await Hive.openBox('collection_$ts');
    });

    tearDown(() async {
      await box.deleteFromDisk();
    });

    test('add 落地 → 新 store 實例 load 取回同一份（持久化）', () async {
      final store = HivePracticeCollectionStore(box);
      await store.add('practice_girl_007');
      await store.add('practice_girl_012');

      final reloaded = HivePracticeCollectionStore(box).load();
      expect(reloaded, {'practice_girl_007', 'practice_girl_012'});
    });

    test('重複 add 不重複、空白 id 不寫入', () async {
      final store = HivePracticeCollectionStore(box);
      await store.add('practice_girl_007');
      await store.add('practice_girl_007');
      await store.add('');

      expect(store.load(), {'practice_girl_007'});
      final raw = box.get(HivePracticeCollectionStore.storageKey) as String;
      expect((jsonDecode(raw) as List).length, 1);
    });

    test('壞 JSON → load 回空集合（不丟例外）', () async {
      await box.put(HivePracticeCollectionStore.storageKey, 'not-json{');
      expect(HivePracticeCollectionStore(box).load(), isEmpty);
    });

    test('JSON 形狀不是 list → 回空集合；混入非字串項被過濾', () async {
      await box.put(
          HivePracticeCollectionStore.storageKey, jsonEncode({'a': 1}));
      expect(HivePracticeCollectionStore(box).load(), isEmpty);

      await box.put(HivePracticeCollectionStore.storageKey,
          jsonEncode(['practice_girl_001', 3, null, '']));
      expect(HivePracticeCollectionStore(box).load(), {'practice_girl_001'});
    });

    test('壞 JSON 之後 add 仍可自癒重建', () async {
      await box.put(HivePracticeCollectionStore.storageKey, 'not-json{');
      final store = HivePracticeCollectionStore(box);
      await store.add('practice_girl_003');
      expect(store.load(), {'practice_girl_003'});
    });
  });
}
