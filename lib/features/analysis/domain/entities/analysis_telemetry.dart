/// AnalyzeChat 輔助請求的純資料 telemetry／進度值物件（domain）。
///
/// 這裡只有可跨層共享的 VO 與 callback typedef：進度階段 enum、進度
/// 更新、telemetry。中文顯示 label 在 presentation
/// （analysis_progress_stage_copy）、HTTP 圍籬與等待里程碑在 data
/// （auxiliary client）、135s 畫面圍籬在 application（screenshot
/// coordinator，真正的 fence owner）。歷史 import 路徑以 re-export 相容。
library;

enum AnalysisProgressStage {
  preparingPayload,
  uploadingRequest,
  awaitingAi,
  recognizingMessages,
  resolvingSpeakers,
  finalizingRecognition,
}

class AnalysisProgressUpdate {
  final AnalysisProgressStage stage;
  final int imageCount;
  final Duration elapsed;
  final int? requestBodyBytes;

  const AnalysisProgressUpdate({
    required this.stage,
    required this.imageCount,
    required this.elapsed,
    this.requestBodyBytes,
  });
}

class AnalysisTelemetry {
  final String? requestType;
  final int imageCount;
  final int requestBodyBytes;
  final Duration payloadPreparationDuration;
  final Duration roundTripDuration;
  final Duration? edgeAiDuration;
  final int? totalCompressedImageBytes;
  final bool cacheHit;
  final bool fallbackUsed;
  final int retryCount;
  final Duration? timeoutDuration;
  final bool? allowModelFallback;
  final String? contextMode;
  final int? inputMessageCount;
  final int? compiledMessageCount;
  final int? truncatedMessageCount;
  final int? openingMessagesUsed;
  final int? recentMessagesUsed;
  final bool conversationSummaryUsed;
  final String? recognizedClassification;
  final String? recognizedConfidence;
  final String? recognizedSideConfidence;
  final int? recognizedMessageCount;
  final int? uncertainSideCount;
  final int? continuityAdjustedCount;
  final int? groupedAdjustedCount;
  final int? layoutFirstAdjustedCount;
  final int? systemRowsRemovedCount;
  final int? quotedPreviewRemovedCount;
  final int? quotedPreviewAttachedCount;
  final int? overlapRemovedCount;
  final bool? shouldChargeQuota;
  final int? chargedMessageCount;
  final int? estimatedMessageCount;
  final String? quotaReason;

  const AnalysisTelemetry({
    this.requestType,
    required this.imageCount,
    required this.requestBodyBytes,
    required this.payloadPreparationDuration,
    required this.roundTripDuration,
    this.edgeAiDuration,
    this.totalCompressedImageBytes,
    this.cacheHit = false,
    this.fallbackUsed = false,
    this.retryCount = 0,
    this.timeoutDuration,
    this.allowModelFallback,
    this.contextMode,
    this.inputMessageCount,
    this.compiledMessageCount,
    this.truncatedMessageCount,
    this.openingMessagesUsed,
    this.recentMessagesUsed,
    this.conversationSummaryUsed = false,
    this.recognizedClassification,
    this.recognizedConfidence,
    this.recognizedSideConfidence,
    this.recognizedMessageCount,
    this.uncertainSideCount,
    this.continuityAdjustedCount,
    this.groupedAdjustedCount,
    this.layoutFirstAdjustedCount,
    this.systemRowsRemovedCount,
    this.quotedPreviewRemovedCount,
    this.quotedPreviewAttachedCount,
    this.overlapRemovedCount,
    this.shouldChargeQuota,
    this.chargedMessageCount,
    this.estimatedMessageCount,
    this.quotaReason,
  });

  Duration? get estimatedTransferDuration {
    if (edgeAiDuration == null) {
      return null;
    }

    final remainingMs =
        roundTripDuration.inMilliseconds - edgeAiDuration!.inMilliseconds;
    return Duration(milliseconds: remainingMs < 0 ? 0 : remainingMs);
  }
}

typedef AnalysisProgressCallback = void Function(
  AnalysisProgressUpdate update,
);

typedef AnalysisTelemetryCallback = void Function(
  AnalysisTelemetry telemetry,
);
