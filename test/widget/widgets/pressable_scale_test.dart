import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/core/services/app_haptics.dart';
import 'package:vibesync/shared/widgets/pressable_scale.dart';

void main() {
  final vibrates = <String>[];

  setUp(() {
    vibrates.clear();
    AppHaptics.enabled = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        vibrates.add(call.arguments as String);
      }
      return null;
    });
  });

  Widget harness({bool hapticOnDown = false, bool enabled = true}) {
    return MaterialApp(
      home: Center(
        child: PressableScale(
          enabled: enabled,
          hapticOnDown: hapticOnDown,
          child: const ColoredBox(
            color: Colors.red,
            child: SizedBox(width: 100, height: 100),
          ),
        ),
      ),
    );
  }

  testWidgets('預設模式：放開時輕點一下', (tester) async {
    await tester.pumpWidget(harness());
    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(PressableScale)));
    await tester.pump();
    expect(vibrates, isEmpty, reason: '按下瞬間不震');
    await gesture.up();
    expect(vibrates, ['HapticFeedbackType.selectionClick']);
    await tester.pumpAndSettle();
  });

  testWidgets('預設模式：被捲動取消就不震', (tester) async {
    await tester.pumpWidget(harness());
    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(PressableScale)));
    await tester.pump();
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(vibrates, isEmpty);
  });

  testWidgets('hapticOnDown：按下瞬間給實心感', (tester) async {
    await tester.pumpWidget(harness(hapticOnDown: true));
    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(PressableScale)));
    await tester.pump();
    expect(vibrates, ['HapticFeedbackType.lightImpact']);
    await gesture.up();
    expect(vibrates, ['HapticFeedbackType.lightImpact'], reason: '放開不再震');
    await tester.pumpAndSettle();
  });

  testWidgets('disabled 時完全靜音', (tester) async {
    await tester.pumpWidget(harness(enabled: false));
    await tester.tap(find.byType(PressableScale));
    await tester.pumpAndSettle();
    expect(vibrates, isEmpty);
  });
}
