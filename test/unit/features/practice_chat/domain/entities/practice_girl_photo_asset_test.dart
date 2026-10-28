import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_girl_catalog.dart';

/// 讀 JPEG 檔頭的 SOF 段拿寬高（不解整張圖）。
({int width, int height}) _jpegSize(List<int> b) {
  var i = 2; // 跳過 SOI（FF D8）
  while (i + 9 < b.length) {
    if (b[i] != 0xFF) {
      i++;
      continue;
    }
    final marker = b[i + 1];
    final length = (b[i + 2] << 8) | b[i + 3];
    // SOF0–SOF15，扣掉 DHT（C4）、JPG（C8）、DAC（CC）。
    if (marker >= 0xC0 &&
        marker <= 0xCF &&
        marker != 0xC4 &&
        marker != 0xC8 &&
        marker != 0xCC) {
      return (
        height: (b[i + 5] << 8) | b[i + 6],
        width: (b[i + 7] << 8) | b[i + 8],
      );
    }
    i += 2 + length;
  }
  throw StateError('找不到 SOF 段');
}

void main() {
  test('每位 photoAssetPath = assets/images/practice_girls/{photoId}.jpg', () {
    for (final g in practiceGirlProfiles) {
      expect(
        g.photoAssetPath,
        'assets/images/practice_girls/${g.photoId}.jpg',
      );
    }
  });

  test('人物照都是直幅或正方（寬 ≤ 高）：practiceGirlPhotoCacheWidth 依這個前提算解碼寬', () {
    final landscape = <String>[];
    for (final g in practiceGirlProfiles) {
      final size = _jpegSize(File(g.photoAssetPath).readAsBytesSync());
      if (size.width > size.height) {
        landscape.add('${g.photoId} ${size.width}×${size.height}');
      }
    }
    expect(landscape, isEmpty);
  });

  test('catalog 內每位的 photo asset 實體檔都存在（bundled 守門）', () {
    final missing = <String>[];
    for (final g in practiceGirlProfiles) {
      if (!File(g.photoAssetPath).existsSync()) {
        missing.add(g.photoAssetPath);
      }
    }
    expect(missing, isEmpty,
        reason: '缺少 ${missing.length} 張：${missing.join(", ")}');
  });
}
