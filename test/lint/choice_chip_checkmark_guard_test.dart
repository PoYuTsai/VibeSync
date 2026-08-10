// ChoiceChip 勾勾守門（2026-08-10）。
//
// Material chip 內建勾勾的淡入淡出會在快速切換時留殘影＋寬度跳動，
// 這個坑已咬三次（ProfileChipSection→CoachFollowUpSection→問誰 chips），
// 制度性堵死：lib/ 內每個 ChoiceChip( 呼叫都必須帶 showCheckmark: false。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lib/ 內所有 ChoiceChip 都關掉 showCheckmark', () {
    final offenders = <String>[];

    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));

    for (final file in files) {
      final source = file.readAsStringSync();
      var searchFrom = 0;
      while (true) {
        final start = source.indexOf('ChoiceChip(', searchFrom);
        if (start == -1) break;
        // 跳過 BrandChoiceChip( 這類子字串命中（前一字元是識別字＝別的類名）。
        if (start > 0 && RegExp(r'[A-Za-z0-9_]').hasMatch(source[start - 1])) {
          searchFrom = start + 'ChoiceChip('.length;
          continue;
        }
        // 往後掃到括號配對結束，檢查該呼叫內有沒有 showCheckmark: false。
        var depth = 0;
        var end = start + 'ChoiceChip('.length - 1;
        for (var i = end; i < source.length; i++) {
          final char = source[i];
          if (char == '(') depth++;
          if (char == ')') {
            depth--;
            if (depth == 0) {
              end = i;
              break;
            }
          }
        }
        final call = source.substring(start, end + 1);
        if (!call.contains('showCheckmark: false')) {
          final line = source.substring(0, start).split('\n').length;
          offenders.add('${file.path}:$line');
        }
        searchFrom = end + 1;
      }
    }

    expect(offenders, isEmpty,
        reason: 'ChoiceChip 少了 showCheckmark: false（勾勾動畫＝殘影＋寬度跳動）：\n'
            '${offenders.join('\n')}');
  });
}
