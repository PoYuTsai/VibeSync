import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/splash/presentation/screens/splash_screen.dart';

void main() {
  testWidgets('splash 在 2 秒內完成 onComplete', (tester) async {
    var completed = false;
    await tester.pumpWidget(MaterialApp(
      home: SplashScreen(onComplete: () => completed = true),
    ));
    // 光球是 repeat 動畫，只能 pump 步進，絕不 pumpAndSettle。
    await tester.pump(const Duration(milliseconds: 2100));
    expect(completed, isTrue);
  });
}
