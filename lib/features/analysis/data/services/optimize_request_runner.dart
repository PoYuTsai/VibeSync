import 'analysis_service.dart' show AnalysisException;
import 'optimize_message_request_session.dart';

/// Sends one billable optimize-message attempt. The runner hands the caller the
/// durable identity so the wire payload can carry `requestId: pending.requestId`.
typedef OptimizeSend<T> = Future<T> Function(
  OptimizeMessagePendingRequest pending,
);

enum OptimizeRunStatus {
  /// `send` returned a value. The caller still owes `markSuccess` once the
  /// paid result is actually on screen.
  success,

  /// The caller's pre-send gate declined (unmounted screen, consent refused).
  cancelled,
}

class OptimizeRunInput {
  const OptimizeRunInput({
    required this.ownerUserId,
    required this.fingerprint,
  });

  final String ownerUserId;
  final String fingerprint;
}

class OptimizeRunOutcome<T> {
  const OptimizeRunOutcome._(this.status, this.pending, this.result);

  const OptimizeRunOutcome.cancelled()
      : this._(OptimizeRunStatus.cancelled, null, null);

  const OptimizeRunOutcome.success(
    OptimizeMessagePendingRequest pending,
    T result,
  ) : this._(OptimizeRunStatus.success, pending, result);

  final OptimizeRunStatus status;

  /// Non-null once an attempt was begun. The caller needs it for the
  /// visible-frame `markSuccess`.
  final OptimizeMessagePendingRequest? pending;

  final T? result;

  bool get isSuccess => status == OptimizeRunStatus.success;
}

/// The one exactly-once path for optimize-message style requests.
///
/// Every entry point (draft polisher, reply refinement) goes through here.
/// Duplicating this ordering duplicates the chance of double-charging a user:
/// `findPending` must precede everything so an interrupted attempt is recovered
/// instead of paid for twice, and `beginAttempt` must not mint an identity for
/// an action that will never be sent.
///
/// There is no tier gate here. Draft polish and reply refinement are open to
/// every plan and metered by quota alone.
class OptimizeRequestRunner {
  OptimizeRequestRunner({required OptimizeMessageRequestIdSession session})
      : _session = session;

  final OptimizeMessageRequestIdSession _session;

  /// Codes that mean the server refuses this durable identity. Keeping the
  /// local row would retry the same rejected `requestId` forever.
  static const resetOnErrorCodes = <String>{
    'INVALID_OPTIMIZE_MESSAGE_REQUEST_ID',
    'OPTIMIZE_MESSAGE_REQUEST_REPLAY_MISMATCH',
  };

  Future<OptimizeRunOutcome<T>> run<T>({
    required OptimizeRunInput input,
    required OptimizeSend<T> send,
    Future<bool> Function()? onReadyToSend,
  }) async {
    final existingPending = await _session.findPending(
      ownerUserId: input.ownerUserId,
      fingerprint: input.fingerprint,
    );
    if (onReadyToSend != null && !await onReadyToSend()) {
      return const OptimizeRunOutcome.cancelled();
    }

    // Persisted before the billable call; a save failure must abort the send.
    final pending = existingPending ??
        await _session.beginAttempt(
          ownerUserId: input.ownerUserId,
          fingerprint: input.fingerprint,
        );

    try {
      final result = await send(pending);
      return OptimizeRunOutcome<T>.success(pending, result);
    } on AnalysisException catch (e) {
      if (resetOnErrorCodes.contains(e.code)) {
        try {
          await _session.reset(pending);
        } catch (_) {
          // A stale encrypted snapshot is replay-safe; the next attempt can
          // surface a storage error without sending another billable call.
        }
      }
      rethrow;
    }
  }
}
