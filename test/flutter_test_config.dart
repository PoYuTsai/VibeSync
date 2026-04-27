// Flutter 自動偵測：每次 `flutter test` 都會 invoke 此檔的 testExecutable，
// 在任何 test 跑之前 set up 共用環境。
//
// 為何要：repo 既有大量斷言寫的是 zh_TW 文案（'50 則' / '熱情' / '推薦的回覆'
// 等）。Flutter 的 platformDispatcher.locale 預設 en_US，造成 `Intl` fallback
// 出英文，於是這些斷言在 Linux CI runner 全炸（mac/win 開發機因 OS locale
// 是 zh_TW 而誤打誤撞 pass）。本檔將每個 test 的 locale 強制成 zh_TW，
// 一次性解決 86/391 個 locale-driven failures，同時讓未來 Linux dev /
// Codespaces 跑測試也走 zh_TW。
//
// 個別 test 仍可在 setUp 用 `binding.platformDispatcher.localeTestValue =`
// 蓋過此預設（例如：將來想測 EN UI 行為時）。

import 'dart:async';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final binding = TestWidgetsFlutterBinding.instance;
  binding.platformDispatcher.localeTestValue = const Locale('zh', 'TW');
  binding.platformDispatcher.localesTestValue = const [Locale('zh', 'TW')];
  Intl.defaultLocale = 'zh_TW';
  await testMain();
}
