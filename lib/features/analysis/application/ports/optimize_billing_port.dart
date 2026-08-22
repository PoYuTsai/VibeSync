/// optimize-message exactly-once 計費的窄 port。
///
/// run() 封裝既有順序：findPending → onReadyToSend 守門 → beginAttempt
/// → send（被伺服器否認身分時 reset）；markSuccess 只能在呼叫端確認
/// 付費結果可見後發生。data 層以 OptimizeRequestRunner ＋ session 實作。
library;

import '../../../conversation/domain/entities/message.dart';
import '../../../conversation/domain/entities/session_context.dart';
import '../../domain/entities/analysis_models.dart';
import '../../domain/entities/optimize_message_pending_request.dart';

class OptimizeBillingOutcome {
  final OptimizeMessagePendingRequest? pending;
  final AnalysisResult? result;

  const OptimizeBillingOutcome.cancelled()
      : pending = null,
        result = null;

  const OptimizeBillingOutcome.success({
    required OptimizeMessagePendingRequest this.pending,
    required AnalysisResult this.result,
  });

  bool get isSuccess => result != null;
}

abstract class OptimizeBillingPort {
  /// 同一份輸入的決定論 fingerprint；指令必須參與（同稿不同指令不得
  /// 共用 requestId）。
  String fingerprintFor({
    required List<Message> messages,
    required String userDraft,
    SessionContext? sessionContext,
    String? conversationSummary,
    String? partnerSummary,
    String? effectiveStyleContext,
    String? knownContactName,
    String? refineInstruction,
  });

  Future<OptimizeBillingOutcome> run({
    required String ownerUserId,
    required String fingerprint,
    required Future<bool> Function() onReadyToSend,
    required Future<AnalysisResult> Function(
      OptimizeMessagePendingRequest pending,
    ) send,
  });

  Future<void> markSuccess(OptimizeMessagePendingRequest pending);
}
