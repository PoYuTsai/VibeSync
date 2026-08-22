// 架構回歸：AnalyzeChat presentation sections 的依賴邊界（recursive）。
//
// Work C 抽出的深 presentation 模組必須是被動的：
// 1. 不 import flutter_riverpod——provider 解析屬 screen/composition root。
// 2. 不 import 任何 /data/ 路徑（含 data/services、data/repositories、
//    notifiers、providers）；wire/reactive 型別由 screen 映射成 view model。
// 3. 不 import /application/——副作用協調屬 screen 持有的 coordinator。
// 4. 不 import supabase——網路/後端存取不進渲染層。
// 5. 除 domain 純服務（/domain/services/，無 IO 的展示政策函式）與
//    app_haptics（UI 觸覺回饋，無資料/網路存取）外，不 import 任何
//    services 路徑（core/services、shared/services）。
//
// domain 實體與其他 presentation/shared widgets 允許。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _sectionsDir = 'lib/features/analysis/presentation/sections';

void main() {
  final files = Directory(_sectionsDir)
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  test('掃描器涵蓋 sections 全樹（目錄不存在或空樹即假綠，必須先失敗）', () {
    expect(
      files,
      isNotEmpty,
      reason: 'presentation/sections 應存在且至少含一個抽出的模組；'
          '目錄被移走時本守門不得靜默通過',
    );
  });

  for (final file in files) {
    final relative = file.path.substring(_sectionsDir.length + 1);
    final imports = file
        .readAsStringSync()
        .split('\n')
        .where((line) => line.trimLeft().startsWith('import '))
        .toList();

    test('$relative：不 import Riverpod', () {
      expect(
        imports.where((line) => line.contains('flutter_riverpod')),
        isEmpty,
        reason: '被動 section 不得自行解析 provider',
      );
    });

    test('$relative：不 import 任何 /data/ 路徑', () {
      expect(
        imports.where((line) => line.contains('/data/')),
        isEmpty,
        reason: 'wire/reactive 型別由 screen 映射成 view model 再傳入',
      );
    });

    test('$relative：不 import /application/', () {
      expect(
        imports.where((line) => line.contains('/application/')),
        isEmpty,
        reason: '副作用協調屬 screen 持有的 coordinator',
      );
    });

    test('$relative：不 import supabase', () {
      expect(
        imports.where((line) => line.contains('supabase')),
        isEmpty,
        reason: '網路/後端存取不進渲染層',
      );
    });

    test('$relative：不 import services（domain 純服務與 app_haptics 除外）', () {
      expect(
        imports.where(
          (line) =>
              line.contains('/services/') &&
              !line.contains('/domain/services/') &&
              !line.contains('app_haptics.dart'),
        ),
        isEmpty,
        reason: 'core/shared/data services 屬副作用層；section 只能收展示資料與 callback',
      );
    });
  }
}
