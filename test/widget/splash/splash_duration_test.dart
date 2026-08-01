import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/splash/presentation/screens/splash_screen.dart';

void main() {
  testWidgets('splash 在約 2 秒完成 onComplete（含下界防過度縮短）', (tester) async {
    var completed = false;
    await tester.pumpWidget(MaterialApp(
      home: SplashScreen(onComplete: () => completed = true),
    ));
    // 光球是 repeat 動畫，只能 pump 步進，絕不 pumpAndSettle。
    // 下界：1.9 秒還不能完成——設計是「縮到約 2 秒」，不是越短越好。
    await tester.pump(const Duration(milliseconds: 1900));
    expect(completed, isFalse);
    await tester.pump(const Duration(milliseconds: 200));
    expect(completed, isTrue);
  });
}
