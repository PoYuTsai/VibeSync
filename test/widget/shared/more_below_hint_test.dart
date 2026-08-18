// 滑動提示 pill 行為測試（2026-08-18 開場白/新話題呈現精修）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vibesync/shared/widgets/more_below_hint.dart';

void main() {
  Widget host({
    required ScrollController controller,
    required GlobalKey targetKey,
    Object? resetToken,
    double spacerHeight = 2000,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            SingleChildScrollView(
              controller: controller,
              child: Column(
                children: [
                  SizedBox(height: spacerHeight),
                  SizedBox(
                    key: targetKey,
                    height: 100,
                    child: const Text('公式區'),
                  ),
                ],
              ),
            ),
            Positioned(
              right: 16,
              bottom: 16,
              child: MoreBelowHint(
                controller: controller,
                targetKey: targetKey,
                label: '往下還有公式開場',
                resetToken: resetToken,
              ),
            ),
          ],
        ),
      ),
    );
  }

  testWidgets('目標在視口下方時顯示；捲到目標後收起', (t) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final targetKey = GlobalKey();
    await t.pumpWidget(host(controller: controller, targetKey: targetKey));
    await t.pump();

    expect(find.byKey(const ValueKey('more-below-hint')), findsOneWidget);
    expect(find.text('往下還有公式開場'), findsOneWidget);

    controller.jumpTo(controller.position.maxScrollExtent);
    await t.pump();
    expect(find.byKey(const ValueKey('more-below-hint')), findsNothing);

    // 看過就不再出現（同一輪結果內捲回頂部也不重現）。
    controller.jumpTo(0);
    await t.pump();
    expect(find.byKey(const ValueKey('more-below-hint')), findsNothing);
  });

  testWidgets('目標本來就在視口內時不顯示', (t) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final targetKey = GlobalKey();
    await t.pumpWidget(host(
      controller: controller,
      targetKey: targetKey,
      spacerHeight: 100,
    ));
    await t.pump();
    expect(find.byKey(const ValueKey('more-below-hint')), findsNothing);
  });

  testWidgets('點 pill 直接捲到目標並收起', (t) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final targetKey = GlobalKey();
    await t.pumpWidget(host(controller: controller, targetKey: targetKey));
    await t.pump();

    await t.tap(find.byKey(const ValueKey('more-below-hint')));
    await t.pumpAndSettle();
    expect(controller.offset, greaterThan(0));
    expect(find.byKey(const ValueKey('more-below-hint')), findsNothing);
  });

  testWidgets('resetToken 換新（新一輪結果）後重新提示', (t) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final targetKey = GlobalKey();
    await t.pumpWidget(host(
      controller: controller,
      targetKey: targetKey,
      resetToken: 'run-1',
    ));
    await t.pump();
    controller.jumpTo(controller.position.maxScrollExtent);
    await t.pump();
    expect(find.byKey(const ValueKey('more-below-hint')), findsNothing);

    controller.jumpTo(0);
    await t.pumpWidget(host(
      controller: controller,
      targetKey: targetKey,
      resetToken: 'run-2',
    ));
    await t.pump();
    await t.pump();
    expect(find.byKey(const ValueKey('more-below-hint')), findsOneWidget);
  });
}
