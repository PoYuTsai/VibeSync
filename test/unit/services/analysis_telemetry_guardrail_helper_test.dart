import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/data/services/analysis_service.dart';
import 'package:vibesync/features/analysis/data/services/analysis_telemetry_guardrail_helper.dart';

void main() {
  group('AnalysisTelemetryGuardrailHelper', () {
    test('flags slow OCR with uncertain speaker direction', () {
      final telemetry = AnalysisTelemetry(
        requestType: 'recognize_only',
        imageCount: 1,
        requestBodyBytes: 820 * 1024,
        payloadPreparationDuration: const Duration(milliseconds: 500),
        roundTripDuration: const Duration(seconds: 9),
        timeoutDuration: const Duration(seconds: 10),
        recognizedClassification: 'low_confidence',
        recognizedSideConfidence: 'low',
        uncertainSideCount: 2,
        groupedAdjustedCount: 1,
      );

      final result = AnalysisTelemetryGuardrailHelper.evaluate(telemetry);
      final labels = result.map((item) => item.label).toList();

      expect(labels, contains('OCR 偏慢'));
      expect(labels, contains('請求偏大'));
      expect(labels, contains('非標準截圖'));
      expect(labels, contains('方向待確認'));
      expect(labels, contains('已套用結構校正'));
      expect(labels, contains('接近逾時'));
    });

    test('flags compressed context and unstable retries for analysis', () {
      final telemetry = AnalysisTelemetry(
        requestType: 'analyze',
        imageCount: 0,
        requestBodyBytes: 12 * 1024,
        payloadPreparationDuration: const Duration(milliseconds: 120),
        roundTripDuration: const Duration(seconds: 14),
        timeoutDuration: const Duration(seconds: 15),
        retryCount: 1,
        fallbackUsed: true,
        contextMode: 'opening_plus_recent',
        truncatedMessageCount: 18,
        conversationSummaryUsed: true,
      );

      final result = AnalysisTelemetryGuardrailHelper.evaluate(telemetry);
      final labels = result.map((item) => item.label).toList();

      expect(labels, contains('分析偏慢'));
      expect(labels, contains('上下文已壓縮'));
      expect(labels, contains('接近逾時'));
      expect(labels, contains('服務不穩定'));
    });

    test('does not emit guardrails for healthy fast analysis', () {
      final telemetry = AnalysisTelemetry(
        requestType: 'analyze',
        imageCount: 0,
        requestBodyBytes: 8 * 1024,
        payloadPreparationDuration: const Duration(milliseconds: 80),
        roundTripDuration: const Duration(seconds: 3),
      );

      final result = AnalysisTelemetryGuardrailHelper.evaluate(telemetry);

      expect(result, isEmpty);
    });
  });
}
