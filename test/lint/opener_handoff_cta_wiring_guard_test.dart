// 「她回覆了，開始分析對話」CTA 的接線守門。
//
// 為什麼需要靜態守門：導航語意本身由
// test/widget/features/opener/opening_rescue_handoff_navigation_test.dart
// 用真 GoRouter 驗（pop 回既有對象卡／replace 掉開場救星／深連結退路），
// 但那支測試掛的是 opener 的 stub。真畫面進不了測試的原因寫在該檔檔頭：
// 要按到 CTA 得先種草稿、按「回看」，而 CTA 會觸發一筆 Hive 寫入，那筆真
// 磁碟 I/O 在 testWidgets 的 fake-async zone 裡收不掉，實測整支卡死到 10
// 分鐘 timeout（run 33027317044）。
//
// 於是剩下唯一沒被行為測試覆蓋的一段，就是「畫面上那顆 CTA 真的呼叫
// navigateToHandoff」。本檔守的就是這一段。
//
// 這支測試證明得了什麼：CTA 按鈕的 onPressed 裡確實叫了
// OpeningRescueScreen.navigateToHandoff，而且沒有任何地方再把
// handoffLocationFor 的結果直接 push（那正是複審退回的舊寫法）。
// 證明不了什麼：按下去之後真的長什麼樣——那是上面那支 widget test 的事。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _screenPath =
    'lib/features/opener/presentation/screens/opening_rescue_screen.dart';
const _ctaLabel = "label: '她回覆了，開始分析對話'";
const _navSignature =
    'static void navigateToHandoff(BuildContext context, {String? partnerId})';

/// CTA 的 label 與 onPressed 相鄰；給足含註解的行距，但不到整個 build 方法。
const _onPressedWindow = 900;

void main() {
  late String source;

  setUpAll(() {
    final file = File(_screenPath);
    expect(
      file.existsSync(),
      isTrue,
      reason: '$_screenPath 不存在。檔案搬家時請同步本守門，'
          '否則這支測試會安靜地變成什麼都沒守。',
    );
    source = file.readAsStringSync();
  });

  test('CTA 的 onPressed 走 navigateToHandoff，不是自己 push', () {
    final labelIndex = source.indexOf(_ctaLabel);
    expect(
      labelIndex,
      isNonNegative,
      reason: '找不到 CTA（$_ctaLabel）。改文案時請同步本守門。',
    );
    expect(
      source.indexOf(_ctaLabel, labelIndex + 1),
      -1,
      reason: 'CTA 文案出現多次，守門會盯到錯的那一個。',
    );

    final window = source.substring(
      labelIndex,
      (labelIndex + _onPressedWindow).clamp(0, source.length),
    );
    expect(
      window.contains('OpeningRescueScreen.navigateToHandoff('),
      isTrue,
      reason: 'CTA 的 onPressed 必須呼叫 navigateToHandoff——導航語意（已綁定'
          ' pop 回既有對象卡、未綁定 replace 掉開場救星）只在那個函式裡，'
          '自己 push 會把複審退回的兩個回歸原樣帶回來。',
    );
  });

  test('handoffLocationFor 只能由 navigateToHandoff 使用', () {
    // 第一輪的錯寫法是 CTA 自己 `context.push(handoffLocationFor(...))`：
    // 那等於讓「去哪」順便決定了「堆疊怎麼變」，而堆疊怎麼變要看入口是誰。
    // 現在只有 navigateToHandoff 可以拿這個網址去導航。
    final navStart = source.indexOf(_navSignature);
    expect(navStart, isNonNegative);
    final navEnd = source.indexOf('\n  static ', navStart + 1);
    expect(
      navEnd,
      greaterThan(navStart),
      reason: '找不到 navigateToHandoff 的結尾（下一個 static 成員）。'
          '檔案結構變了請同步本守門。',
    );

    const call = 'handoffLocationFor(';
    const declarationPrefix = 'static String ';
    final offenders = <String>[];
    for (var i = source.indexOf(call); i >= 0; i = source.indexOf(call, i + 1)) {
      final isDeclaration = i >= declarationPrefix.length &&
          source.substring(i - declarationPrefix.length, i) ==
              declarationPrefix;
      if (isDeclaration) continue;
      if (i > navStart && i < navEnd) continue;
      offenders.add(source.substring(i, (i + 60).clamp(0, source.length)));
    }

    expect(
      offenders,
      isEmpty,
      reason: 'handoffLocationFor 只回答「去哪」，堆疊怎麼變由 navigateToHandoff '
          '決定（先收回首頁再推一頁）。在別處直接拿它導航，就會回到複審退回的'
          '狀態：分析頁／封存頁入口落在錯的頁，文章頁留在返回路徑上。'
          '違規處：$offenders',
    );
  });

  test('navigateToHandoff 仍是 OpeningRescueScreen 的靜態入口', () {
    expect(
      source.contains(_navSignature),
      isTrue,
      reason: '簽名變了就更新本守門與 handoff 導航測試，不要讓守門空轉。',
    );
  });

  test('導航規則是「收回首頁再推一頁」，不是看誰在下面', () {
    final start = source.indexOf(_navSignature);
    expect(start, isNonNegative);
    final body = source.substring(
      start,
      (start + 400).clamp(0, source.length),
    );

    expect(
      body.contains("router.go('/')"),
      isTrue,
      reason: '必須先把堆疊收回首頁：帶 partnerId 的入口有三個（對象卡、'
          '分析頁、封存頁），未綁定的有兩個（首頁、文章頁），'
          '不收回首頁就會落在錯的頁。',
    );
    expect(
      body.contains('canPop'),
      isFalse,
      reason: 'canPop 是第一輪選錯的依據——它只知道「有沒有上一頁」，'
          '不知道那是不是對象卡。改回去會讓分析頁／封存頁入口再次退化。',
    );
  });
}
