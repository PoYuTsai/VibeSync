import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/practice_chat/data/repositories/practice_pending_draw_store.dart';

PracticePendingDraw samplePending() => const PracticePendingDraw(
      currentProfileId: 'practice_girl_007',
      requestId: 'req-abc',
    );

void main() {
  group('PracticePendingDraw JSON', () {
    test('toJson / fromJson 來回保值', () {
      final back = PracticePendingDraw.fromJson(samplePending().toJson());

      expect(back, isNotNull);
      expect(back!.currentProfileId, 'practice_girl_007');
      expect(back.requestId, 'req-abc');
    });

    test('首抽（currentProfileId=null）來回保值', () {
      const firstDraw = PracticePendingDraw(
        currentProfileId: null,
        requestId: 'req-first',
      );
      final back = PracticePendingDraw.fromJson(firstDraw.toJson());

      expect(back, isNotNull);
      expect(back!.currentProfileId, isNull);
      expect(back.requestId, 'req-first');
    });

    test('欄位缺漏或型別不對 → null（當不存在）', () {
      expect(PracticePendingDraw.fromJson({}), isNull);
      expect(
        PracticePendingDraw.fromJson(
          samplePending().toJson()..remove('requestId'),
        ),
        isNull,
      );
      expect(
        PracticePendingDraw.fromJson(
          samplePending().toJson()..['requestId'] = '',
        ),
        isNull,
      );
      expect(
        PracticePendingDraw.fromJson(
          samplePending().toJson()..['currentProfileId'] = 42,
        ),
        isNull,
      );
    });
  });

  group('InMemoryPracticePendingDrawStore', () {
    test('save → load → clear', () async {
      final store = InMemoryPracticePendingDrawStore();
      expect(store.load(), isNull);

      await store.save(samplePending());
      expect(store.load()!.requestId, 'req-abc');

      await store.clear();
      expect(store.load(), isNull);
    });
  });

  group('HivePracticePendingDrawStore', () {
    late Box box;

    setUp(() async {
      Hive.init('./.dart_tool/test_hive_pending_draw');
      final ts = DateTime.now().microsecondsSinceEpoch;
      box = await Hive.openBox('pending_draw_$ts');
    });

    tearDown(() async {
      await box.deleteFromDisk();
    });

    test('save 落地 → load 取回同一份', () async {
      final store = HivePracticePendingDrawStore(() => box);
      await store.save(samplePending());

      final back = store.load();
      expect(back, isNotNull);
      expect(back!.currentProfileId, 'practice_girl_007');
      expect(back.requestId, 'req-abc');
    });

    test('損毀資料 → load 回 null（不丟例外）', () async {
      await box.put('practice_pending_draw', 'not-json{');
      expect(HivePracticePendingDrawStore(() => box).load(), isNull);
    });

    test('clear 後 load 回 null', () async {
      final store = HivePracticePendingDrawStore(() => box);
      await store.save(samplePending());
      await store.clear();
      expect(store.load(), isNull);
    });

    test('box getter 丟例外（box 沒開）→ load/save/clear 全 no-op 不丟例外',
        () async {
      final store = HivePracticePendingDrawStore(
        () => throw HiveError('Box not found'),
      );
      expect(store.load(), isNull);
      await store.save(samplePending());
      await store.clear();
    });
  });
}
