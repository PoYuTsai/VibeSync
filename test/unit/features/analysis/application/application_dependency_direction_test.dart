// 架構回歸：application 層的依賴方向（recursive，含 ports/**）。
//
// application → 窄 port（domain/application）→ data：
// 1. 不得 import flutter_riverpod（等於不得自行解析 provider）。
// 2. 不得反向 import presentation。
// 3. 不得 import 任何 /data/ 路徑。
// 4. 不得引用 reactive/wire 型別：StreamingAnalysisState／
//    StreamingAnalyzePhase／AnalysisStreamContent／rawEvent——run 識別
//    走 AnalysisRunMetadata 窄 seam，wire decode 與顯示映射分屬 data／
//    presentation。
// 組裝一律在 composition root（analysis_providers.dart）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _applicationDir = 'lib/features/analysis/application';

const _forbiddenTypeTokens = <String>[
  'StreamingAnalysisState',
  'StreamingAnalyzePhase',
  'AnalysisStreamContent',
  'rawEvent',
];

void main() {
  final files = Directory(_applicationDir)
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  test('掃描器涵蓋 application 全樹（必須看得到 ports/ 子目錄）', () {
    expect(files, isNotEmpty);
    expect(
      files.where((file) => file.path.contains('/ports/')),
      isNotEmpty,
      reason: '遞迴掃描失效的話，ports/** 的違規會假綠',
    );
  });

  for (final file in files) {
    final relative = file.path.substring(_applicationDir.length + 1);
    final source = file.readAsStringSync();
    final imports = source
        .split('\n')
        .where((line) => line.trimLeft().startsWith('import '))
        .toList();

    test('$relative：不 import Riverpod（不得自行解析 provider）', () {
      expect(
        imports.where((line) => line.contains('flutter_riverpod')),
        isEmpty,
        reason: 'application 只能收具名注入的依賴；provider 解析屬 composition root',
      );
    });

    test('$relative：不反向 import presentation', () {
      expect(
        imports.where((line) => line.contains('/presentation/')),
        isEmpty,
        reason: '依賴方向是 presentation → application，不可回頭',
      );
    });

    test('$relative：不 import 任何 /data/ 路徑', () {
      expect(
        imports.where((line) => line.contains('/data/')),
        isEmpty,
        reason: 'application 只能經 port 觸及 data；具體型別由 adapter 供給',
      );
    });

    test('$relative：不引用 reactive/wire 型別（narrow seam 硬擋）', () {
      for (final token in _forbiddenTypeTokens) {
        expect(
          source.contains(token),
          isFalse,
          reason: '$relative 引用了 $token；application 只能認 '
              'AnalysisRunMetadata 等窄 seam 型別',
        );
      }
    });
  }
}
