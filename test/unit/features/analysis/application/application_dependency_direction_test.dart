// 架構回歸：application 層的依賴方向。
//
// application → 窄 port（domain/application）→ data：application 只能
// 依賴具名注入的 callable／port，不得 import Riverpod（等於不得自行
// 解析 provider）、不得反向 import presentation、也不得 import 任何
// /data/ 路徑（含具體 store／client／notifier 型別）。Riverpod／Hive
// ／具體 client 的組裝一律在 composition root（analysis_providers.dart）
// 以 data adapter 完成。
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

    test('${file.uri.pathSegments.last}：不 import 任何 /data/ 路徑', () {
      expect(
        imports.where((line) => line.contains('/data/')),
        isEmpty,
        reason: 'application 只能經 port 觸及 data；具體型別由 adapter 供給',
      );
    });
  }
}
