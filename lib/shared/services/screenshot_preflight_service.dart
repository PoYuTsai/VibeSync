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

  static const int _hardRejectMinEdge = 360;
  static const int _warnMinWidth = 540;
  static const int _warnMinHeight = 540;
  static const int _comfortableMinWidth = 720;
  static const int _comfortableMinHeight = 1200;

  static ScreenshotPreflightResult inspect(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return ScreenshotPreflightResult.reject(
        '這張圖片無法讀取，請重新截圖後再試。',
      );
    }

    final width = decoded.width;
    final height = decoded.height;
    final aspectRatio = height / width;
    final isLandscapeCrop = width >= height;
    final isLowResolution = width < _warnMinWidth || height < _warnMinHeight;

    if (width < _hardRejectMinEdge || height < _hardRejectMinEdge) {
      return ScreenshotPreflightResult.reject(
        '這張截圖解析度太低，請上傳更清楚的聊天畫面。',
        width: width,
        height: height,
      );
    }

    if (isLandscapeCrop && isLowResolution) {
      return ScreenshotPreflightResult.warn(
        '這張圖裁得比較橫，解析度也偏低，仍可先試試看；若辨識不穩，建議補上更多上下文或改傳直式截圖。',
        width: width,
        height: height,
      );
    }

    if (isLandscapeCrop) {
      return ScreenshotPreflightResult.warn(
        '這張圖裁得比較橫，可能少了上下文；若辨識不穩，建議補上更多聊天內容再試。',
        width: width,
        height: height,
      );
    }

    if (aspectRatio < 1.2) {
      return ScreenshotPreflightResult.warn(
        '這張圖上下文偏少，若辨識不穩，建議補上更多前後訊息再試。',
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

    if (isLowResolution) {
      return ScreenshotPreflightResult.warn(
        '這張截圖解析度偏低，但可以先試試看；若辨識不穩，建議裁近一點或換更清楚的截圖。',
        width: width,
        height: height,
      );
    }

    if (width < _comfortableMinWidth || height < _comfortableMinHeight) {
      return ScreenshotPreflightResult.warn(
        '這張截圖解析度偏低，若辨識不穩建議裁近一點再重試。',
        width: width,
        height: height,
      );
    }

    return ScreenshotPreflightResult.allow(width: width, height: height);
  }
}
