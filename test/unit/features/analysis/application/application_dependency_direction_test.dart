// 架構回歸：application 層的依賴方向。
//
// Round 2 corrective 之後，application coordinator 只能依賴具名注入的
// callable／介面：不得 import Riverpod（等於不得自行解析 provider）、
// 不得反向 import presentation。Riverpod／Hive store／具體 client 的
// 組裝一律在 composition root（analysis_providers.dart）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _applicationDir = 'lib/features/analysis/application';

void main() {
  final files = Directory(_applicationDir)
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  test('application 目錄存在且非空', () {
    expect(files, isNotEmpty);
  });

  for (final file in files) {
    final imports = file
        .readAsLinesSync()
        .where((line) => line.trimLeft().startsWith('import '))
        .toList();

    test('${file.uri.pathSegments.last}：不 import Riverpod（不得自行解析 provider）',
        () {
      expect(
        imports.where((line) => line.contains('flutter_riverpod')),
        isEmpty,
        reason: 'application 只能收具名注入的依賴；provider 解析屬 composition root',
      );
    });

    test('${file.uri.pathSegments.last}：不反向 import presentation', () {
      expect(
        imports.where((line) => line.contains('/presentation/')),
        isEmpty,
        reason: '依賴方向是 presentation → application，不可回頭',
      );
    });
  }
}
