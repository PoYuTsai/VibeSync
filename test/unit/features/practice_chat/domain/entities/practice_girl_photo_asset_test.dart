import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_girl_catalog.dart';

void main() {
  test('每位 photoAssetPath = assets/images/practice_girls/{photoId}.jpg', () {
    for (final g in practiceGirlProfiles) {
      expect(
        g.photoAssetPath,
        'assets/images/practice_girls/${g.photoId}.jpg',
      );
    }
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
