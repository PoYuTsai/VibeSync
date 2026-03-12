import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;

/// 圖片壓縮服務
/// 用於壓縮用戶上傳的截圖到適合 API 傳輸的大小
class ImageCompressService {
  static const int maxWidth = 1024;
  static const int quality = 85;
  static const int maxSizeBytes = 500 * 1024; // 500KB

  /// 壓縮圖片到適合上傳的大小
  /// 返回壓縮後的 JPEG bytes，或 null 如果壓縮失敗
  static Future<Uint8List?> compressImage(Uint8List imageBytes) async {
    try {
      // 解碼圖片取得尺寸
      final image = img.decodeImage(imageBytes);
      if (image == null) return null;

      // 計算目標尺寸
      int targetWidth = image.width;
      int targetHeight = image.height;

      if (image.width > maxWidth) {
        targetWidth = maxWidth;
        targetHeight = (image.height * maxWidth / image.width).round();
      }

      // 壓縮
      final result = await FlutterImageCompress.compressWithList(
        imageBytes,
        minWidth: targetWidth,
        minHeight: targetHeight,
        quality: quality,
        format: CompressFormat.jpeg,
      );

      // 檢查大小
      if (result.length > maxSizeBytes) {
        // 再次壓縮，降低品質
        return await FlutterImageCompress.compressWithList(
          imageBytes,
          minWidth: targetWidth,
          minHeight: targetHeight,
          quality: 60,
          format: CompressFormat.jpeg,
        );
      }

      return result;
    } catch (e) {
      return null;
    }
  }

  /// 檢查圖片格式是否支援
  static bool isSupportedFormat(String? mimeType) {
    if (mimeType == null) return false;
    return mimeType == 'image/jpeg' ||
        mimeType == 'image/jpg' ||
        mimeType == 'image/png';
  }

  /// 將 bytes 轉成 base64
  static String toBase64(Uint8List bytes) {
    return base64Encode(bytes);
  }
}
