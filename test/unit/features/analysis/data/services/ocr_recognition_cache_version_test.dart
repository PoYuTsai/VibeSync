import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/data/services/ocr_recognition_cache_service.dart';

void main() {
  test('OCR cache version 必須隨 side 判別行為改動 bump（meta 錨點後 ≥ 5）', () {
    // bc023822（LINE meta 錨點）＋ 9b670516（metaDecisive guard）改變了
    // server 端 side 判別行為，但 _cacheVersion 停在 4——已快取的高信心
    // 錯誤結果會在 24h TTL 內重播。版本停在 4 以下即此回歸重現。
    expect(
      OcrRecognitionCacheService.debugCacheVersion,
      greaterThanOrEqualTo(5),
    );
  });
}
