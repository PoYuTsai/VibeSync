import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_girl_catalog.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_girl_photo.dart';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('用 photoAssetPath 建 AssetImage，且 wired 了 fallback errorBuilder',
      (tester) async {
    final girl = practiceGirlProfiles.first;
    await tester.pumpWidget(
      _host(PracticeGirlPhoto(profile: girl, width: 80, height: 100)),
    );

    final img = tester.widget<Image>(find.byType(Image));
    expect((img.image as AssetImage).assetName, girl.photoAssetPath);
    expect(img.errorBuilder, isNotNull, reason: '必須有 fallback 不讓缺圖 crash');
  });

  testWidgets('errorBuilder 渲染出名字首字母 fallback、不丟例外', (tester) async {
    // 直接驗證 fallback builder（asset 載入時序在 test 不可靠，故不依賴它觸發）。
    final girl = practiceGirlProfiles[2]; // Zoe
    await tester.pumpWidget(
      _host(PracticeGirlPhoto(profile: girl, width: 40, height: 40, circle: true)),
    );

    final img = tester.widget<Image>(find.byType(Image));
    final ctx = tester.element(find.byType(Image));
    final fallback = img.errorBuilder!(ctx, FlutterError('load failed'), null);

    await tester.pumpWidget(_host(fallback));
    expect(tester.takeException(), isNull);
    expect(find.text(girl.displayName.substring(0, 1)), findsOneWidget);
  });

  testWidgets('可由 caller 指定穩定 key', (tester) async {
    final girl = practiceGirlProfiles.first;
    await tester.pumpWidget(
      _host(PracticeGirlPhoto(
        key: const ValueKey('practice-profile-avatar'),
        profile: girl,
        width: 38,
        height: 38,
        circle: true,
      )),
    );
    expect(
      find.byKey(const ValueKey('practice-profile-avatar')),
      findsOneWidget,
    );
  });
}
