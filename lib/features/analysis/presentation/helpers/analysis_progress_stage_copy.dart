/// OCR／分析等待進度階段的中文顯示文案（presentation-owned）。
library;

import '../../domain/entities/analysis_telemetry.dart';

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
