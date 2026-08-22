/// 主分析串流 run 的窄 port：session controller 只能透過這兩個 callable
/// 碰 StreamingAnalyzeNotifier（唯一 reactive 真相留在 data notifier）。
library;

import '../../../conversation/domain/entities/message.dart';
import '../../../conversation/domain/entities/session_context.dart';
import '../../domain/entities/overcharge_confirmation.dart';

/// 啟動唯一串流 run（notifier 快取 payload 供 retry、跨導航存活）。
typedef StartAnalysisRun = Future<void> Function({
  required List<Message> messages,
  SessionContext? sessionContext,
  String? conversationSummary,
  String? partnerSummary,
  String? effectiveStyleContext,
  String? knownContactName,
  int? previousAnalyzedCount,
  int? previousAnalyzedCharCount,
  OverchargeConfirmationPayload? confirmedOvercharge,
  int? conversationMessageCount,
  int? analyzedMessageCount,
  String? conversationContentRevision,
});

/// 以快取的 runId＋payload 續跑同一 run（不重扣額度）；無可續跑時 no-op。
typedef RetryAnalysisRun = Future<void> Function();
