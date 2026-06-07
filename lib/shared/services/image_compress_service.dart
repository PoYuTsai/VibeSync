import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;

/// 圖片壓縮服務
/// 用於壓縮用戶上傳的截圖到適合 API 傳輸的大小
class ImageCompressService {
  static const int maxSizeBytes = 600 * 1024; // Match Edge image validation.

  // Progressive fallback：寬度從大到小、品質從高到低。
  // 用於對付拼貼版面、高解析度截圖等壓縮阻抗高的輸入。
  static const List<(int width, int quality)> _compressionAttempts = [
    (960, 78),
    (960, 60),
    (768, 60),
    (768, 45),
    (640, 45),
    (640, 30),
  ];

  /// 壓縮圖片到適合上傳的大小
  /// 壓得到目標 → 回該結果；全部嘗試都超標 → 回最小的版本（由 caller 決定擋不擋）
  /// 解碼失敗或例外 → 回 null
  static Future<Uint8List?> compressImage(Uint8List imageBytes) async {
    try {
      final image = img.decodeImage(imageBytes);
      if (image == null) return null;

      Uint8List? smallest;
      for (final (width, q) in _compressionAttempts) {
        int targetWidth = image.width;
        int targetHeight = image.height;
        if (image.width > width) {
          targetWidth = width;
          targetHeight = (image.height * width / image.width).round();
        }

        final result = await FlutterImageCompress.compressWithList(
          imageBytes,
          minWidth: targetWidth,
          minHeight: targetHeight,
          quality: q,
          format: CompressFormat.jpeg,
        );

        if (result.length <= maxSizeBytes) {
          return result;
        }
        if (smallest == null || result.length < smallest.length) {
          smallest = result;
        }
      }

      return smallest;
    } catch (e) {
      return null;
    }
  }

  /// 檢查圖片格式是否支援
  /// iOS 截圖通常是 HEIC 格式，也需要支援
  /// 當 mimeType 為 null 時，允許嘗試處理（讓圖片庫判斷）
  static bool isSupportedFormat(String? mimeType) {
    // 如果沒有 mimeType，允許嘗試處理
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
