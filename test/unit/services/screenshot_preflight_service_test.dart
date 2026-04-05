import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:vibesync/shared/services/screenshot_preflight_service.dart';

void main() {
  Uint8List buildImageBytes({
    required int width,
    required int height,
  }) {
    final image = img.Image(width: width, height: height);
    img.fill(image, color: img.ColorRgb8(40, 40, 40));
    return Uint8List.fromList(img.encodeJpg(image));
  }

  group('ScreenshotPreflightService.inspect', () {
    test('rejects images that are truly too small', () {
      final result = ScreenshotPreflightService.inspect(
        buildImageBytes(width: 320, height: 320),
      );

      expect(result.decision, ScreenshotPreflightDecision.reject);
      expect(result.message, contains('太小了'));
    });

    test('warns instead of rejecting tight landscape chat crops', () {
      final result = ScreenshotPreflightService.inspect(
        buildImageBytes(width: 780, height: 484),
      );

      expect(result.decision, ScreenshotPreflightDecision.warn);
      expect(result.message, contains('裁得比較橫'));
    });

    test('allows normal portrait screenshots', () {
      final result = ScreenshotPreflightService.inspect(
        buildImageBytes(width: 1170, height: 2532),
      );

      expect(result.decision, ScreenshotPreflightDecision.allow);
    });
  });
}
