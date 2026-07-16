import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/data/services/ocr_recognition_cache_service.dart';

void main() {
  test('OCR cache version 必須隨辨識內容正規化改動 bump（地圖分享後 ≥ 6）', () {
    // Google Maps URL＋預覽現在會收斂成單一地點分享；版本停在 5 以下時，
    // 已快取的 URL／Google 制式英文仍會在 24h TTL 內重播。
    expect(
      OcrRecognitionCacheService.debugCacheVersion,
      greaterThanOrEqualTo(6),
    );
  });
}
