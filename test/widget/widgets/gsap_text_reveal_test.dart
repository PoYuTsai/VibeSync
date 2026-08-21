// test/widget/widgets/gsap_text_reveal_test.dart
//
// GsapTextReveal 契約鎖：
//   1. 抽變體（純函數）——指定優先、scramble 需要拆字、亂數可注入 seed。
//   2. 進場拆字、收尾塌回單一 Text（find.text／可選取性／無障礙不受損）。
//   3. 五種變體都收斂，`pumpAndSettle` 不會卡住。
//   4. 全程不動文字透明度——這是全 App 殘影禁令，回歸了就紅。
//   5. 關動畫／animate:false／演到一半改名，都直接落地。
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vibesync/shared/widgets/motion/gsap_text_reveal.dart';

Widget _host(Widget child, {bool disableAnimations = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Scaffold(body: Center(child: child)),
      ),
    );

void main() {
  group('resolveVariant', () {
    test('指定變體優先於亂數', () {
      for (final v in GsapRevealVariant.values) {
        expect(
          GsapTextReveal.resolveVariant(
            requested: v,
            canSplit: true,
            random: math.Random(0),
          ),
          v,
        );
      }
    });

    test('不能拆字時 scramble 退回 popIn', () {
      expect(
        GsapTextReveal.resolveVariant(
          requested: GsapRevealVariant.scramble,
          canSplit: false,
          random: math.Random(0),
        ),
        GsapRevealVariant.popIn,
      );
    });

    test('不能拆字時抽籤池不含 scramble', () {
      for (var seed = 0; seed < 200; seed++) {
        expect(
          GsapTextReveal.resolveVariant(
            requested: null,
            canSplit: false,
            random: math.Random(seed),
          ),
          isNot(GsapRevealVariant.scramble),
        );
      }
    });

    test('能拆字時五種變體都抽得到', () {
      final seen = <GsapRevealVariant>{};
      for (var seed = 0; seed < 200; seed++) {
        seen.add(GsapTextReveal.resolveVariant(
          requested: null,
          canSplit: true,
          random: math.Random(seed),
        ));
      }
      expect(seen, GsapRevealVariant.values.toSet());
    });

    test('同一個 seed 抽到同一種（測試可鎖結果）', () {
      for (var seed = 0; seed < 20; seed++) {
        expect(
          GsapTextReveal.resolveVariant(
            requested: null,
            canSplit: true,
            random: math.Random(seed),
          ),
          GsapTextReveal.resolveVariant(
            requested: null,
            canSplit: true,
            random: math.Random(seed),
          ),
        );
      }
    });
  });

  group('進場與收尾', () {
    testWidgets('進行中逐字拆開，收斂後塌回單一 Text', (t) async {
      await t.pumpWidget(_host(const GsapTextReveal(
        text: '小美',
        variant: GsapRevealVariant.riseMask,
      )));

      expect(find.text('小'), findsOneWidget);
      expect(find.text('美'), findsOneWidget);
      expect(find.text('小美'), findsNothing);

      await t.pumpAndSettle();

      // 塌回單一 Text：find.text 找得到整串，無障礙樹與可選取性回到正常。
      expect(find.text('小美'), findsOneWidget);
      expect(find.text('小'), findsNothing);
    });

    testWidgets('五種變體都收斂到完整文字', (t) async {
      for (final v in GsapRevealVariant.values) {
        await t.pumpWidget(_host(GsapTextReveal(
          key: ValueKey(v),
          text: '小美人',
          variant: v,
        )));
        await t.pumpAndSettle();
        expect(find.text('小美人'), findsOneWidget, reason: '$v 沒收斂');
      }
    });

    testWidgets('超過 maxSplitLength 就整串一起動，不拆字', (t) async {
      const long = '這是一個非常非常長的對象名稱';
      await t.pumpWidget(_host(const GsapTextReveal(
        text: long,
        maxSplitLength: 12,
        variant: GsapRevealVariant.riseMask,
      )));

      expect(long.length, greaterThan(12));
      expect(find.text(long), findsOneWidget);

      await t.pumpAndSettle();
      expect(find.text(long), findsOneWidget);
    });

    testWidgets('單一字元名字不拆字也不炸', (t) async {
      await t.pumpWidget(_host(const GsapTextReveal(text: '美')));
      await t.pumpAndSettle();
      expect(find.text('美'), findsOneWidget);
    });

    testWidgets('收尾會回呼 onEnd 一次', (t) async {
      var ended = 0;
      await t.pumpWidget(_host(GsapTextReveal(
        text: '小美',
        variant: GsapRevealVariant.riseMask,
        onEnd: () => ended++,
      )));

      expect(ended, 0);
      await t.pumpAndSettle();
      expect(ended, 1);
    });
  });

  group('殘影禁令', () {
    testWidgets('全程不出現 Opacity／FadeTransition', (t) async {
      for (final v in GsapRevealVariant.values) {
        await t.pumpWidget(_host(GsapTextReveal(
          key: ValueKey(v),
          text: '小美人',
          variant: v,
        )));

        for (var i = 0; i < 14; i++) {
          expect(
            find.descendant(
              of: find.byType(GsapTextReveal),
              matching: find.byType(Opacity),
            ),
            findsNothing,
            reason: '$v 動到了文字透明度',
          );
          expect(
            find.descendant(
              of: find.byType(GsapTextReveal),
              matching: find.byType(FadeTransition),
            ),
            findsNothing,
            reason: '$v 動到了文字透明度',
          );
          await t.pump(const Duration(milliseconds: 60));
        }
        await t.pumpAndSettle();
      }
    });
  });

  group('直接落地的路徑', () {
    testWidgets('reduce motion：不拆字、直接完整文字，onEnd 只回呼一次', (t) async {
      var ended = 0;
      await t.pumpWidget(_host(
        GsapTextReveal(text: '小美', onEnd: () => ended++),
        disableAnimations: true,
      ));

      expect(find.text('小美'), findsOneWidget);
      expect(find.text('小'), findsNothing);
      expect(ended, 1);
    });

    testWidgets('animate: false（捲動回收後重建）：直接完整文字，onEnd 只回呼一次',
        (t) async {
      var ended = 0;
      await t.pumpWidget(_host(
        GsapTextReveal(
          text: '小美',
          animate: false,
          onEnd: () => ended++,
        ),
      ));

      expect(find.text('小美'), findsOneWidget);
      expect(find.text('小'), findsNothing);
      expect(ended, 1);
    });

    testWidgets('演到一半被改名：直接落在新名字，不會演錯字', (t) async {
      await t.pumpWidget(_host(const GsapTextReveal(
        text: '小美',
        variant: GsapRevealVariant.riseMask,
      )));
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('小'), findsOneWidget);

      await t.pumpWidget(_host(const GsapTextReveal(
        text: '大寶',
        variant: GsapRevealVariant.riseMask,
      )));

      expect(find.text('大寶'), findsOneWidget);
      expect(find.text('小'), findsNothing);
    });
  });

  group('無障礙', () {
    testWidgets('拆字期間語意標籤仍是完整名字', (t) async {
      final handle = t.ensureSemantics();
      await t.pumpWidget(_host(const GsapTextReveal(
        text: '小美',
        variant: GsapRevealVariant.riseMask,
      )));

      expect(
        t.getSemantics(find.byType(GsapTextReveal)),
        isSemantics(label: '小美'),
      );

      await t.pumpAndSettle();
      handle.dispose();
    });
  });
}
