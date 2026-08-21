/// 潤飾／微調的傳輸呼叫窄 port：兩個 typed callable 對應 auxiliary
/// client 的 optimizeDraft／refineReply（requestId 是 exactly-once 帳本
/// 的 durable 身分）。data client 在 composition root 直接以 tear-off
/// 供給。
library;

import '../../../conversation/domain/entities/message.dart';
import '../../../conversation/domain/entities/session_context.dart';
import '../../domain/entities/analysis_models.dart';
import '../../domain/entities/analysis_telemetry.dart';

typedef OptimizeDraftCall = Future<AnalysisResult> Function({
  required List<Message> messages,
  required String userDraft,
  SessionContext? sessionContext,
  String? conversationSummary,
  String? partnerSummary,
  String? effectiveStyleContext,
  String? knownContactName,
  String? requestId,
  AnalysisTelemetryCallback? onTelemetry,
});

typedef RefineReplyCall = Future<AnalysisResult> Function({
  required List<Message> messages,
  required String userDraft,
  required String refineInstruction,
  String? refineAnchorText,
  SessionContext? sessionContext,
  String? conversationSummary,
  String? partnerSummary,
  String? effectiveStyleContext,
  String? knownContactName,
  String? requestId,
  AnalysisTelemetryCallback? onTelemetry,
});
