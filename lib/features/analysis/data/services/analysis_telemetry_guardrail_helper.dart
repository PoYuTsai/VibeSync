import 'analysis_service.dart';

enum AnalysisTelemetryGuardrailSeverity {
  info,
  warning,
  critical,
}

class AnalysisTelemetryGuardrail {
  final String label;
  final String detail;
  final AnalysisTelemetryGuardrailSeverity severity;

  const AnalysisTelemetryGuardrail({
    required this.label,
    required this.detail,
    required this.severity,
  });
}

class AnalysisTelemetryGuardrailHelper {
  static const int _singleImageOcrWarningMs = 7000;
  static const int _multiImageOcrWarningMs = 15000;
  static const int _generalAnalysisWarningMs = 12000;
  static const int _myMessageWarningMs = 6000;
  static const int _optimizeWarningMs = 6000;
  static const int _heavyOcrPayloadBytes = 700 * 1024;
  static const double _nearTimeoutRatio = 0.8;

  static List<AnalysisTelemetryGuardrail> evaluate(
    AnalysisTelemetry telemetry,
  ) {
    final guardrails = <AnalysisTelemetryGuardrail>[];
    if (telemetry.requestType == 'recognize_only') {
      _appendRecognizeGuardrails(guardrails, telemetry);
    } else {
      _appendAnalysisGuardrails(guardrails, telemetry);
    }
    return guardrails;
  }

  static void _appendRecognizeGuardrails(
    List<AnalysisTelemetryGuardrail> guardrails,
    AnalysisTelemetry telemetry,
  ) {
    final expectedOcrMs = telemetry.imageCount > 1
        ? _multiImageOcrWarningMs
        : _singleImageOcrWarningMs;
    if (telemetry.roundTripDuration.inMilliseconds > expectedOcrMs) {
      guardrails.add(
        AnalysisTelemetryGuardrail(
          label: 'OCR 偏慢',
          detail: telemetry.imageCount > 1
              ? '這次多張截圖 OCR 已超過 ${expectedOcrMs ~/ 1000} 秒 benchmark，建議檢查圖片大小或張數。'
              : '這次單張 OCR 已超過 ${expectedOcrMs ~/ 1000} 秒 benchmark，建議檢查圖片大小或截圖內容密度。',
          severity: AnalysisTelemetryGuardrailSeverity.warning,
        ),
      );
    }

    if (telemetry.requestBodyBytes > _heavyOcrPayloadBytes) {
      guardrails.add(
        const AnalysisTelemetryGuardrail(
          label: '請求偏大',
          detail: '這次 OCR 請求偏大，若常出現偏慢情況，建議縮短截圖長度或減少張數。',
          severity: AnalysisTelemetryGuardrailSeverity.info,
        ),
      );
    }

    if (telemetry.recognizedClassification != null &&
        telemetry.recognizedClassification != 'valid_chat') {
      guardrails.add(
        AnalysisTelemetryGuardrail(
          label: '非標準截圖',
          detail:
              '本次識別分類為 ${telemetry.recognizedClassification}，建議先確認這張圖是否真的是同一段雙人聊天。',
          severity: telemetry.recognizedClassification == 'low_confidence'
              ? AnalysisTelemetryGuardrailSeverity.warning
              : AnalysisTelemetryGuardrailSeverity.critical,
        ),
      );
    }

    if (telemetry.recognizedSideConfidence == 'low' ||
        (telemetry.uncertainSideCount ?? 0) > 0) {
      guardrails.add(
        AnalysisTelemetryGuardrail(
          label: '方向待確認',
          detail: (telemetry.uncertainSideCount ?? 0) > 0
              ? '本次有 ${telemetry.uncertainSideCount} 則訊息左右方向不夠穩，匯入前建議先檢查「我說 / 她說」。'
              : '本次 speaker 方向信心偏低，匯入前建議先檢查「我說 / 她說」。',
          severity: AnalysisTelemetryGuardrailSeverity.warning,
        ),
      );
    }

    final totalRepairs = (telemetry.continuityAdjustedCount ?? 0) +
        (telemetry.groupedAdjustedCount ?? 0) +
        (telemetry.layoutFirstAdjustedCount ?? 0) +
        (telemetry.quotedPreviewAttachedCount ?? 0);
    if (totalRepairs > 0) {
      guardrails.add(
        AnalysisTelemetryGuardrail(
          label: '已套用結構校正',
          detail: '本次 OCR 有套用 $totalRepairs 次結構校正或引用併回，若內容仍怪，建議打開預覽逐則確認。',
          severity: AnalysisTelemetryGuardrailSeverity.info,
        ),
      );
    }

    if (_isNearTimeout(telemetry)) {
      guardrails.add(
        const AnalysisTelemetryGuardrail(
          label: '接近逾時',
          detail: '這次 OCR 已接近逾時上限，若持續發生，建議減少單張訊息量或拆成多次匯入。',
          severity: AnalysisTelemetryGuardrailSeverity.warning,
        ),
      );
    }

    if (telemetry.retryCount > 0 || telemetry.fallbackUsed) {
      guardrails.add(
        const AnalysisTelemetryGuardrail(
          label: '服務不穩定',
          detail: '這次請求有重試或 fallback，代表上游模型回應不夠穩，若持續發生建議稍後再試。',
          severity: AnalysisTelemetryGuardrailSeverity.warning,
        ),
      );
    }
  }

