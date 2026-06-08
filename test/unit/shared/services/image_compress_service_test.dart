import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/shared/services/image_compress_service.dart';

void main() {
  group('ImageCompressService', () {
    test('uses the same per-image cap as analyze-chat edge validation', () {
      expect(ImageCompressService.maxSizeBytes, 900 * 1024);
    });
  });
}
