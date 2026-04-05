import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;

/// Compresses screenshots for OCR while preserving enough text clarity.
///
/// The goal here is not maximum compression. It is fast upload + stable OCR.
/// We therefore keep a relatively generous primary pass, then only downsize
/// more aggressively when the result still exceeds the upload budget.
class ImageCompressService {
  static const int maxWidth = 960;
  static const int maxHeight = 2048;
  static const int fallbackMaxWidth = 900;
  static const int fallbackMaxHeight = 1920;
  static const int quality = 78;
  static const int fallbackQuality = 60;
  static const int maxSizeBytes = 350 * 1024; // 350KB
  static const int passThroughSizeBytes = 280 * 1024;

  static bool _isLikelyJpeg(Uint8List bytes) {
    return bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF;
  }

  static ({int width, int height}) _targetDimensions(
    img.Image image, {
    bool fallback = false,
  }) {
    final maxTargetWidth = fallback ? fallbackMaxWidth : maxWidth;
    final maxTargetHeight = fallback ? fallbackMaxHeight : maxHeight;

    final widthScale = maxTargetWidth / image.width;
    final heightScale = maxTargetHeight / image.height;
    final scale = [1.0, widthScale, heightScale].reduce(
      (value, element) => value < element ? value : element,
    );

    if (scale >= 1.0) {
      return (width: image.width, height: image.height);
    }

    return (
      width: (image.width * scale).round(),
      height: (image.height * scale).round(),
    );
  }

  static Future<Uint8List> _compressWithTarget(
    Uint8List imageBytes, {
    required int width,
    required int height,
    required int quality,
  }) {
    return FlutterImageCompress.compressWithList(
      imageBytes,
      minWidth: width,
      minHeight: height,
      quality: quality,
      format: CompressFormat.jpeg,
    );
  }

  /// Returns compressed JPEG bytes, or null if compression fails.
  static Future<Uint8List?> compressImage(Uint8List imageBytes) async {
    try {
      final image = img.decodeImage(imageBytes);
      if (image == null) return null;

      final primary = _targetDimensions(image);
      final isAlreadyWithinPrimaryTarget =
          primary.width == image.width && primary.height == image.height;

      if (_isLikelyJpeg(imageBytes) &&
          isAlreadyWithinPrimaryTarget &&
          imageBytes.length <= passThroughSizeBytes) {
        return imageBytes;
      }

      final result = await _compressWithTarget(
        imageBytes,
        width: primary.width,
        height: primary.height,
        quality: quality,
      );

      if (result.length > maxSizeBytes) {
        final fallback = _targetDimensions(image, fallback: true);
        return await _compressWithTarget(
          imageBytes,
          width: fallback.width,
          height: fallback.height,
          quality: fallbackQuality,
        );
      }

      return result;
    } catch (_) {
      return null;
    }
  }

  /// Checks whether the selected image format is supported.
  static bool isSupportedFormat(String? mimeType) {
    if (mimeType == null) return true;

    final supported = [
      'image/jpeg',
      'image/jpg',
      'image/png',
      'image/heic',
      'image/heif',
      'image/webp',
    ];
    return supported.contains(mimeType.toLowerCase());
  }

  /// Encodes bytes into base64.
  static String toBase64(Uint8List bytes) {
    return base64Encode(bytes);
  }
}
