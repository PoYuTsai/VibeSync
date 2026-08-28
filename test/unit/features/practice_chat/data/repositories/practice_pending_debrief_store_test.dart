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

/// 清除後的合約：不是物理刪除，而是保留世代的空 tombstone（防止清除後
/// 舊寫入以較大 revision 復活血統）。「已清除」＝null 或空 context。
bool clearedAppliedHintContext(PracticeAppliedHintContext? context) =>
    context == null || (context.turns.isEmpty && context.latestHint == null);

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
      expect(clearedAppliedHintContext(store.load('sess-hint')), isTrue);
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
      expect(store.load('sess-hint')?.turns, isNotEmpty);
      await store.clearForSession('sess-hint');
      expect(clearedAppliedHintContext(store.load('sess-hint')), isTrue);
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

      // 遷移寫入來自 controller，revision 一定比讀到的舊 context（0）新。
      await store.save(PracticeAppliedHintContext(
        sessionId: sample.sessionId,
        turns: sample.turns,
        latestHint: sample.latestHint,
        revision: 1,
      ));
      expect(box.get(HivePracticeAppliedHintStore.storageKey), isNull);
      expect(store.load('sess-hint')?.turns, hasLength(1));
    });

    test('JSON round-trip preserves revision; legacy payloads default to 0',
        () {
      final versioned = PracticeAppliedHintContext(
        sessionId: 'sess-hint',
        turns: sample.turns,
        revision: 7,
      );
      expect(
        PracticeAppliedHintContext.fromJson(versioned.toJson())?.revision,
        7,
      );
      final legacyJson = sample.toJson()..remove('revision');
      expect(PracticeAppliedHintContext.fromJson(legacyJson)?.revision, 0);
    });

    test('save rejects a stale revision so a late old-controller write '
        'cannot clobber a newer context (in-memory and Hive)', () async {
      Hive.init('./.dart_tool/test_hive_applied_hint_cas');
      final ts = DateTime.now().microsecondsSinceEpoch;
      final box = await Hive.openBox('applied_hint_cas_$ts');
      addTearDown(box.deleteFromDisk);
      final stores = <PracticeAppliedHintStore>[
        InMemoryPracticeAppliedHintStore(),
        HivePracticeAppliedHintStore(() => box),
      ];
      for (final store in stores) {
        final newer = PracticeAppliedHintContext(
          sessionId: 'sess-hint',
          turns: sample.turns,
          revision: 2,
        );
        await store.save(newer);
        // 同 revision 與較舊 revision 都要拒絕。
        await expectLater(
          store.save(const PracticeAppliedHintContext(
            sessionId: 'sess-hint',
            turns: [],
            revision: 2,
          )),
          throwsStateError,
        );
        await expectLater(
          store.save(const PracticeAppliedHintContext(
            sessionId: 'sess-hint',
            turns: [],
            revision: 1,
          )),
          throwsStateError,
        );
        expect(store.load('sess-hint')?.turns, hasLength(1));
        expect(store.load('sess-hint')?.revision, 2);
        // 別的 session 不受影響。
        await store.save(const PracticeAppliedHintContext(
          sessionId: 'sess-other',
          turns: [],
          revision: 1,
        ));
        expect(store.load('sess-other'), isNotNull);
      }
    });

    test('clearForSession with ifRevisionAtMost keeps a newer context '
        'and effective clears leave a generation-preserving tombstone '
        '(in-memory and Hive)', () async {
      Hive.init('./.dart_tool/test_hive_applied_hint_clear');
      final ts = DateTime.now().microsecondsSinceEpoch;
      final box = await Hive.openBox('applied_hint_clear_$ts');
      addTearDown(box.deleteFromDisk);
      final stores = <PracticeAppliedHintStore>[
        InMemoryPracticeAppliedHintStore(),
        HivePracticeAppliedHintStore(() => box),
      ];
      for (final store in stores) {
        await store.save(PracticeAppliedHintContext(
          sessionId: 'sess-hint',
          turns: sample.turns,
          revision: 3,
        ));
        // 舊 controller 視角（revision 2）的守衛清除 → 現存較新，no-op。
        await store.clearForSession('sess-hint', ifRevisionAtMost: 2);
        expect(store.load('sess-hint')?.turns, isNotEmpty);
        // 視角一致（revision 3）→ 清除生效：空 tombstone、revision 前進。
        await store.clearForSession('sess-hint', ifRevisionAtMost: 3);
        final tombstone = store.load('sess-hint');
        expect(clearedAppliedHintContext(tombstone), isTrue);
        expect(tombstone?.revision, 4);
        // 重複清除冪等，不再灌 revision。
        await store.clearForSession('sess-hint');
        expect(store.load('sess-hint')?.revision, 4);
      }
    });

    test('a stale write cannot resurrect lineage after an unconditional clear '
        '(in-memory and Hive)', () async {
      // Codex round-1 review 的反證序列：clear 若物理刪除會讓 revision 歸零，
      // 舊 controller 之後能以較大 revision 復活已清掉的血統。
      Hive.init('./.dart_tool/test_hive_applied_hint_resurrect');
      final ts = DateTime.now().microsecondsSinceEpoch;
      final box = await Hive.openBox('applied_hint_resurrect_$ts');
      addTearDown(box.deleteFromDisk);
      final stores = <PracticeAppliedHintStore>[
        InMemoryPracticeAppliedHintStore(),
        HivePracticeAppliedHintStore(() => box),
      ];
      for (final store in stores) {
        await store.save(PracticeAppliedHintContext(
          sessionId: 'sess-hint',
          turns: sample.turns,
          revision: 10,
        ));
        await store.clearForSession('sess-hint'); // 場次收尾（無條件）
        expect(store.load('sess-hint')?.revision, 11);
        // 舊 controller（清除前視角 10）的晚到還原寫入 → 必須被拒。
        await expectLater(
          store.save(PracticeAppliedHintContext(
            sessionId: 'sess-hint',
            turns: sample.turns,
            revision: 11,
          )),
          throwsStateError,
        );
        expect(clearedAppliedHintContext(store.load('sess-hint')), isTrue);
        // 走正常協定的新 writer（先 load 再 +1）照常寫入。
        final view = store.load('sess-hint')!.revision;
        await store.save(PracticeAppliedHintContext(
          sessionId: 'sess-hint',
          turns: const [
            {'turnIndex': 0, 'type': 'steady', 'originalHintText': '新的一輪', 'sentText': '新的一輪', 'exact': true},
          ],
          revision: view + 1,
        ));
        expect(store.load('sess-hint')?.turns, hasLength(1));
      }
    });

    test('two un-awaited saves settle to the newer revision, and Hive keeps '
        'it across close/reopen', () async {
      Hive.init('./.dart_tool/test_hive_applied_hint_concurrent');
      final ts = DateTime.now().microsecondsSinceEpoch;
      final boxName = 'applied_hint_concurrent_$ts';
      var box = await Hive.openBox(boxName);
      addTearDown(() async {
        if (!box.isOpen) box = await Hive.openBox(boxName);
        await box.deleteFromDisk();
      });
      final stores = <PracticeAppliedHintStore>[
        InMemoryPracticeAppliedHintStore(),
        HivePracticeAppliedHintStore(() => box),
      ];
      for (final store in stores) {
        final first = store.save(PracticeAppliedHintContext(
          sessionId: 'sess-hint',
          turns: sample.turns,
          revision: 1,
        ));
        final second = store.save(const PracticeAppliedHintContext(
          sessionId: 'sess-hint',
          turns: [
            {'turnIndex': 1, 'type': 'warmUp', 'originalHintText': '第二筆', 'sentText': '第二筆', 'exact': true},
          ],
          revision: 2,
        ));
        await Future.wait([first, second]);
        expect(store.load('sess-hint')?.revision, 2);
        expect(store.load('sess-hint')?.turns.single['sentText'], '第二筆');
      }
      // Hive：快取收斂到 revision 2 之外，磁碟也要是 revision 2。
      await box.close();
      box = await Hive.openBox(boxName);
      final reopened = HivePracticeAppliedHintStore(() => box);
      expect(reopened.load('sess-hint')?.revision, 2);
      expect(reopened.load('sess-hint')?.turns.single['sentText'], '第二筆');
    });

    test('unconditional clear on an EMPTY store leaves a generation-1 '
        'tombstone; guarded clear stays a no-op (in-memory and Hive)',
        () async {
      // Codex round-2 P2-1：空 store 不留 tombstone 的話，視角 0 的舊
      // controller 事後仍能以 revision 1 寫進第一代血統。
      Hive.init('./.dart_tool/test_hive_applied_hint_empty_clear');
      final ts = DateTime.now().microsecondsSinceEpoch;
      final box = await Hive.openBox('applied_hint_empty_clear_$ts');
      addTearDown(box.deleteFromDisk);
      final stores = <PracticeAppliedHintStore>[
        InMemoryPracticeAppliedHintStore(),
        HivePracticeAppliedHintStore(() => box),
      ];
      for (final store in stores) {
        // 守衛清除（stale 路徑）在空 store 上不得產生任何寫入。
        await store.clearForSession('sess-hint', ifRevisionAtMost: 5);
        expect(store.load('sess-hint'), isNull);
        // 無條件清除（場次收尾）要留世代 1 tombstone。
        await store.clearForSession('sess-hint');
        expect(store.load('sess-hint')?.revision, 1);
        expect(clearedAppliedHintContext(store.load('sess-hint')), isTrue);
        // 視角 0 的舊 controller 晚到寫入 revision 1 → 拒絕。
        await expectLater(
          store.save(PracticeAppliedHintContext(
            sessionId: 'sess-hint',
            turns: sample.turns,
            revision: 1,
          )),
          throwsStateError,
        );
        expect(clearedAppliedHintContext(store.load('sess-hint')), isTrue);
      }
    });

    test('Hive guard reads fail closed: a transient box error rejects the '
        'write/clear instead of treating the store as empty', () async {
      // Codex round-2 P2-3：load 吞錯回 null 會讓 CAS 與守衛清除 fail open。
      Hive.init('./.dart_tool/test_hive_applied_hint_failclosed');
      final ts = DateTime.now().microsecondsSinceEpoch;
      final box = await Hive.openBox('applied_hint_failclosed_$ts');
      addTearDown(box.deleteFromDisk);
      var failNextOpen = false;
      final store = HivePracticeAppliedHintStore(() {
        if (failNextOpen) {
          failNextOpen = false;
          throw StateError('simulated transient box failure');
        }
        return box;
      });
      await store.save(PracticeAppliedHintContext(
        sessionId: 'sess-hint',
        turns: sample.turns,
        revision: 10,
      ));
      // stale save 在讀取失敗時必須被拒（不是被當成空 store 而落值）。
      failNextOpen = true;
      await expectLater(
        store.save(const PracticeAppliedHintContext(
          sessionId: 'sess-hint',
          turns: [],
          revision: 1,
        )),
        throwsStateError,
      );
      expect(store.load('sess-hint')?.revision, 10);
      expect(store.load('sess-hint')?.turns, isNotEmpty);
      // 守衛清除在讀取失敗時也必須拋出，不得刪掉較新 context。
      failNextOpen = true;
      await expectLater(
        store.clearForSession('sess-hint', ifRevisionAtMost: 2),
        throwsStateError,
      );
      expect(store.load('sess-hint')?.revision, 10);
    });

    test('in-memory store trims sessionId consistently across save/load/clear',
        () async {
      final store = InMemoryPracticeAppliedHintStore();
      await store.save(PracticeAppliedHintContext(
        sessionId: ' sess-hint ',
        turns: sample.turns,
        revision: 1,
      ));
      expect(store.load('sess-hint')?.turns, isNotEmpty);
      // 回傳的 identity 也要正規化——controller restore 比對 sessionId。
      expect(store.load('sess-hint')?.sessionId, 'sess-hint');
      await store.clearForSession(' sess-hint '); // trim 後同一鍵
      expect(clearedAppliedHintContext(store.load('sess-hint')), isTrue);
    });

    test('a present-but-undecodable per-session slot fails closed: save and '
        'clear reject instead of clobbering the unknown generation', () async {
      // Codex round-3：損壞資料的世代未知，把它當成「不存在」等於允許
      // 任意 revision 覆寫。
      Hive.init('./.dart_tool/test_hive_applied_hint_corrupt');
      final ts = DateTime.now().microsecondsSinceEpoch;
      final box = await Hive.openBox('applied_hint_corrupt_$ts');
      addTearDown(box.deleteFromDisk);
      final slot = HivePracticeAppliedHintStore.storageKeyForSession('sess-hint');
      await box.put(slot, '{broken');
      final store = HivePracticeAppliedHintStore(() => box);
      // 公開 load 維持容錯（restore 路徑把它當成沒有血統）。
      expect(store.load('sess-hint'), isNull);
      // 守衛路徑必須拋出，且不得動到原值。
      await expectLater(
        store.save(PracticeAppliedHintContext(
          sessionId: 'sess-hint',
          turns: sample.turns,
          revision: 1,
        )),
        throwsStateError,
      );
      expect(box.get(slot), '{broken');
      await expectLater(
        store.clearForSession('sess-hint', ifRevisionAtMost: 5),
        throwsStateError,
      );
      await expectLater(
        store.clearForSession('sess-hint'),
        throwsStateError,
      );
      expect(box.get(slot), '{broken');
      // 其他 session 不受牽連。
      await store.save(const PracticeAppliedHintContext(
        sessionId: 'sess-other',
        turns: [],
        revision: 1,
      ));
      expect(store.load('sess-other'), isNotNull);
    });

    test('blank sessionId clear is a no-op in both implementations', () async {
      Hive.init('./.dart_tool/test_hive_applied_hint_blank');
      final ts = DateTime.now().microsecondsSinceEpoch;
      final box = await Hive.openBox('applied_hint_blank_$ts');
      addTearDown(box.deleteFromDisk);
      final stores = <PracticeAppliedHintStore>[
        InMemoryPracticeAppliedHintStore(),
        HivePracticeAppliedHintStore(() => box),
      ];
      for (final store in stores) {
        await store.clearForSession('   ');
        expect(store.load(''), isNull);
        expect(store.load('   '), isNull);
      }
      expect(box.isEmpty, isTrue);
    });
  });
}
