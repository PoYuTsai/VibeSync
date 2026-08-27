// AppBar 標題字體守門（2026-08-27）。
//
// Eric 真機回報「新增對象」的標題字體跟其他頁不一樣。根因不是那一頁寫錯，
// 而是 AppBar 沒有標題 style 時會落回 Flutter 的 `textTheme.titleLarge`：
// iOS 上那是 `.SF UI Display` 22 / w400，字體家族、字級、字重都跟 App 其他
// 文字（`.SF UI Text`）不同，中文更明顯。
//
// 制度性堵死兩件事：
// 1. ThemeData 一定要綁 AppBarTheme.titleTextStyle = AppTypography.appBarTitle，
//    這樣任何沒自帶 style 的 AppBar 都不會掉回 Flutter 預設。
// 2. lib/ 內 AppBar 的 title 不准自己手寫 TextStyle(...)——要嘛不給 style
//    （吃 AppBarTheme），要嘛走 AppTypography 檔位。手寫 TextStyle 只會蓋掉
//    顏色卻繼續繼承錯的字體家族／字級，正是這次的坑。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/core/theme/app_theme.dart';
import 'package:vibesync/core/theme/app_typography.dart';

/// 從 [source] 的 [openParenIndex]（指向 `(`）掃到配對的 `)`，回傳其索引。
int _matchingParen(String source, int openParenIndex) {
  var depth = 0;
  for (var i = openParenIndex; i < source.length; i++) {
    final char = source[i];
    if (char == '(') depth++;
    if (char == ')') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return source.length - 1;
}

/// 取出 AppBar 自己那層 `title:` 的值（略過 actions/bottom 裡巢狀 widget 的
/// 同名參數）；掃到同層的逗號或該層結束為止。找不到回傳 null。
String? _ownTitleArgument(String call) {
  var depth = 0;
  for (var i = 0; i < call.length; i++) {
    final char = call[i];
    if (char == '(' || char == '[' || char == '{') {
      depth++;
      continue;
    }
    if (char == ')' || char == ']' || char == '}') {
      depth--;
      continue;
    }
    // depth 1 = AppBar( 自己的參數層。
    if (depth != 1 || !call.startsWith('title:', i)) continue;
    if (i > 0 && RegExp(r'[A-Za-z0-9_]').hasMatch(call[i - 1])) continue;

    final valueStart = i + 'title:'.length;
    var valueDepth = 0;
    for (var j = valueStart; j < call.length; j++) {
      final c = call[j];
      if (c == '(' || c == '[' || c == '{') valueDepth++;
      if (c == ')' || c == ']' || c == '}') {
        if (valueDepth == 0) return call.substring(valueStart, j);
        valueDepth--;
      }
      if (c == ',' && valueDepth == 0) return call.substring(valueStart, j);
    }
    return call.substring(valueStart);
  }
  return null;
}

void main() {
  test('AppBarTheme 綁住 AppTypography.appBarTitle', () {
    final titleStyle = AppTheme.darkTheme.appBarTheme.titleTextStyle;

    expect(
      titleStyle,
      isNotNull,
      reason: 'AppBarTheme.titleTextStyle 為 null 時，AppBar 標題會落回 Flutter '
          '預設 textTheme.titleLarge（iOS = .SF UI Display 22/w400），'
          '字體與全 App 不一致',
    );
    expect(titleStyle!.fontSize, AppTypography.appBarTitle.fontSize);
    expect(titleStyle.fontWeight, AppTypography.appBarTitle.fontWeight);
    expect(titleStyle.color, AppTypography.appBarTitle.color);
    expect(
      titleStyle.fontFamily,
      isNull,
      reason: '字體家族要跟 App 其他文字一樣吃平台預設，不要指定 .SF UI Display',
    );
  });

  test('lib/ 內 AppBar 的 title 不自己手寫 TextStyle', () {
    final offenders = <String>[];

    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));

    for (final file in files) {
      final source = file.readAsStringSync();
      var searchFrom = 0;
      while (true) {
        final start = source.indexOf('AppBar(', searchFrom);
        if (start == -1) break;
        // 跳過 SliverAppBar( / brandAppBar( 這類子字串命中。
        if (start > 0 && RegExp(r'[A-Za-z0-9_]').hasMatch(source[start - 1])) {
          searchFrom = start + 'AppBar('.length;
          continue;
        }
        final end = _matchingParen(source, start + 'AppBar('.length - 1);
        final call = source.substring(start, end + 1);
        searchFrom = end + 1;

        final title = _ownTitleArgument(call);
        if (title == null || !title.contains('TextStyle(')) continue;

        final line = source.substring(0, start).split('\n').length;
        offenders.add('${file.path}:$line');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'AppBar 標題手寫 TextStyle 只蓋得掉顏色，字體家族／字級／字重仍會'
          '繼承 Flutter 預設（iOS = .SF UI Display 22/w400），跟其他頁不一致。'
          '請拿掉 style 讓它吃 AppBarTheme，或改用 AppTypography.appBarTitle：\n'
          '${offenders.join('\n')}',
    );
  });
}
