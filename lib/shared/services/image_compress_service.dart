import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;

/// 圖片壓縮服務
/// 用於壓縮用戶上傳的截圖到適合 API 傳輸的大小
class ImageCompressService {
  static const int maxWidth = 960;
  static const int quality = 78;
  static const int fallbackQuality = 60;
  static const int maxSizeBytes = 350 * 1024; // 350KB

  /// 壓縮圖片到適合上傳的大小
  /// 返回壓縮後的 JPEG bytes，或 null 如果壓縮失敗
  static Future<Uint8List?> compressImage(Uint8List imageBytes) async {
    try {
      final image = img.decodeImage(imageBytes);
      if (image == null) return null;

      int targetWidth = image.width;
      int targetHeight = image.height;

      if (image.width > maxWidth) {
        targetWidth = maxWidth;
        targetHeight = (image.height * maxWidth / image.width).round();
      }

      final result = await FlutterImageCompress.compressWithList(
        imageBytes,
        minWidth: targetWidth,
        minHeight: targetHeight,
        quality: quality,
        format: CompressFormat.jpeg,
      );

      if (result.length > maxSizeBytes) {
        return await FlutterImageCompress.compressWithList(
          imageBytes,
          minWidth: targetWidth,
          minHeight: targetHeight,
          quality: fallbackQuality,
          format: CompressFormat.jpeg,
        );
      }

      return result;
    } catch (_) {
      return null;
    }
  }

  /// 檢查圖片格式是否支援
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

  /// 將 bytes 轉成 base64
  static String toBase64(Uint8List bytes) {
    return base64Encode(bytes);
  }
}
