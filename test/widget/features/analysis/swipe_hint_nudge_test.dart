import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/presentation/widgets/swipe_hint_nudge.dart';

void main() {
  double currentOffsetX(WidgetTester tester) {
    final transform = tester.widget<Transform>(
      find.descendant(
        of: find.byType(SwipeHintNudge),
        matching: find.byType(Transform),
      ),
    );
    return transform.transform.getTranslation().x;
  }

  Widget wrap({bool disableAnimations = false}) {
    return MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: const Directionality(
        textDirection: TextDirection.ltr,
        child: SwipeHintNudge(child: Text('← 左右滑動')),
      ),
    );
  }

  // 長駐 repeat 動畫：絕不能 pumpAndSettle（永不 settle），只用定時 pump。
  testWidgets('長駐左右晃動：第一輪會動，下一輪還在動', (tester) async {
    await tester.pumpWidget(wrap());
    // 週期 2600ms：420ms 落在第一段右移中。
    await tester.pump(const Duration(milliseconds: 420));
    expect(currentOffsetX(tester), greaterThan(0));

    // 1770ms 落在左移段。
    await tester.pump(const Duration(milliseconds: 1350));
    expect(currentOffsetX(tester), lessThan(0));

    // 跨一整輪後（+2600ms）仍在同相位擺動＝repeat 沒停。
    await tester.pump(const Duration(milliseconds: 2600));
    expect(currentOffsetX(tester), lessThan(0));

    // 收尾停回原位靠 dispose，不留 ticker。
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('reduced motion 全程靜止', (tester) async {
    await tester.pumpWidget(wrap(disableAnimations: true));
    await tester.pump(const Duration(milliseconds: 1200));
    expect(currentOffsetX(tester), 0);
    await tester.pump(const Duration(milliseconds: 2600));
    expect(currentOffsetX(tester), 0);
  });
}
