/// data 端 adapter：以既有 OptimizeMessageRequestIdSession ＋
/// OptimizeRequestRunner 實作 application 的 OptimizeBillingPort。
/// exactly-once 順序與 reset 語意完全由 runner／session 決定，這裡只做
/// 型別對映。
library;

import '../../application/ports/optimize_billing_port.dart';
import '../../domain/entities/analysis_models.dart';
import 'optimize_message_request_session.dart';
import 'optimize_request_runner.dart';

class OptimizeBillingAdapter implements OptimizeBillingPort {
  OptimizeBillingAdapter({required OptimizeMessageRequestIdSession session})
      : _session = session,
        _runner = OptimizeRequestRunner(session: session);

  final OptimizeMessageRequestIdSession _session;
  final OptimizeRequestRunner _runner;

  @override
  String fingerprintFor({
    required messages,
    required userDraft,
    sessionContext,
    conversationSummary,
    partnerSummary,
    effectiveStyleContext,
    knownContactName,
    refineInstruction,
  }) {
    return OptimizeMessageRequestIdSession.fingerprintFor(
      messages: messages,
      userDraft: userDraft,
      sessionContext: sessionContext,
      conversationSummary: conversationSummary,
      partnerSummary: partnerSummary,
      effectiveStyleContext: effectiveStyleContext,
      knownContactName: knownContactName,
      refineInstruction: refineInstruction,
    );
  }

  @override
  Future<OptimizeBillingOutcome> run({
    required String ownerUserId,
    required String fingerprint,
    required Future<bool> Function() onReadyToSend,
    required Future<AnalysisResult> Function(
      OptimizeMessagePendingRequest pending,
    ) send,
  }) async {
    final outcome = await _runner.run<AnalysisResult>(
      input: OptimizeRunInput(
        ownerUserId: ownerUserId,
        fingerprint: fingerprint,
      ),
      onReadyToSend: onReadyToSend,
      send: send,
    );
    if (!outcome.isSuccess) {
      return const OptimizeBillingOutcome.cancelled();
    }
    return OptimizeBillingOutcome.success(
      pending: outcome.pending!,
      result: outcome.result!,
    );
  }

  @override
  Future<void> markSuccess(OptimizeMessagePendingRequest pending) =>
      _session.markSuccess(pending);
}
