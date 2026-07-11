import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/practice_chat/data/repositories/practice_pending_hint_store.dart';

PracticePendingHint samplePending() => const PracticePendingHint(
      sessionId: 'sess-1',
      aiCount: 3,
      requestId: 'req-abc',
    );

void main() {
  group('PracticePendingHint JSON', () {
    test('toJson / fromJson 來回保值', () {
      final back = PracticePendingHint.fromJson(samplePending().toJson());

      expect(back, isNotNull);
      expect(back!.sessionId, 'sess-1');
      expect(back.aiCount, 3);
      expect(back.requestId, 'req-abc');
    });

    test('欄位缺漏或型別不對 → null（當不存在）', () {
      expect(PracticePendingHint.fromJson({}), isNull);
      expect(
        PracticePendingHint.fromJson(
          samplePending().toJson()..remove('requestId'),
        ),
        isNull,
      );
      expect(
        PracticePendingHint.fromJson(
          samplePending().toJson()..['aiCount'] = 'three',
        ),
        isNull,
      );
      expect(
        PracticePendingHint.fromJson(
          samplePending().toJson()..['sessionId'] = '',
        ),
        isNull,
      );
    });
  });

  group('InMemoryPracticePendingHintStore', () {
    test('save → load → clear', () async {
      final store = InMemoryPracticePendingHintStore();
      expect(store.load(), isNull);

      await store.save(samplePending());
      expect(store.load()!.requestId, 'req-abc');

      await store.clear();
      expect(store.load(), isNull);
    });

    test('keeps independent session/turn slots and clears by identity',
        () async {
      final store = InMemoryPracticePendingHintStore();
      await store.save(samplePending());
      await store.save(const PracticePendingHint(
        sessionId: 'sess-2',
        aiCount: 1,
        requestId: 'req-b',
      ));

      expect(
        store.loadFor(sessionId: 'sess-1', aiCount: 3)?.requestId,
        'req-abc',
      );
      expect(
        store.loadFor(sessionId: 'sess-2', aiCount: 1)?.requestId,
        'req-b',
      );
      await store.clearFor(
        sessionId: 'sess-1',
        aiCount: 3,
        requestId: 'wrong-id',
      );
      expect(
        store.loadFor(sessionId: 'sess-1', aiCount: 3)?.requestId,
        'req-abc',
      );
      await store.clearFor(
        sessionId: 'sess-1',
        aiCount: 3,
        requestId: 'req-abc',
      );
      expect(store.loadFor(sessionId: 'sess-1', aiCount: 3), isNull);
      expect(store.loadFor(sessionId: 'sess-2', aiCount: 1), isNotNull);
    });
  });

  group('HivePracticePendingHintStore', () {
    late Box box;

    setUp(() async {
      Hive.init('./.dart_tool/test_hive_pending_hint');
      final ts = DateTime.now().microsecondsSinceEpoch;
      box = await Hive.openBox('pending_hint_$ts');
    });

    tearDown(() async {
      await box.deleteFromDisk();
    });

    test('save 落地 → load 取回同一份', () async {
      final store = HivePracticePendingHintStore(() => box);
      await store.save(samplePending());

      final back = store.load();
      expect(back, isNotNull);
      expect(back!.sessionId, 'sess-1');
      expect(back.aiCount, 3);
      expect(back.requestId, 'req-abc');
    });

    test('A and B persist independently across session switches', () async {
      final store = HivePracticePendingHintStore(() => box);
      await store.save(samplePending());
      await store.save(const PracticePendingHint(
        sessionId: 'sess-2',
        aiCount: 1,
        requestId: 'req-b',
      ));

      expect(
        store.loadFor(sessionId: 'sess-1', aiCount: 3)?.requestId,
        'req-abc',
      );
      expect(
        store.loadFor(sessionId: 'sess-2', aiCount: 1)?.requestId,
        'req-b',
      );
      await store.clearFor(
        sessionId: 'sess-1',
        aiCount: 3,
        requestId: 'req-abc',
      );
      expect(store.loadFor(sessionId: 'sess-1', aiCount: 3), isNull);
      expect(store.loadFor(sessionId: 'sess-2', aiCount: 1), isNotNull);
    });

    test('損毀資料 → load 回 null（不丟例外）', () async {
      await box.put('practice_pending_hint', 'not-json{');
      expect(HivePracticePendingHintStore(() => box).load(), isNull);
    });

    test('clear 後 load 回 null', () async {
      final store = HivePracticePendingHintStore(() => box);
      await store.save(samplePending());
      await store.clear();
      expect(store.load(), isNull);
    });

    test('box getter 丟例外時 load/clear fail-open，但 save 回報 durability failure',
        () async {
      final store = HivePracticePendingHintStore(
        () => throw HiveError('Box not found'),
      );
      expect(store.load(), isNull);
      await expectLater(
        store.save(samplePending()),
        throwsA(isA<HiveError>()),
      );
      await store.clear();
    });
  });
}
