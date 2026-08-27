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

  test('沒有任何地方把 handoffLocationFor 的結果直接 push', () {
    for (final banned in const [
      'push(OpeningRescueScreen.handoffLocationFor',
      'push(handoffLocationFor',
    ]) {
      expect(
        source.contains(banned),
        isFalse,
        reason: '$banned 是複審退回的舊寫法：已綁定對象會疊出第二張相同的卡，'
            '未綁定則把開場救星留在返回路徑上。目的地網址請交給 '
            'navigateToHandoff 決定堆疊怎麼變。',
      );
    }
  });

  test('navigateToHandoff 仍是 OpeningRescueScreen 的靜態入口', () {
    expect(
      source.contains(
        'static void navigateToHandoff(BuildContext context, {String? partnerId})',
      ),
      isTrue,
      reason: '簽名變了就更新本守門與 handoff 導航測試，不要讓守門空轉。',
    );
  });

  test('導航規則是「收回首頁再推一頁」，不是看誰在下面', () {
    final start = source.indexOf(
      'static void navigateToHandoff(BuildContext context, {String? partnerId})',
    );
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
