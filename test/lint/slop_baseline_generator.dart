// 產生／更新 slop_baseline.json（在 repo 根目錄跑：
// dart test/lint/slop_baseline_generator.dart）。
// 僅在「還債後鎖緊棘輪」時重產；不得為了讓新 slop 過關而重產——
// 刻意保留走 DESIGN.md §7 登記＋slop_scan.dart 白名單。
import 'dart:io';

import 'slop_scan.dart';

void main() {
  final scan = scanLib(Directory('lib'));
  File('test/lint/slop_baseline.json')
      .writeAsStringSync('${encodeBaseline(scan)}\n');
  var total = 0;
  scan.forEach((check, files) {
    final sum = files.values.fold<int>(0, (a, b) => a + b);
    total += sum;
    stdout.writeln('$check: $sum 處（${files.length} 檔）');
  });
  stdout.writeln('基準已寫入 test/lint/slop_baseline.json（共 $total 處既存債）');
}
