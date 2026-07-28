import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/data/services/analysis_service.dart';
import 'package:vibesync/features/analysis/data/services/optimize_message_request_session.dart';
import 'package:vibesync/features/analysis/data/services/optimize_request_runner.dart';

const _owner = '11111111-1111-4111-8111-111111111111';
const _fingerprint = '["fixed-wire-payload"]';

/// Wraps the real state machine so the assertions cover production behaviour
/// rather than a hand-written double that could drift from it.
class _RecordingSession extends OptimizeMessageRequestIdSession {
  final markSuccessCalls = <OptimizeMessagePendingRequest>[];
  final resetCalls = <OptimizeMessagePendingRequest>[];
  final begunRequestIds = <String>[];
  OptimizeMessagePendingRequest? lastBegun;

  @override
  Future<OptimizeMessagePendingRequest> beginAttempt({
    required String ownerUserId,
    required String fingerprint,
  }) async {
    final pending = await super.beginAttempt(
      ownerUserId: ownerUserId,
      fingerprint: fingerprint,
    );
    lastBegun = pending;
    begunRequestIds.add(pending.requestId);
    return pending;
  }

  @override
  Future<void> markSuccess(OptimizeMessagePendingRequest pending) async {
    markSuccessCalls.add(pending);
    await super.markSuccess(pending);
  }

  @override
  Future<void> reset(OptimizeMessagePendingRequest pending) async {
    resetCalls.add(pending);
    await super.reset(pending);
  }
}

OptimizeRunInput _input() => const OptimizeRunInput(
      ownerUserId: _owner,
      fingerprint: _fingerprint,
    );

void main() {
  test('失敗後重試沿用同一個 requestId，runner 自己不呼叫 markSuccess', () async {
    final session = _RecordingSession();
    final runner = OptimizeRequestRunner(session: session);

    await expectLater(
      runner.run<String>(
        input: _input(),
        send: (pending) async => throw const SocketException('network'),
      ),
      throwsA(isA<SocketException>()),
    );
    final firstRequestId = session.lastBegun!.requestId;
    expect(session.markSuccessCalls, isEmpty);
    expect(session.resetCalls, isEmpty);

    final second = await runner.run<String>(
      input: _input(),
      send: (pending) async {
        expect(pending.requestId, firstRequestId);
        return 'optimized';
      },
    );

    expect(second.isSuccess, isTrue);
    expect(second.result, 'optimized');
    expect(second.pending!.requestId, firstRequestId);
    // markSuccess 是呼叫端在畫面真的畫出付費結果後才做的事；runner 不得代勞，
    // 否則使用者在結果出現前離開就再也無法 replay 已付結果。
    expect(session.markSuccessCalls, isEmpty);
  });

  test('沒有方案閘門：任何用戶都能直接鑄身分並送出', () async {
    final session = _RecordingSession();
    final runner = OptimizeRequestRunner(session: session);
    var sendCalls = 0;

    final outcome = await runner.run<String>(
      input: _input(),
      send: (pending) async {
        sendCalls++;
        return 'optimized';
      },
    );

    expect(outcome.isSuccess, isTrue);
    expect(sendCalls, 1);
    expect(session.begunRequestIds, hasLength(1));
  });

  test('既存 pending：重試沿用同一身分取回已付結果', () async {
    final session = _RecordingSession();
    final runner = OptimizeRequestRunner(session: session);

    await expectLater(
      runner.run<String>(
        input: _input(),
        send: (pending) async => throw const SocketException('network'),
      ),
      throwsA(isA<SocketException>()),
    );
    final paidRequestId = session.lastBegun!.requestId;

    final recovered = await runner.run<String>(
      input: _input(),
      send: (pending) async {
        expect(pending.requestId, paidRequestId);
        return 'optimized';
      },
    );

    expect(recovered.isSuccess, isTrue);
  });

  test('onReadyToSend 回 false：不 beginAttempt、不送出', () async {
    final session = _RecordingSession();
    final runner = OptimizeRequestRunner(session: session);
    var sendCalls = 0;

    final outcome = await runner.run<String>(
      input: _input(),
      onReadyToSend: () async => false,
      send: (pending) async {
        sendCalls++;
        return 'optimized';
      },
    );

    expect(outcome.status, OptimizeRunStatus.cancelled);
    expect(sendCalls, 0);
    expect(session.begunRequestIds, isEmpty);
  });

  test('replay 身分錯誤：reset 掉本機 pending 並把錯誤丟回呼叫端', () async {
    for (final code in const [
      'INVALID_OPTIMIZE_MESSAGE_REQUEST_ID',
      'OPTIMIZE_MESSAGE_REQUEST_REPLAY_MISMATCH',
    ]) {
      final session = _RecordingSession();
      final runner = OptimizeRequestRunner(session: session);

      await expectLater(
        runner.run<String>(
          input: _input(),
          send: (pending) async => throw AnalysisException('壞了', code: code),
        ),
        throwsA(isA<AnalysisException>()),
        reason: code,
      );

      expect(session.resetCalls, hasLength(1), reason: code);
      // reset 後下一次必須鑄新的 requestId，不能沿用被伺服器否認的身分。
      await expectLater(
        runner.run<String>(
          input: _input(),
          send: (pending) async {
            expect(pending.requestId, isNot(session.begunRequestIds.first));
            throw const SocketException('network');
          },
        ),
        throwsA(isA<SocketException>()),
        reason: code,
      );
    }
  });

  test('其他錯誤碼不 reset：pending 保留下來才能重試同一筆', () async {
    final session = _RecordingSession();
    final runner = OptimizeRequestRunner(session: session);

    await expectLater(
      runner.run<String>(
        input: _input(),
        send: (pending) async => throw AnalysisException(
          '這次沒有產生可用的優化結果，請稍後再試。',
          code: 'OPTIMIZE_MESSAGE_RESULT_INVALID',
        ),
      ),
      throwsA(isA<AnalysisException>()),
    );

    expect(session.resetCalls, isEmpty);
    expect(session.begunRequestIds, hasLength(1));

    await expectLater(
      runner.run<String>(
        input: _input(),
        send: (pending) async {
          expect(pending.requestId, session.begunRequestIds.first);
          throw const SocketException('network');
        },
      ),
      throwsA(isA<SocketException>()),
    );
    expect(session.begunRequestIds, hasLength(1));
  });
}
