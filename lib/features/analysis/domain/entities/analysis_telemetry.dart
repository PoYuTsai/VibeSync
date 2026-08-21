/// AnalyzeChat 輔助請求的進度階段、等待里程碑、圍籬時限與 telemetry
/// 值物件（domain）。screen／application／data client 共用；歷史
/// import 路徑（auxiliary client／analysis_service barrel）以
/// re-export 相容。
library;

enum AnalysisProgressStage {
  preparingPayload,
  uploadingRequest,
  awaitingAi,
  recognizingMessages,
  resolvingSpeakers,
  finalizingRecognition,
}

String analysisProgressStageLabel(AnalysisProgressStage stage) {
  switch (stage) {
    case AnalysisProgressStage.preparingPayload:
      return '準備圖片中';
    case AnalysisProgressStage.uploadingRequest:
      return '上傳圖片中';
    case AnalysisProgressStage.awaitingAi:
      return 'AI 讀取圖片中';
    case AnalysisProgressStage.recognizingMessages:
      return '辨識訊息內容中';
    case AnalysisProgressStage.resolvingSpeakers:
      return '校對說話者中';
    case AnalysisProgressStage.finalizingRecognition:
      return '整理辨識結果中';
  }
}

class AnalysisProgressMilestone {
  final Duration delay;
  final AnalysisProgressStage stage;

  const AnalysisProgressMilestone(this.delay, this.stage);
}

/// recognizeOnly 不傳輸中間分析內容，只在等待同一個 OCR
/// request 時送出輕量狀態。這些是用戶等待進度，不是伺服器承諾的
/// 精確百分比；response schema、quota 與 OCR 結果契約都不變。
const ocrRecognitionProgressMilestones = <AnalysisProgressMilestone>[
  AnalysisProgressMilestone(
    Duration(milliseconds: 700),
    AnalysisProgressStage.awaitingAi,
  ),
  AnalysisProgressMilestone(
    Duration(seconds: 4),
    AnalysisProgressStage.recognizingMessages,
  ),
  AnalysisProgressMilestone(
    Duration(seconds: 9),
    AnalysisProgressStage.resolvingSpeakers,
  ),
  AnalysisProgressMilestone(
    Duration(seconds: 15),
    AnalysisProgressStage.finalizingRecognition,
  ),
];

/// Client fences must outlive the Edge request-level model budgets (50s text,
/// 120s image) so parsing and quota settlement can finish before the socket is
/// closed locally.
const kAnalyzeTextRequestTimeout = Duration(seconds: 65);
const kAnalyzeImageRequestTimeout = Duration(seconds: 130);

/// The screen-level OCR fence wraps payload preparation as well as the HTTP
/// call, so it stays outside [kAnalyzeImageRequestTimeout].
const kAnalyzeOcrScreenTimeout = Duration(seconds: 135);

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
