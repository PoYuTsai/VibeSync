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

  testWidgets('進場延遲後左右晃一趟，播完停回原位', (tester) async {
    await tester.pumpWidget(wrap());
    // 延遲段（前 650ms）不動。
    await tester.pump(const Duration(milliseconds: 300));
    expect(currentOffsetX(tester), 0);

    // 動作段中要離開原位。
    await tester.pump(const Duration(milliseconds: 600));
    expect(currentOffsetX(tester), isNot(0));

    // 播完停回原位。
    await tester.pumpAndSettle();
    expect(currentOffsetX(tester), 0);
  });

  testWidgets('reduced motion 全程靜止', (tester) async {
    await tester.pumpWidget(wrap(disableAnimations: true));
    await tester.pump(const Duration(milliseconds: 1200));
    expect(currentOffsetX(tester), 0);
    await tester.pumpAndSettle();
    expect(currentOffsetX(tester), 0);
  });
}
