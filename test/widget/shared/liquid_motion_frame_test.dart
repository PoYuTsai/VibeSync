import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/shared/widgets/brand/liquid_motion_frame.dart';

Widget _host({
  required Widget child,
  bool disableAnimations = false,
  bool tickerEnabled = true,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: TickerMode(
        enabled: tickerEnabled,
        child: Scaffold(body: Center(child: child)),
      ),
    ),
  );
}

void main() {
  testWidgets('reduced motion 使用靜態流光並可收斂', (tester) async {
    await tester.pumpWidget(
      _host(
        disableAnimations: true,
        child: const LiquidMotionFrame(
          child: SizedBox(width: 180, height: 80, child: Text('查看升級方案')),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(LiquidMotionFrame), findsOneWidget);
    expect(find.text('查看升級方案'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TickerMode 關閉時不留下無限 ticker', (tester) async {
    await tester.pumpWidget(
      _host(
        tickerEnabled: false,
        child: const LiquidMotionFrame(
          shape: BoxShape.circle,
          child: SizedBox.square(dimension: 54),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(LiquidMotionFrame), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('啟用動效後持續重繪但保留 child', (tester) async {
    await tester.pumpWidget(
      _host(
        child: const LiquidMotionFrame(
          child: SizedBox(width: 180, height: 80, child: Text('動態外框')),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 900));

    expect(find.text('動態外框'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
