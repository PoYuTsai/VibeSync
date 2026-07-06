import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/coaching_memory/data/services/coaching_outcome_uploader.dart';
import 'package:vibesync/features/coaching_memory/domain/entities/coaching_outcome_event.dart';

/// Fully-populated event: every privacy-sensitive local-only field is set so
/// tests can prove they never reach the wire.
CoachingOutcomeEvent _event() {
  return CoachingOutcomeEvent(
    id: 'opener:req-1:extend',
    partnerId: 'partner-secret',
    conversationId: 'conversation-secret',
    source: CoachingOutcomeSource.opener,
    adviceId: 'opener:req-1:extend',
    adviceType: 'extend',
    suggestedMoveSummary: '妳週末也會去爬山嗎？',
    userAction: CoachingUserAction.editedAndSent,
    outcome: CoachingOutcomeSignal.engaged,
    outcomeTextPreview: '她回：真的假的你也爬山',
    userNote: '這招對戶外掛有效',
    createdAt: DateTime.utc(2026, 7, 6, 10, 30, 15),
  );
}

class _CapturingInvoker {
  String? fn;
  Map<String, dynamic>? body;
  int callCount = 0;

  final int status;
  final Object? throwError;

  _CapturingInvoker({this.status = 200, this.throwError});

  Future<CoachingOutcomeUploadResponse> call(
    String functionName, {
    required Map<String, dynamic> body,
  }) async {
    callCount++;
    fn = functionName;
    this.body = body;
    if (throwError != null) {
      throw throwError!;
    }
    return CoachingOutcomeUploadResponse(status);
  }
}

void main() {
  group('buildOutcomeUploadBody 白名單與序列化', () {
    test('只含白名單欄位、enum 用 .name、createdAt 為 ISO8601 UTC', () {
      final body = CoachingOutcomeUploader.buildOutcomeUploadBody(
        _event(),
        userTier: 'starter',
      );

      expect(body['kind'], 'outcome');
      final event = body['event'] as Map<String, dynamic>;

      expect(event['id'], 'opener:req-1:extend');
      expect(event['source'], 'opener');
      expect(event['adviceType'], 'extend');
      expect(event['adviceId'], 'opener:req-1:extend');
      expect(event['userAction'], 'editedAndSent');
      expect(event['outcome'], 'engaged');
      expect(event['suggestedMoveSummary'], '妳週末也會去爬山嗎？');
      expect(event['createdAt'], '2026-07-06T10:30:15.000Z');
      expect(event['userTier'], 'starter');

      // 白名單以外的鍵一律不得出現。
      const allowed = {
        'id',
        'source',
        'adviceType',
        'adviceId',
        'userAction',
        'outcome',
        'suggestedMoveSummary',
        'createdAt',
        'userTier',
      };
      expect(event.keys.toSet().difference(allowed), isEmpty);
    });

    test('隱私承諾：preview/note/partnerId/conversationId 絕不出現在 payload', () {
      final body = CoachingOutcomeUploader.buildOutcomeUploadBody(
        _event(),
        userTier: 'essential',
      );
      final event = body['event'] as Map<String, dynamic>;

      expect(event.containsKey('outcomeTextPreview'), isFalse);
      expect(event.containsKey('userNote'), isFalse);
      expect(event.containsKey('partnerId'), isFalse);
      expect(event.containsKey('conversationId'), isFalse);

      // 連值都不得洩漏（防止改名夾帶）。
      final serialized = event.values.map((v) => v.toString()).join('|');
      expect(serialized.contains('partner-secret'), isFalse);
      expect(serialized.contains('conversation-secret'), isFalse);
      expect(serialized.contains('她回：真的假的你也爬山'), isFalse);
      expect(serialized.contains('這招對戶外掛有效'), isFalse);
    });

    test('createdAt 為本地時間時序列化為 UTC', () {
      final body = CoachingOutcomeUploader.buildOutcomeUploadBody(
        CoachingOutcomeEvent(
          id: 'e1',
          source: CoachingOutcomeSource.analyze,
          suggestedMoveSummary: 'x',
          userAction: CoachingUserAction.sentAsIs,
          outcome: CoachingOutcomeSignal.pending,
          createdAt: DateTime(2026, 7, 6, 10),
        ),
      );
      final createdAt = (body['event'] as Map)['createdAt'] as String;
      expect(createdAt.endsWith('Z'), isTrue);
    });

    test('tier 為 null 時省略 userTier 欄位', () {
      final body = CoachingOutcomeUploader.buildOutcomeUploadBody(_event());
      final event = body['event'] as Map<String, dynamic>;
      expect(event.containsKey('userTier'), isFalse);
    });

    test('adviceType/adviceId 為 null 時省略', () {
      final body = CoachingOutcomeUploader.buildOutcomeUploadBody(
        CoachingOutcomeEvent(
          id: 'e1',
          source: CoachingOutcomeSource.analyze,
          suggestedMoveSummary: 'x',
          userAction: CoachingUserAction.unknown,
          outcome: CoachingOutcomeSignal.unknown,
          createdAt: DateTime.utc(2026, 7, 6, 10),
        ),
      );
      final event = body['event'] as Map<String, dynamic>;
      expect(event.containsKey('adviceType'), isFalse);
      expect(event.containsKey('adviceId'), isFalse);
    });
  });

  group('upload best-effort fire-and-forget', () {
    test('打到 submit-feedback、送出白名單 body 且 tier 來自 resolver', () async {
      final invoker = _CapturingInvoker(status: 200);
      final uploader = CoachingOutcomeUploader(
        invoker: invoker.call,
        resolveUserTier: () => 'starter',
      );

      await uploader.upload(_event());

      expect(invoker.callCount, 1);
      expect(invoker.fn, 'submit-feedback');
      final event = invoker.body!['event'] as Map<String, dynamic>;
      expect(event['userTier'], 'starter');
      expect(event.containsKey('partnerId'), isFalse);
      expect(event.containsKey('outcomeTextPreview'), isFalse);
      expect(event.containsKey('userNote'), isFalse);
      expect(event.containsKey('conversationId'), isFalse);
    });

    test('invoker 丟例外時不 throw（吞錯）', () async {
      final invoker = _CapturingInvoker(throwError: Exception('network down'));
      final uploader = CoachingOutcomeUploader(
        invoker: invoker.call,
        resolveUserTier: () => 'free',
      );

      await expectLater(uploader.upload(_event()), completes);
    });

    test('回 500 非 2xx 時不 throw（吞錯）', () async {
      final invoker = _CapturingInvoker(status: 500);
      final uploader = CoachingOutcomeUploader(
        invoker: invoker.call,
        resolveUserTier: () => null,
      );

      await expectLater(uploader.upload(_event()), completes);
      expect(invoker.callCount, 1);
    });

    test('resolveUserTier 丟例外時不擋上傳、送 null tier', () async {
      final invoker = _CapturingInvoker(status: 200);
      final uploader = CoachingOutcomeUploader(
        invoker: invoker.call,
        resolveUserTier: () => throw StateError('no subscription'),
      );

      await uploader.upload(_event());

      expect(invoker.callCount, 1);
      final event = invoker.body!['event'] as Map<String, dynamic>;
      expect(event.containsKey('userTier'), isFalse);
    });
  });
}