  static void _appendAnalysisGuardrails(
    List<AnalysisTelemetryGuardrail> guardrails,
    AnalysisTelemetry telemetry,
  ) {
    final expectedMs = _analysisWarningThresholdMs(telemetry.requestType);
    if (telemetry.roundTripDuration.inMilliseconds > expectedMs) {
      guardrails.add(
        AnalysisTelemetryGuardrail(
          label: '分析偏慢',
          detail:
              '這次 ${_requestTypeLabel(telemetry.requestType)}已超過 ${expectedMs ~/ 1000} 秒 benchmark，建議觀察是否和長上下文或網路有關。',
          severity: AnalysisTelemetryGuardrailSeverity.warning,
        ),
      );
    }

    if ((telemetry.truncatedMessageCount ?? 0) > 0 ||
        telemetry.conversationSummaryUsed ||
        telemetry.contextMode == 'opening_plus_recent') {
      final truncated = telemetry.truncatedMessageCount ?? 0;
      final detail = truncated > 0
          ? '這次分析已省略 $truncated 則較早訊息，並改用摘要 + 最近對話模式；若結果怪，建議檢查是否缺少關鍵上下文。'
          : '這次分析已切換成摘要 + 最近對話模式，若結果怪，建議檢查是否缺少關鍵上下文。';
      guardrails.add(
        AnalysisTelemetryGuardrail(
          label: '上下文已壓縮',
          detail: detail,
          severity: AnalysisTelemetryGuardrailSeverity.info,
        ),
      );
    }

    if (_isNearTimeout(telemetry)) {
      guardrails.add(
        const AnalysisTelemetryGuardrail(
          label: '接近逾時',
          detail: '這次分析已接近逾時上限，若持續發生，建議縮短上下文或拆成較小段落分析。',
          severity: AnalysisTelemetryGuardrailSeverity.warning,
        ),
      );
    }

    if (telemetry.retryCount > 0 || telemetry.fallbackUsed) {
      guardrails.add(
        const AnalysisTelemetryGuardrail(
          label: '服務不穩定',
          detail: '這次分析有重試或 fallback，代表模型回應不夠穩，若持續發生建議稍後再試。',
          severity: AnalysisTelemetryGuardrailSeverity.warning,
        ),
      );
    }
  }

  static int _analysisWarningThresholdMs(String? requestType) {
    switch (requestType) {
      case 'my_message':
        return _myMessageWarningMs;
      case 'optimize_message':
        return _optimizeWarningMs;
      default:
        return _generalAnalysisWarningMs;
    }
  }

  static bool _isNearTimeout(AnalysisTelemetry telemetry) {
    final timeoutDuration = telemetry.timeoutDuration;
    if (timeoutDuration == null) {
      return false;
    }
    return telemetry.roundTripDuration.inMilliseconds >=
        (timeoutDuration.inMilliseconds * _nearTimeoutRatio);
  }

  static String _requestTypeLabel(String? requestType) {
    switch (requestType) {
      case 'my_message':
        return '「我說」分析';
      case 'optimize_message':
        return '訊息優化';
      case 'analyze_with_images':
        return '帶圖分析';
      default:
        return '分析';
    }
  }
}
