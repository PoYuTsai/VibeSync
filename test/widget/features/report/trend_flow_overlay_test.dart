import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/report/presentation/widgets/trend_flow_overlay.dart';

Widget _subject({bool disableAnimations = false}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(
        body: SizedBox(
          width: 240,
          height: 120,
          child: TrendFlowOverlay(
            points: const [
              Offset(0, 0.4),
              Offset(0.5, 0.7),
              Offset(1, 0.55),
            ],
            padding: const EdgeInsets.all(12),
            color: Colors.orange,
            glowColor: Colors.deepOrange,
            activeDuration: const Duration(milliseconds: 200),
            pauseDuration: const Duration(seconds: 5),
            painterKey: const ValueKey('flow-painter'),
            child: const ColoredBox(color: Colors.black),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('資料流完成後進入長停頓，不持續逐幀重繪', (tester) async {
    await tester.pumpWidget(_subject());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byKey(const ValueKey('flow-painter')), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('reduced motion 開啟時完全靜止', (tester) async {
    await tester.pumpWidget(_subject(disableAnimations: true));
    await tester.pump();

    expect(find.byKey(const ValueKey('flow-painter')), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
