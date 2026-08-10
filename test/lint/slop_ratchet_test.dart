// 去 slop 棘輪測試（DESIGN.md 階段 D）。
//
// 與 slop_baseline.json 比對：任一檔任一檢查的計數「超過」基準＝紅
// （新 slop 進場）；「低於」基準＝綠但提示重產基準把棘輪鎖緊。
// 還債後重產基準：dart test/lint/slop_baseline_generator.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'slop_scan.dart';

void main() {
  test('lib/ 無新增 slop（tiny font／off-scale radius／raw color／彩色陰影）',
      () {
    final baselineFile = File('test/lint/slop_baseline.json');
    expect(baselineFile.existsSync(), isTrue,
        reason: '缺 slop_baseline.json——跑 dart test/lint/slop_baseline_generator.dart 產生');
    final baseline = decodeBaseline(baselineFile.readAsStringSync());
    final current = scanLib(Directory('lib'));

    final regressions = <String>[];
    final improvements = <String>[];

    final checks = {...baseline.keys, ...current.keys};
    for (final check in checks) {
      final baseFiles = baseline[check] ?? const <String, int>{};
      final curFiles = current[check] ?? const <String, int>{};
      for (final path in {...baseFiles.keys, ...curFiles.keys}) {
        final base = baseFiles[path] ?? 0;
        final cur = curFiles[path] ?? 0;
        if (cur > base) {
          regressions.add('[$check] $path：$base → $cur（+${cur - base}）');
        } else if (cur < base) {
          improvements.add('[$check] $path：$base → $cur');
        }
      }
    }

    if (improvements.isNotEmpty) {
      // 還了債＝好事；提示鎖緊棘輪，不擋。
      // ignore: avoid_print
      print('👍 slop 減少 ${improvements.length} 筆，'
          '記得重產基準鎖緊棘輪：dart test/lint/slop_baseline_generator.dart');
    }

    expect(
      regressions,
      isEmpty,
      reason: '偵測到新增 slop（規則見 DESIGN.md）：\n${regressions.join('\n')}\n'
          '刻意保留請登記 DESIGN.md §7 並加進 slop_scan.dart 白名單。',
    );
  });
}
