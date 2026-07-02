import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/data/services/analysis_service.dart';

void main() {
  group('AnalysisService.isAutoRetriableAnalysisError', () {
    test('圖片完整分析（已扣費路徑）的 TIMEOUT 不自動重試', () {
      // server Claude timeout 120s（parse retry 最壞再 +120s）＞ client 120s，
      // client timeout 時 server 很可能已完成並扣費；自動重打會重複扣 2-3 則。
      expect(
        AnalysisService.isAutoRetriableAnalysisError(
          code: 'TIMEOUT',
          hasImages: true,
          recognizeOnly: false,
        ),
        isFalse,
      );
    });

    test('recognizeOnly（免費 OCR）的 TIMEOUT 維持自動重試', () {
      expect(
        AnalysisService.isAutoRetriableAnalysisError(
          code: 'TIMEOUT',
          hasImages: true,
          recognizeOnly: true,
        ),
        isTrue,
      );
    });

    test('無圖路徑的 TIMEOUT 維持自動重試', () {
      expect(
        AnalysisService.isAutoRetriableAnalysisError(
          code: 'TIMEOUT',
          hasImages: false,
          recognizeOnly: false,
        ),
        isTrue,
      );
    });

    test('圖片路徑的其他 retriable code 不受影響', () {
      for (final code in [
        'NETWORK_ERROR',
        'UNEXPECTED_ERROR',
        'UPSTREAM_UNAVAILABLE',
      ]) {
        expect(
          AnalysisService.isAutoRetriableAnalysisError(
            code: code,
            hasImages: true,
            recognizeOnly: false,
          ),
          isTrue,
          reason: '$code 應維持自動重試',
        );
      }
    });

    test('非 retriable code 一律不重試', () {
      expect(
        AnalysisService.isAutoRetriableAnalysisError(
          code: 'QUOTA_EXCEEDED',
          hasImages: false,
          recognizeOnly: false,
        ),
        isFalse,
      );
      expect(
        AnalysisService.isAutoRetriableAnalysisError(
          code: null,
          hasImages: false,
          recognizeOnly: false,
        ),
        isFalse,
      );
    });
  });
}
