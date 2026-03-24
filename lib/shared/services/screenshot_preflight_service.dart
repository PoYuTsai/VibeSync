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
        '這張圖打不開，請重新截圖後再試。',
      );
    }

    final width = decoded.width;
    final height = decoded.height;
    final aspectRatio = height / width;
    final isLandscapeCrop = width >= height;
    final isLowResolution = width < _warnMinWidth || height < _warnMinHeight;

    if (width < _hardRejectMinEdge || height < _hardRejectMinEdge) {
      return ScreenshotPreflightResult.reject(
        '這張圖太小了，請換更清楚的聊天截圖。',
        width: width,
        height: height,
      );
    }

    if (isLandscapeCrop && isLowResolution) {
      return ScreenshotPreflightResult.warn(
        '這張圖裁得比較橫，也稍微偏小。可以先試試看；若內容抓不準，建議補上更多前後文。',
        width: width,
        height: height,
      );
    }

    if (isLandscapeCrop) {
      return ScreenshotPreflightResult.warn(
        '這張圖裁得比較橫，前後文可能不夠。若抓不準，建議多截一點聊天內容。',
        width: width,
        height: height,
      );
    }

    if (aspectRatio < 1.2) {
      return ScreenshotPreflightResult.warn(
        '這張圖帶到的前後文比較少。若抓不準，建議補上前後幾則訊息。',
        width: width,
        height: height,
      );
    }

    if (aspectRatio > 5.8) {
      return ScreenshotPreflightResult.warn(
        '這張圖很長，拆成 2 到 3 張通常會更穩。',
        width: width,
        height: height,
      );
    }

    if (isLowResolution) {
      return ScreenshotPreflightResult.warn(
        '這張圖稍微偏糊，可以先試試看；若抓不準，建議截近一點或換更清楚的圖。',
        width: width,
        height: height,
      );
    }

    if (width < _comfortableMinWidth || height < _comfortableMinHeight) {
      return ScreenshotPreflightResult.warn(
        '這張圖偏小，若抓不準，建議裁近一點再試。',
        width: width,
        height: height,
      );
    }

    return ScreenshotPreflightResult.allow(width: width, height: height);
  }
}
