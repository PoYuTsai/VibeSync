import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/analysis/data/services/optimize_message_request_session.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/features/conversation/domain/entities/session_context.dart';

const _ownerA = '11111111-1111-4111-8111-111111111111';
const _ownerB = '22222222-2222-4222-8222-222222222222';

Message _message(String content, {bool isFromMe = false}) => Message(
      id: content,
      content: content,
      isFromMe: isFromMe,
      timestamp: DateTime.utc(2026, 7, 16),
    );

class _FailingSaveStore extends InMemoryOptimizeMessagePendingRequestStore {
  @override
  Future<void> save(OptimizeMessagePendingRequest pending) {
    throw StateError('disk unavailable');
  }
}

void main() {
  group('OptimizeMessageRequestIdSession', () {
    test('付費結果在方案變動後仍可用同一個 requestId 取回', () async {
      final session = OptimizeMessageRequestIdSession();
      final paidButResponseLost = await session.beginAttempt(
        ownerUserId: _ownerA,
        fingerprint: 'charged-response-lost',
      );
      final restoredAfterDowngrade = await session.findPending(
        ownerUserId: _ownerA,
        fingerprint: 'charged-response-lost',
      );
      expect(restoredAfterDowngrade?.requestId, paidButResponseLost.requestId);
    });

    test('same payload retry reuses its UUID until success', () async {
      final session = OptimizeMessageRequestIdSession();
      final fingerprint = OptimizeMessageRequestIdSession.fingerprintFor(
        messages: [_message('最近有空嗎？')],
        userDraft: '要不要喝咖啡',
      );

      final first = await session.beginAttempt(
        ownerUserId: _ownerA,
        fingerprint: fingerprint,
      );
      final retry = await session.beginAttempt(
        ownerUserId: _ownerA,
        fingerprint: fingerprint,
      );

      expect(retry.requestId, first.requestId);
      expect(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        ).hasMatch(first.requestId),
        isTrue,
      );
    });

    test('new screen and app session restore the durable UUID', () async {
      final store = InMemoryOptimizeMessagePendingRequestStore();
      final firstScreen = OptimizeMessageRequestIdSession(store: store);
      final rebuiltScreen = OptimizeMessageRequestIdSession(store: store);

      final first = await firstScreen.beginAttempt(
        ownerUserId: _ownerA,
        fingerprint: 'same-wire-payload',
      );
      final restored = await rebuiltScreen.beginAttempt(
        ownerUserId: _ownerA,
        fingerprint: 'same-wire-payload',
      );

      expect(restored.requestId, first.requestId);
    });

    test('same device never shares request identity across accounts', () async {
      final store = InMemoryOptimizeMessagePendingRequestStore();
      final session = OptimizeMessageRequestIdSession(store: store);

      final first = await session.beginAttempt(
        ownerUserId: _ownerA,
        fingerprint: 'same-wire-payload',
      );
      final otherAccount = await session.beginAttempt(
        ownerUserId: _ownerB,
        fingerprint: 'same-wire-payload',
      );

      expect(otherAccount.requestId, isNot(first.requestId));
    });

    test('changed wire input rotates the UUID', () async {
      final session = OptimizeMessageRequestIdSession();
      final first = await session.beginAttempt(
        ownerUserId: _ownerA,
        fingerprint: OptimizeMessageRequestIdSession.fingerprintFor(
          messages: [_message('最近有空嗎？')],
          userDraft: '要不要喝咖啡',
        ),
      );
      final changed = await session.beginAttempt(
        ownerUserId: _ownerA,
        fingerprint: OptimizeMessageRequestIdSession.fingerprintFor(
          messages: [_message('最近有空嗎？')],
          userDraft: '要不要吃飯',
        ),
      );

      expect(changed.requestId, isNot(first.requestId));
    });

    test('fingerprint follows the trimmed wire representation', () {
      final first = OptimizeMessageRequestIdSession.fingerprintFor(
        messages: [
          Message(
            id: '1',
            content: '嗨',
            isFromMe: false,
            timestamp: DateTime.utc(2026, 7, 16),
            quotedReplyPreview: '  前一句  ',
            quotedReplyPreviewIsFromMe: true,
          ),
        ],
        userDraft: '  要不要喝咖啡  ',
        conversationSummary: '  剛認識  ',
      );
      final sameWire = OptimizeMessageRequestIdSession.fingerprintFor(
        messages: [
          Message(
            id: '2',
            content: '嗨',
            isFromMe: false,
            timestamp: DateTime.utc(2026, 7, 17),
            quotedReplyPreview: '前一句',
            quotedReplyPreviewIsFromMe: true,
          ),
        ],
        userDraft: '要不要喝咖啡',
        conversationSummary: '剛認識',
      );

      expect(sameWire, first);
    });

    // 這兩條金值是 2026-07-29 加入 refineInstruction 之前跑出來的實際值。
    // 沒帶指令的請求，fingerprint 必須與當天 byte-identical，否則部署當下
    // 7 天窗內所有未結算的 pending 都會變成 replay mismatch，使用者拿不回
    // 已經付過錢的結果。shape 測試擋不住 normalizedOptional 之類的正規化
    // 行為被改動，所以這裡鎖的是寫死的 64 位十六進位值。
    test('legacy fingerprint digest is byte-identical to 2026-07-28', () {
      const legacyFullDigest =
          '46e0acc79337ce3605b7a064852c8707ddec66fc43855660225ccb21b6358f3f';
      const legacyMinimalDigest =
          '6bf6a2fd087afe8d35f635143bf802ffc76056558448964f6ceff253a62e338d';

      final full = OptimizeMessageRequestIdSession.fingerprintFor(
        messages: [
          Message(
            id: '1',
            content: '嗨，週末有空嗎？',
            isFromMe: false,
            timestamp: DateTime.utc(2026, 7, 16),
            quotedReplyPreview: '前一句',
            quotedReplyPreviewIsFromMe: true,
          ),
          Message(
            id: '2',
            content: '看情況欸',
            isFromMe: true,
            timestamp: DateTime.utc(2026, 7, 16),
          ),
        ],
        userDraft: '要不要一起去看展',
        sessionContext: SessionContext(
          meetingContext: MeetingContext.datingApp,
          duration: AcquaintanceDuration.fewWeeks,
          goal: UserGoal.dateInvite,
          analysisContextNote: '她剛換工作',
        ),
        conversationSummary: '剛認識兩週',
        partnerSummary: '喜歡藝術',
        effectiveStyleContext: '幽默但不油',
        knownContactName: '小美',
      );
      final minimal = OptimizeMessageRequestIdSession.fingerprintFor(
        messages: [_message('嗨')],
        userDraft: '想約妳喝咖啡',
      );

      expect(
        OptimizeMessageRequestIdSession.digestFingerprint(full),
        legacyFullDigest,
      );
      expect(
        OptimizeMessageRequestIdSession.digestFingerprint(minimal),
        legacyMinimalDigest,
      );
    });

    test('refine instruction only joins the fingerprint when non-empty', () {
      List<Message> messages() => [_message('嗨')];

      final legacy = OptimizeMessageRequestIdSession.fingerprintFor(
        messages: messages(),
        userDraft: '想約妳喝咖啡',
      );
      final withInstruction = OptimizeMessageRequestIdSession.fingerprintFor(
        messages: messages(),
        userDraft: '想約妳喝咖啡',
        refineInstruction: '再幽默一點',
      );
      final sameInstruction = OptimizeMessageRequestIdSession.fingerprintFor(
        messages: messages(),
        userDraft: '想約妳喝咖啡',
        refineInstruction: '  再幽默一點  ',
      );
      final otherInstruction = OptimizeMessageRequestIdSession.fingerprintFor(
        messages: messages(),
        userDraft: '想約妳喝咖啡',
        refineInstruction: '再短一點',
      );

      expect(withInstruction, sameInstruction);
      expect(withInstruction, isNot(legacy));
      expect(withInstruction, isNot(otherInstruction));

      // 空字串／純空白／null 一律不得改變舊請求的 fingerprint。
      for (final blank in <String?>[null, '', '   ']) {
        expect(
          OptimizeMessageRequestIdSession.fingerprintFor(
            messages: messages(),
            userDraft: '想約妳喝咖啡',
            refineInstruction: blank,
          ),
          legacy,
        );
      }
    });

    test('legacy pending still matches after refine support lands', () async {
      // 舊版存下的 pending 是以「沒有指令」的 fingerprint 建的；升級後同一筆
      // 重送必須找回同一個 requestId，而不是鑄一顆新的（＝重複計費）。
      final session = OptimizeMessageRequestIdSession();
      final legacyFingerprint =
          OptimizeMessageRequestIdSession.fingerprintFor(
        messages: [_message('嗨')],
        userDraft: '想約妳喝咖啡',
      );

      final pending = await session.beginAttempt(
        ownerUserId: _ownerA,
        fingerprint: legacyFingerprint,
      );
      final restored = await session.findPending(
        ownerUserId: _ownerA,
        fingerprint: OptimizeMessageRequestIdSession.fingerprintFor(
          messages: [_message('嗨')],
          userDraft: '想約妳喝咖啡',
          refineInstruction: null,
        ),
      );

      expect(restored?.requestId, pending.requestId);
    });

    test('success and explicit reset rotate the next attempt', () async {
      final session = OptimizeMessageRequestIdSession();
      const fingerprint = 'same-payload';

      final first = await session.beginAttempt(
        ownerUserId: _ownerA,
        fingerprint: fingerprint,
      );
      await session.markSuccess(first);
      final second = await session.beginAttempt(
        ownerUserId: _ownerA,
        fingerprint: fingerprint,
      );
      await session.reset(second);
      final third = await session.beginAttempt(
        ownerUserId: _ownerA,
        fingerprint: fingerprint,
      );

      expect(second.requestId, isNot(first.requestId));
      expect(third.requestId, isNot(second.requestId));
    });

    test('expired durable identity rotates after replay window', () async {
      final store = InMemoryOptimizeMessagePendingRequestStore();
      var now = DateTime.utc(2026, 7, 16);
      final firstSession = OptimizeMessageRequestIdSession(
        store: store,
        now: () => now,
      );
      final first = await firstSession.beginAttempt(
        ownerUserId: _ownerA,
        fingerprint: 'same-payload',
      );

      now = now.add(const Duration(days: 7));
      final laterSession = OptimizeMessageRequestIdSession(
        store: store,
        now: () => now,
      );
      final later = await laterSession.beginAttempt(
        ownerUserId: _ownerA,
        fingerprint: 'same-payload',
      );

      expect(later.requestId, isNot(first.requestId));
    });

    test('persistence failure aborts before returning a billable UUID',
        () async {
      final session = OptimizeMessageRequestIdSession(
        store: _FailingSaveStore(),
      );

      await expectLater(
        session.beginAttempt(
          ownerUserId: _ownerA,
          fingerprint: 'same-payload',
        ),
        throwsStateError,
      );
    });
  });

  group('HiveOptimizeMessagePendingRequestStore', () {
    late Box<dynamic> box;

    setUp(() async {
      Hive.init('./.dart_tool/test_hive_optimize_pending');
      final timestamp = DateTime.now().microsecondsSinceEpoch;
      box = await Hive.openBox<dynamic>('optimize_pending_$timestamp');
    });

    tearDown(() async {
      await box.deleteFromDisk();
    });

    test('survives screen rebuild without persisting draft or conversation',
        () async {
      final store = HiveOptimizeMessagePendingRequestStore(() => box);
      final firstScreen = OptimizeMessageRequestIdSession(store: store);
      final first = await firstScreen.beginAttempt(
        ownerUserId: _ownerA,
        fingerprint: 'SECRET_DRAFT::SECRET_CONVERSATION',
      );

      final rawValues = box.values.whereType<String>().toList();
      expect(rawValues, hasLength(1));
      expect(rawValues.single, isNot(contains('SECRET_DRAFT')));
      expect(rawValues.single, isNot(contains('SECRET_CONVERSATION')));

      final rebuiltScreen = OptimizeMessageRequestIdSession(store: store);
      final restored = await rebuiltScreen.beginAttempt(
        ownerUserId: _ownerA,
        fingerprint: 'SECRET_DRAFT::SECRET_CONVERSATION',
      );
      expect(restored.requestId, first.requestId);
    });

    test('account-scoped rows survive and clear independently', () async {
      final store = HiveOptimizeMessagePendingRequestStore(() => box);
      final session = OptimizeMessageRequestIdSession(store: store);
      final ownerA = await session.beginAttempt(
        ownerUserId: _ownerA,
        fingerprint: 'same-payload',
      );
      final ownerB = await session.beginAttempt(
        ownerUserId: _ownerB,
        fingerprint: 'same-payload',
      );

      await session.markSuccess(ownerA);
      final restoredB =
          await OptimizeMessageRequestIdSession(store: store).beginAttempt(
        ownerUserId: _ownerB,
        fingerprint: 'same-payload',
      );
      expect(restoredB.requestId, ownerB.requestId);
      expect(box.values.whereType<String>(), hasLength(1));
    });

    test('malformed existing identity fails closed instead of minting new UUID',
        () async {
      final store = HiveOptimizeMessagePendingRequestStore(() => box);
      await OptimizeMessageRequestIdSession(store: store).beginAttempt(
        ownerUserId: _ownerA,
        fingerprint: 'charged-response-lost',
      );
      final existingKey = box.keys.single;
      await box.put(existingKey, '{malformed-json');

      final rebuilt = OptimizeMessageRequestIdSession(store: store);
      await expectLater(
        rebuilt.beginAttempt(
          ownerUserId: _ownerA,
          fingerprint: 'charged-response-lost',
        ),
        throwsStateError,
      );
      expect(box.get(existingKey), '{malformed-json');
      expect(box.keys, hasLength(1));
    });
  });
}
