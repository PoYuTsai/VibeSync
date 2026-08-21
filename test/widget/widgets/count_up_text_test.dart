// test/widget/widgets/count_up_text_test.dart
//
// CountUpText 契約鎖：開場從 0 起跑、整數落點、關動畫直接落地、
// animate:false 不重播、之後 value 真的變了照樣補間。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vibesync/shared/widgets/motion/count_up_text.dart';

Widget _host(Widget child, {bool disableAnimations = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Scaffold(body: Center(child: child)),
      ),
    );

int _shown(WidgetTester t) =>
    int.parse(t.widget<Text>(find.byType(Text)).data!);

void main() {
  testWidgets('第一格是 0，收斂後停在目標值', (t) async {
    await t.pumpWidget(_host(const CountUpText(value: 36, haptic: false)));

    expect(_shown(t), 0);

    await t.pump(const Duration(milliseconds: 300));
    final mid = _shown(t);
    expect(mid, greaterThan(0));
    expect(mid, lessThan(36));

    await t.pumpAndSettle();
    expect(_shown(t), 36);
  });

  testWidgets('全程只顯示整數（GSAP snap: 1）', (t) async {
    await t.pumpWidget(_host(const CountUpText(value: 87, haptic: false)));

    for (var i = 0; i < 20; i++) {
      final text = t.widget<Text>(find.byType(Text)).data!;
      expect(int.tryParse(text), isNotNull, reason: '出現非整數中間態：$text');
      await t.pump(const Duration(milliseconds: 50));
    }
    await t.pumpAndSettle();
    expect(_shown(t), 87);
  });

  testWidgets('跑動過程單調遞增，不會回頭', (t) async {
    await t.pumpWidget(_host(const CountUpText(value: 64, haptic: false)));

    var previous = _shown(t);
    for (var i = 0; i < 25; i++) {
      await t.pump(const Duration(milliseconds: 40));
      final current = _shown(t);
      expect(current, greaterThanOrEqualTo(previous));
      previous = current;
    }
    await t.pumpAndSettle();
    expect(_shown(t), 64);
  });

  testWidgets('reduce motion：直接是終值，不閃 0', (t) async {
    await t.pumpWidget(_host(
      const CountUpText(value: 36, haptic: false),
      disableAnimations: true,
    ));

    expect(_shown(t), 36);
  });

  testWidgets('animate: false：直接是終值，不重播', (t) async {
    await t.pumpWidget(
      _host(const CountUpText(value: 36, haptic: false, animate: false)),
    );

    expect(_shown(t), 36);
    await t.pumpAndSettle();
    expect(_shown(t), 36);
  });

  testWidgets('animate: false 之後 value 真的變了，照樣補間過去', (t) async {
    await t.pumpWidget(
      _host(const CountUpText(value: 36, haptic: false, animate: false)),
    );
    expect(_shown(t), 36);

    // 「這次不播開場」不等於「這張卡從此不准動」：新分數進來要從 36 走到 80，
    // 而不是從 0 重跑、也不是硬跳。
    await t.pumpWidget(
      _host(const CountUpText(value: 80, haptic: false, animate: false)),
    );
    await t.pump(const Duration(milliseconds: 300));
    final mid = _shown(t);
    expect(mid, greaterThan(36));
    expect(mid, lessThan(80));

    await t.pumpAndSettle();
    expect(_shown(t), 80);
  });

  testWidgets('跑完會回呼 onEnd 一次', (t) async {
    var ended = 0;
    await t.pumpWidget(_host(
      CountUpText(value: 36, haptic: false, onEnd: () => ended++),
    ));

    expect(ended, 0);
    await t.pumpAndSettle();
    expect(ended, 1);
  });

  testWidgets('value 為 0 時不跑也不炸', (t) async {
    await t.pumpWidget(_host(const CountUpText(value: 0, haptic: false)));

    expect(_shown(t), 0);
    await t.pumpAndSettle();
    expect(_shown(t), 0);
  });
}
