// 動態頁 debug 假資料的 release 隔離守門（2026-08-24 複審補做）。
//
// `practice_moments_debug_fixtures.dart` 的檔頭宣告「機械證明在本檔」——
// 在此之前**本檔並不存在**，那句話是空頭支票。這種註解比沒有註解更糟：
// 它讓下一個人以為有守門，於是不再自己確認。
//
// 守什麼：D3 的假資料是**驗收工具，不是產品功能**。它必須：
//   1. 只被 `practice_moments_screen.dart` 引用（唯一引用點）
//   2. 每個引用點都包在 `if (kDebugMode)` 裡（編譯期消除，不是 runtime 判斷）
//   3. 不被任何 provider／service／entity 碰到（那些會進 release）
//
// 為什麼是靜態掃描而不是跑起來看：tree-shaking 只發生在 release AOT 編譯，
// `flutter test` 跑的是 debug JIT，**測不出來**。能在測試裡做的就是釘死
// 「讓 tree-shaking 得以成立的那個前提」——引用點全部在 kDebugMode 之下。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _fixtures = 'practice_moments_debug_fixtures.dart';
const _allowedImporter =
    'lib/features/practice_chat/presentation/screens/practice_moments_screen.dart';

List<File> _libDartFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

void main() {
  test('debug 假資料檔真的存在，且守門對象沒有被改名', () {
    final fixtures = _libDartFiles()
        .where((f) => f.path.endsWith(_fixtures))
        .toList();
    expect(
      fixtures.length,
      1,
      reason: '找不到 $_fixtures（或有多份）。改名時請同步本守門，'
          '否則這支測試會安靜地變成什麼都沒守。',
    );
  });

  test('lib/ 內只有動態頁會 import debug 假資料', () {
    final offenders = <String>[];
    for (final file in _libDartFiles()) {
      if (file.path.endsWith(_fixtures)) continue;
      final source = file.readAsStringSync();
      if (!source.contains(_fixtures)) continue;
      final normalized = file.path.replaceAll(r'\', '/');
      if (!normalized.endsWith(_allowedImporter)) {
        offenders.add(normalized);
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: '假資料被動態頁以外的檔案引用了。多一個引用點就多一條 '
          'release 洩漏路徑（尤其 provider／service／entity 一定會進 release）：\n'
          '${offenders.join('\n')}',
    );
  });

  test('動態頁對假資料的每一處使用都在 kDebugMode 之下', () {
    final screen = File(_allowedImporter);
    expect(screen.existsSync(), isTrue, reason: '找不到 $_allowedImporter');
    final source = screen.readAsStringSync();

    // 假資料檔對外的 API 名稱；import 那一行本身不算使用點。
    const symbols = ['practiceMomentsDebugFeed', 'PracticeMomentsDebugBar'];
    final guardAt = source.indexOf('if (kDebugMode)');
    expect(
      guardAt,
      greaterThan(-1),
      reason: '動態頁裡找不到 if (kDebugMode) 區塊——假資料失去編譯期消除的前提',
    );

    // 掃出 kDebugMode 區塊的括號範圍，所有使用點都必須落在裡面。
    final blockStart = source.indexOf('{', guardAt);
    var depth = 0;
    var blockEnd = blockStart;
    for (var i = blockStart; i < source.length; i++) {
      if (source[i] == '{') depth++;
      if (source[i] == '}') {
        depth--;
        if (depth == 0) {
          blockEnd = i;
          break;
        }
      }
    }
    expect(blockEnd, greaterThan(blockStart), reason: 'kDebugMode 區塊括號不配對');

    final offenders = <String>[];
    for (final symbol in symbols) {
      var from = 0;
      while (true) {
        final at = source.indexOf(symbol, from);
        if (at == -1) break;
        from = at + symbol.length;
        // import 行不算使用點。
        final lineStart = source.lastIndexOf('\n', at) + 1;
        final line = source.substring(
          lineStart,
          source.indexOf('\n', at) == -1 ? source.length : source.indexOf('\n', at),
        );
        if (line.trimLeft().startsWith('import ')) continue;
        if (at < blockStart || at > blockEnd) {
          final lineNo = source.substring(0, at).split('\n').length;
          offenders.add('$_allowedImporter:$lineNo → $symbol');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: '假資料的使用點跑到 if (kDebugMode) 外面了。'
          'kDebugMode 是 const bool，只有包在它裡面 release AOT 才會整段消除；'
          '在外面就是**會被編譯進 release**：\n${offenders.join('\n')}',
    );
  });

  test('假資料不被任何 provider／service／entity 碰到', () {
    final risky = _libDartFiles().where((f) {
      final p = f.path.replaceAll(r'\', '/');
      return p.contains('/data/') || p.contains('/domain/');
    });
    final offenders = <String>[];
    for (final file in risky) {
      if (file.readAsStringSync().contains(_fixtures)) {
        offenders.add(file.path);
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'data/domain 層碰到了 debug 假資料——那些檔案一定會進 release，'
          '而且會讓假貼文有機會流進正式路徑：\n${offenders.join('\n')}',
    );
  });
}
