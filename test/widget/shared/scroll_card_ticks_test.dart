import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/core/services/app_haptics.dart';
import 'package:vibesync/shared/widgets/scroll_card_ticks.dart';

// ScrollCardTicks：卡片通過焦點線換人那刻打一下輕觸覺。鎖三件事：
// 第一次落點不震、跨卡才震（同卡內捲動不震）、橫向軸也能用。
void main() {
  final vibrates = <String>[];

  setUp(() {
    vibrates.clear();
    AppHaptics.enabled = true;
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        vibrates.add(call.arguments as String);
      }
      return null;
    });
  });

  Widget vertical() => MaterialApp(
        home: Scaffold(
          body: ScrollCardTicks(
            child: ListView(
              children: [
                for (var i = 0; i < 8; i++)
                  CardTickTarget(
                    index: i,
                    child: SizedBox(height: 200, child: Text('card-$i')),
                  ),
              ],
            ),
          ),
        ),
      );

  testWidgets('縱向：跨卡打一下、同卡內不重複', (tester) async {
    await tester.pumpWidget(vertical());

    // 第一段小捲動：焦點落到第 0 張（第一次落點，不震）。
    await tester.drag(find.byType(ListView), const Offset(0, -20));
    await tester.pump();
    expect(vibrates, isEmpty);

    // 同一張卡內再捲一點：不震。
    await tester.drag(find.byType(ListView), const Offset(0, -20));
    await tester.pump();
    expect(vibrates, isEmpty);

    // 大捲動跨到下一張：震一下。
    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pump();
    expect(vibrates.length, 1);
  });

  testWidgets('橫向軸：跨卡打一下', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 200,
            child: ScrollCardTicks(
              axis: Axis.horizontal,
              focusFraction: 0.3,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (var i = 0; i < 6; i++)
                    CardTickTarget(
                      index: i,
                      child: SizedBox(width: 250, child: Text('card-$i')),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.drag(find.byType(ListView), const Offset(-20, 0));
    await tester.pump();
    expect(vibrates, isEmpty); // 第一次落點。

    await tester.drag(find.byType(ListView), const Offset(-260, 0));
    await tester.pump();
    expect(vibrates.length, 1);
  });
}
