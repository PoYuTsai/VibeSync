/// 截圖辨識工作流的窄 port：免費 OCR 傳輸呼叫與辨識結果快取。
/// data 層（AnalysisAuxiliaryClient／OcrRecognitionCacheService）在
/// composition root 以 adapter 實作。
library;

import 'dart:typed_data';

import '../../../conversation/domain/entities/session_context.dart';
import '../../domain/entities/analysis_models.dart';
import '../../domain/entities/analysis_telemetry.dart';

/// 免費 OCR：一批截圖辨識成結構化對話（不扣訂閱額度、單次 HTTP）。
typedef RecognizeScreenshots = Future<AnalysisResult> Function({
  required List<Uint8List> images,
  SessionContext? sessionContext,
  String? knownContactName,
  AnalysisProgressCallback? onProgress,
  AnalysisTelemetryCallback? onTelemetry,
});

abstract class OcrRecognitionCachePort {
  Future<void> invalidate(List<Uint8List> images, String conversationId);

  /// 快取命中回辨識結果；未命中回 null。
  Future<RecognizedConversation?> read(
    List<Uint8List> images,
    String conversationId,
  );

  Future<void> write({
    required List<Uint8List> images,
    required RecognizedConversation recognizedConversation,
    required String conversationId,
  });
}
