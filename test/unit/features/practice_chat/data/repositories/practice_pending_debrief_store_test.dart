import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/practice_chat/data/repositories/practice_pending_debrief_store.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_hint.dart';

const _digest =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const _digestB =
    'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';

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

    test('keeps independent session/payload intents', () async {
      final store = InMemoryPracticePendingDebriefStore();
      await store.save(samplePending());
      await store.save(const PracticePendingDebrief(
        sessionId: 'sess-2',
        payloadDigest: _digestB,
        requestId: 'req-b',
      ));

      expect(
        store.loadFor(sessionId: 'sess-1', payloadDigest: _digest)?.requestId,
        'req-abc',
      );
      expect(
        store.loadFor(sessionId: 'sess-2', payloadDigest: _digestB)?.requestId,
        'req-b',
      );
      await store.clearFor(samplePending());
      expect(
        store.loadFor(sessionId: 'sess-1', payloadDigest: _digest),
        isNull,
      );
      expect(
        store.loadFor(sessionId: 'sess-2', payloadDigest: _digestB),
        isNotNull,
      );
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

    test('A and B survive independently and clear is identity-scoped',
        () async {
      final store = HivePracticePendingDebriefStore(() => box);
      await store.save(samplePending());
      await store.save(const PracticePendingDebrief(
        sessionId: 'sess-2',
        payloadDigest: _digestB,
        requestId: 'req-b',
      ));

      expect(
        store.loadFor(sessionId: 'sess-1', payloadDigest: _digest)?.requestId,
        'req-abc',
      );
      expect(
        store.loadFor(sessionId: 'sess-2', payloadDigest: _digestB)?.requestId,
        'req-b',
      );
      await store.clearFor(samplePending());
      expect(
        store.loadFor(sessionId: 'sess-1', payloadDigest: _digest),
        isNull,
      );
      expect(
        store.loadFor(sessionId: 'sess-2', payloadDigest: _digestB),
        isNotNull,
      );
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

    test('unavailable box fails save closed but load/clear remain tolerant',
        () async {
      final store = HivePracticePendingDebriefStore(
        () => throw HiveError('Box not found'),
      );
      expect(store.load(), isNull);
      await expectLater(store.save(samplePending()), throwsA(isA<HiveError>()));
      await store.clear();
    });
  });

  group('PracticeAppliedHintContext', () {
    const latestHint = PracticeSuccessfulHintSnapshot(
      aiCount: 3,
      requestId: 'hint-req-2',
      qualitySchemaVersion: kPracticeHintQualitySchemaVersion,
      result: PracticeHintResult(
        replies: [
          PracticeHintReply(
            type: PracticeHintReplyType.warmUp,
            label: '升溫回覆',
            text: '你這個酒吧雷達是只對有故事的店有效嗎？',
            hintRequestId: 'hint-req-2',
            decision: PracticeHintDecision(
              phase: '建立互動',
              targetVariable: '投入感',
              move: '用 callback 延伸她的品味',
              rationale: '讓她補充自己的判斷，形成有來有往',
              inviteRoute: 'hold',
            ),
          ),
          PracticeHintReply(
            type: PracticeHintReplyType.steady,
            label: '穩住回覆',
            text: '我會先記住這間，之後再跟你交換我的口袋名單。',
            hintRequestId: 'hint-req-2',
            decision: PracticeHintDecision(
              phase: '價值交換',
              targetVariable: '共同感',
              move: '分享自己的口袋名單作為交換',
              rationale: '不是只向她索取資訊，也讓她看見你的生活',
              inviteRoute: 'soft_invite',
            ),
          ),
        ],
        coaching: '一則拉高投入，一則穩住交換感。',
        costDeducted: 1,
        hintUsedCount: 2,
        monthlyRemaining: 18,
        dailyRemaining: 7,
        qualitySchemaVersion: kPracticeHintQualitySchemaVersion,
      ),
    );
    final sample = PracticeAppliedHintContext(
      sessionId: 'sess-hint',
      turns: const [
        {
          'turnIndex': 2,
          'type': 'steady',
          'originalHintText': '先接住她的情緒',
          'sentText': '先接住她的情緒',
          'exact': true,
          'hintRequestId': 'hint-req-1',
          'decision': {
            'phase': '建立互動',
            'move': '情緒承接',
          },
        },
      ],
      latestHint: latestHint,
    );

    test('JSON round-trip preserves applied turns and complete Hint envelope',
        () {
      final back = PracticeAppliedHintContext.fromJson(sample.toJson());
      expect(back?.sessionId, 'sess-hint');
      expect(back?.turns, hasLength(1));
      expect(back?.turns.first['hintRequestId'], 'hint-req-1');
      expect(back?.turns.first['decision']['move'], '情緒承接');
      expect(back?.latestHint?.aiCount, 3);
      expect(back?.latestHint?.requestId, 'hint-req-2');
      expect(back?.latestHint?.result.replies, hasLength(2));
      expect(
        back?.latestHint?.result.replies.first.decision?.move,
        '用 callback 延伸她的品味',
      );
      expect(
        back?.latestHint?.result.replies.last.decision?.inviteRoute,
        'soft_invite',
      );
      expect(back?.latestHint?.result.monthlyRemaining, 18);
      expect(back?.latestHint?.result.dailyRemaining, 7);
      expect(back?.latestHint?.qualitySchemaVersion,
          kPracticeHintQualitySchemaVersion);
      expect(back?.latestHint?.isRestorable, true);
    });

    test('old Hint snapshots keep replay identity but are not restorable', () {
      final legacyJson = sample.toJson();
      final latest = legacyJson['latestHint']! as Map<String, dynamic>;
      latest.remove('qualitySchemaVersion');
      (latest['result']! as Map<String, dynamic>)
          .remove('qualitySchemaVersion');

      final back = PracticeAppliedHintContext.fromJson(legacyJson);

      expect(back?.latestHint?.requestId, 'hint-req-2');
      expect(back?.latestHint?.qualitySchemaVersion, isNull);
      expect(back?.latestHint?.result.qualitySchemaVersion, isNull);
      expect(back?.latestHint?.isRestorable, false);
    });

    test('unknown Hint snapshot versions are not restorable', () {
      final unknownJson = sample.toJson();
      final latest = unknownJson['latestHint']! as Map<String, dynamic>;
      latest['qualitySchemaVersion'] = 'string-heuristics-v0';
      (latest['result']! as Map<String, dynamic>)['qualitySchemaVersion'] =
          'string-heuristics-v0';

      final back = PracticeAppliedHintContext.fromJson(unknownJson);

      expect(back?.latestHint?.requestId, 'hint-req-2');
      expect(back?.latestHint?.isRestorable, false);
    });

    test('in-memory store keeps A and B independently across A -> B -> A',
        () async {
      final store = InMemoryPracticeAppliedHintStore();
      await store.save(sample);
      await store.save(const PracticeAppliedHintContext(
        sessionId: 'sess-b',
        turns: [],
      ));
      await store.clearForSession('another-session');
      expect(store.load('sess-hint')?.latestHint?.aiCount, 3);
      expect(store.load('sess-b')?.sessionId, 'sess-b');
      await store.clearForSession('sess-hint');
      expect(store.load('sess-hint'), isNull);
      expect(store.load('sess-b'), isNotNull);
    });

    test('Hive JSON uses per-session keys and needs no type adapter', () async {
      Hive.init('./.dart_tool/test_hive_applied_hint');
      final ts = DateTime.now().microsecondsSinceEpoch;
      final box = await Hive.openBox('applied_hint_$ts');
      addTearDown(box.deleteFromDisk);
      final store = HivePracticeAppliedHintStore(() => box);

      await store.save(sample);
      await store.save(const PracticeAppliedHintContext(
        sessionId: 'sess-b',
        turns: [],
      ));

      final raw = box.get(
        HivePracticeAppliedHintStore.storageKeyForSession('sess-hint'),
      );
      expect(raw, isA<String>());
      expect(
        store.load('sess-hint')?.turns.first['hintRequestId'],
        'hint-req-1',
      );
      expect(store.load('sess-b'), isNotNull);
      await store.clearForSession('another-session');
      expect(store.load('sess-hint'), isNotNull);
      await store.clearForSession('sess-hint');
      expect(store.load('sess-hint'), isNull);
      expect(store.load('sess-b'), isNotNull);
    });

    test('Hive load reads the legacy single-slot key for matching session',
        () async {
      Hive.init('./.dart_tool/test_hive_applied_hint_legacy');
      final ts = DateTime.now().microsecondsSinceEpoch;
      final box = await Hive.openBox('applied_hint_legacy_$ts');
      addTearDown(box.deleteFromDisk);
      await box.put(
        HivePracticeAppliedHintStore.storageKey,
        jsonEncode(sample.toJson()),
      );

      final store = HivePracticeAppliedHintStore(() => box);
      expect(store.load('sess-hint')?.latestHint?.aiCount, 3);
      expect(store.load('sess-b'), isNull);

      await store.save(sample);
      expect(box.get(HivePracticeAppliedHintStore.storageKey), isNull);
      expect(store.load('sess-hint')?.turns, hasLength(1));
    });
  });
}
