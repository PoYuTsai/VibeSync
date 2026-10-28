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

  group('解碼大小（典藏材質規格 §8.4）', () {
    testWidgets('帶 cacheWidth：用 ResizeImage 包同一張 asset、寬度照給的', (tester) async {
      final girl = practiceGirlProfiles.first;
      await tester.pumpWidget(
        _host(PracticeGirlPhoto(
          profile: girl,
          width: 40,
          height: 40,
          circle: true,
          cacheWidth: 120,
        )),
      );

      final img = tester.widget<Image>(find.byType(Image));
      final resized = img.image as ResizeImage;
      expect(resized.width, 120);
      expect(
          (resized.imageProvider as AssetImage).assetName, girl.photoAssetPath);
    });

    testWidgets(
        'practiceGirlPhotoCacheWidth：框的長邊×裝置像素比，夾 64–4096；寬或高不是有限正數回 null',
        (tester) async {
      final results = <String, int?>{};
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(devicePixelRatio: 3),
          child: Builder(builder: (context) {
            int? w(double width, double height) =>
                practiceGirlPhotoCacheWidth(context,
                    width: width, height: height);
            results['頭像 40×40'] = w(40, 40);
            results['個人頁 248×310'] = w(248, 310);
            results['動態 4:3 300×225'] = w(300, 225);
            results['很小 10×10'] = w(10, 10);
            results['很大 2000×2000'] = w(2000, 2000);
            results['無限寬'] = w(double.infinity, 320);
            results['零'] = w(0, 0);
            results['寬是零 0×40'] = w(0, 40);
            results['高是無限 40×∞'] = w(40, double.infinity);
            return const SizedBox();
          }),
        ),
      );

      expect(results, {
        '頭像 40×40': 120,
        '個人頁 248×310': 930,
        '動態 4:3 300×225': 900,
        '很小 10×10': 64,
        '很大 2000×2000': 4096,
        '無限寬': null,
        '零': null,
        '寬是零 0×40': null,
        '高是無限 40×∞': null,
      });
    });
  });
}
