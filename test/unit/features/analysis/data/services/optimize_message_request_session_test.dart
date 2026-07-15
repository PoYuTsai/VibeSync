import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/analysis/data/services/optimize_message_request_session.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';

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
    test('downgraded account may replay paid pending but cannot start fresh',
        () async {
      final session = OptimizeMessageRequestIdSession();
      expect(
        canSendOptimizeMessageRequest(isEssential: false, pending: null),
        isFalse,
      );
      expect(
        canSendOptimizeMessageRequest(isEssential: true, pending: null),
        isTrue,
      );

      final paidButResponseLost = await session.beginAttempt(
        ownerUserId: _ownerA,
        fingerprint: 'charged-response-lost',
      );
      final restoredAfterDowngrade = await session.findPending(
        ownerUserId: _ownerA,
        fingerprint: 'charged-response-lost',
      );
      expect(restoredAfterDowngrade?.requestId, paidButResponseLost.requestId);
      expect(
        canSendOptimizeMessageRequest(
          isEssential: false,
          pending: restoredAfterDowngrade,
        ),
        isTrue,
      );
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
