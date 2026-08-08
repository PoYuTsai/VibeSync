import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/shared/widgets/brand/one_shot_comet_border.dart';

void main() {
  Widget harness({required int? trigger, bool disableAnimations = false}) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Center(
          child: OneShotCometBorder(
            trigger: trigger,
            child: const SizedBox(width: 200, height: 120),
          ),
        ),
      ),
    );
  }

  Finder cometPaint() => find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is OneShotCometBorderPainter,
      );

  testWidgets('首幀不播；trigger 換新值播一圈後自然收乾', (tester) async {
    // 首幀帶著 trigger 值建立：不播（等同 paywall 預選卡）。
    await tester.pumpWidget(harness(trigger: 5));
    await tester.pump(const Duration(milliseconds: 300));
    expect(cometPaint(), findsNothing);

    // trigger 換新值：開始播。
    await tester.pumpWidget(harness(trigger: 6));
    await tester.pump(const Duration(milliseconds: 200));
    expect(cometPaint(), findsOneWidget);

    // 一次性動畫：pumpAndSettle 能收斂（沒有無限 ticker），播完零殘留。
    await tester.pumpAndSettle();
    expect(cometPaint(), findsNothing);
  });

  testWidgets('disableAnimations 時完全不播、不排任何幀', (tester) async {
    await tester.pumpWidget(harness(trigger: 1, disableAnimations: true));
    await tester.pumpWidget(harness(trigger: 2, disableAnimations: true));
    await tester.pump();

    expect(cometPaint(), findsNothing);
    // 沒有任何進行中的動畫 ticker。
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('播到一半 trigger 變 null（取消選取）立刻收掉殘光', (tester) async {
    await tester.pumpWidget(harness(trigger: 1));
    await tester.pumpWidget(harness(trigger: 2));
    await tester.pump(const Duration(milliseconds: 200));
    expect(cometPaint(), findsOneWidget);

    await tester.pumpWidget(harness(trigger: null));
    await tester.pump();
    expect(cometPaint(), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
  });
}
