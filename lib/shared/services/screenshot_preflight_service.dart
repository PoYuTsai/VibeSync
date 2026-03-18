import 'dart:typed_data';

import 'package:image/image.dart' as img;

enum ScreenshotPreflightDecision {
  allow,
  warn,
  reject,
}

class ScreenshotPreflightResult {
  final ScreenshotPreflightDecision decision;
  final String? message;
  final int? width;
  final int? height;

  const ScreenshotPreflightResult({
    required this.decision,
    this.message,
    this.width,
    this.height,
  });

  bool get isRejected => decision == ScreenshotPreflightDecision.reject;
  bool get isWarning => decision == ScreenshotPreflightDecision.warn;

  factory ScreenshotPreflightResult.allow({
    int? width,
    int? height,
  }) {
    return ScreenshotPreflightResult(
      decision: ScreenshotPreflightDecision.allow,
      width: width,
      height: height,
    );
  }

  factory ScreenshotPreflightResult.warn(
    String message, {
    int? width,
    int? height,
  }) {
    return ScreenshotPreflightResult(
      decision: ScreenshotPreflightDecision.warn,
      message: message,
      width: width,
      height: height,
    );
  }

  factory ScreenshotPreflightResult.reject(
    String message, {
    int? width,
    int? height,
  }) {
    return ScreenshotPreflightResult(
      decision: ScreenshotPreflightDecision.reject,
      message: message,
      width: width,
      height: height,
    );
  }
}

class ScreenshotPreflightService {
  const ScreenshotPreflightService._();

  static ScreenshotPreflightResult inspect(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return ScreenshotPreflightResult.reject(
        '這張圖片無法讀取，請重新截圖後再試。',
      );
    }

    final width = decoded.width;
    final height = decoded.height;

    if (width < 540 || height < 540) {
      return ScreenshotPreflightResult.reject(
        '這張截圖解析度太低，請上傳更清楚的聊天畫面。',
        width: width,
        height: height,
      );
    }

    if (width >= height) {
      return ScreenshotPreflightResult.reject(
        '這看起來不像直式聊天截圖，請改傳手機聊天畫面。',
        width: width,
        height: height,
      );
    }

    final aspectRatio = height / width;
    if (aspectRatio < 1.2) {
      return ScreenshotPreflightResult.reject(
        '這張圖片比例不像聊天截圖，請改傳完整直式對話畫面。',
        width: width,
        height: height,
      );
    }

    if (aspectRatio > 5.8) {
      return ScreenshotPreflightResult.warn(
        '這張截圖很長，建議拆成 2-3 張，辨識會更穩。',
        width: width,
        height: height,
      );
    }

    if (width < 720 || height < 1200) {
      return ScreenshotPreflightResult.warn(
        '這張截圖解析度偏低，若辨識不穩建議裁近一點再重試。',
        width: width,
        height: height,
      );
    }

    return ScreenshotPreflightResult.allow(width: width, height: height);
  }
}
