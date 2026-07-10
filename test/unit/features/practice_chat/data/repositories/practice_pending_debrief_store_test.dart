import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/practice_chat/data/repositories/practice_pending_debrief_store.dart';

const _digest =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

PracticePendingDebrief samplePending() => const PracticePendingDebrief(
      sessionId: 'sess-1',
      payloadDigest: _digest,
      requestId: 'req-abc',
    );

void main() {
  group('PracticePendingDebrief JSON', () {
    test('toJson / fromJson round-trip keeps only ids and SHA-256 digest', () {
      final json = samplePending().toJson();
      final back = PracticePendingDebrief.fromJson(json);

      expect(
          json.keys, containsAll(['sessionId', 'payloadDigest', 'requestId']));
      expect(json.keys, hasLength(3));
      expect(back, isNotNull);
      expect(back!.sessionId, 'sess-1');
      expect(back.payloadDigest, _digest);
      expect(back.requestId, 'req-abc');
    });

    test('missing fields or invalid digest fail closed', () {
      expect(PracticePendingDebrief.fromJson({}), isNull);
      expect(
        PracticePendingDebrief.fromJson(
          samplePending().toJson()..['payloadDigest'] = 'not-a-digest',
        ),
        isNull,
      );
      expect(
        PracticePendingDebrief.fromJson(
          samplePending().toJson()..['payloadDigest'] = ''.padRight(64, 'Z'),
        ),
        isNull,
      );
      expect(
        PracticePendingDebrief.fromJson(
          samplePending().toJson()..['requestId'] = '',
        ),
        isNull,
      );
    });
  });

  group('InMemoryPracticePendingDebriefStore', () {
    test('save → load → clear', () async {
      final store = InMemoryPracticePendingDebriefStore();
      expect(store.load(), isNull);
      await store.save(samplePending());
      expect(store.load()!.requestId, 'req-abc');
      await store.clear();
      expect(store.load(), isNull);
    });
  });

  group('HivePracticePendingDebriefStore', () {
    late Box box;

    setUp(() async {
      Hive.init('./.dart_tool/test_hive_pending_debrief');
      final ts = DateTime.now().microsecondsSinceEpoch;
      box = await Hive.openBox('pending_debrief_$ts');
    });

    tearDown(() async {
      await box.deleteFromDisk();
    });

    test('save/load round-trip and raw JSON contains no transcript', () async {
      final store = HivePracticePendingDebriefStore(() => box);
      await store.save(samplePending());

      final raw = box.get(HivePracticePendingDebriefStore.storageKey);
      expect(raw, isA<String>());
      expect(raw as String, isNot(contains('SECRET_TRANSCRIPT')));
      expect(raw, isNot(contains('memorySummary')));
      expect(raw, isNot(contains('appliedHintTurns')));
      expect(store.load()!.payloadDigest, _digest);
    });

    test('corrupted data loads as absent', () async {
      await box.put(
        HivePracticePendingDebriefStore.storageKey,
        'not-json{',
      );
      expect(HivePracticePendingDebriefStore(() => box).load(), isNull);
    });

    test('clear removes the pending snapshot', () async {
      final store = HivePracticePendingDebriefStore(() => box);
      await store.save(samplePending());
      await store.clear();
      expect(store.load(), isNull);
    });

    test('unavailable box is fail-open for load/save/clear', () async {
      final store = HivePracticePendingDebriefStore(
        () => throw HiveError('Box not found'),
      );
      expect(store.load(), isNull);
      await store.save(samplePending());
      await store.clear();
    });
  });
}
