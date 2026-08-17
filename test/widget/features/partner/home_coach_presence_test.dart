import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vibesync/features/partner/presentation/widgets/home_coach_presence.dart';

Widget _subject(HomeCoachPose pose) {
  return MaterialApp(
    home: Scaffold(
      body: HomeCoachPresence(
        pose: pose,
        height: 360,
      ),
    ),
  );
}

void main() {
  test('differentPose always selects another gesture', () {
    final random = Random(42);

    for (final pose in HomeCoachPose.values) {
      for (var i = 0; i < 100; i++) {
        expect(pose.differentPose(random), isNot(pose));
      }
    }
  });

  testWidgets('renders the requested Sydney pose asset', (tester) async {
    for (final pose in HomeCoachPose.values) {
      await tester.pumpWidget(_subject(pose));
      // 換姿勢 crossfade 期間新舊圖並存，先讓轉場走完再斷言。
      await tester.pumpAndSettle();

      final image = tester.widget<Image>(find.byType(Image));
      final provider = image.image as AssetImage;

      expect(provider.assetName, pose.assetPath);
      expect(image.fit, BoxFit.fitHeight);
      expect(image.alignment, Alignment.bottomCenter);
      expect(
        find.byKey(ValueKey('home-coach-pose-${pose.name}')),
        findsOneWidget,
      );
    }
  });

  testWidgets('decodes the bundled coach image', (tester) async {
    await tester.pumpWidget(_subject(HomeCoachPose.greeting));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();

    final image = find.byKey(
      const ValueKey('home-coach-pose-greeting'),
    );
    expect(tester.renderObject<RenderImage>(image).image, isNotNull);
  });

  // 2026-08-09 拍板：以 greeting（雙手張開）為基準做人物正規化——任何姿勢
  // 的「人物顯示高度」一致、人物中心水平置中、底邊錨定，且不放大超過畫布
  //（不切身）。舊的「畫布同尺寸＋靠右錨定」規格已推翻。
  testWidgets('keeps every Sydney pose figure at the same visual height', (
    tester,
  ) async {
    double? referenceFigureHeight;

    for (final pose in HomeCoachPose.values) {
      await tester.pumpWidget(_subject(pose));
      await tester.pump();

      final image = find.byKey(ValueKey('home-coach-pose-${pose.name}'));
      final size = tester.getSize(image);
      final figureHeight = size.height * pose.figureHeightFraction;
      referenceFigureHeight ??= figureHeight;

      expect(figureHeight, closeTo(referenceFigureHeight, 0.5));

      // 不切身：渲染高不超過 presence 高度。
      final presenceRect = tester.getRect(find.byType(HomeCoachPresence));
      expect(size.height, lessThanOrEqualTo(presenceRect.height + 0.01));
      // 底邊錨定。
      final imageRect = tester.getRect(image);
      expect(imageRect.bottom, closeTo(presenceRect.bottom, 0.01));
    }
  });

  testWidgets('centers the figure (not the canvas) on the home midline', (
    tester,
  ) async {
    for (final pose in HomeCoachPose.values) {
      await tester.pumpWidget(_subject(pose));
      await tester.pump();

      final presenceRect = tester.getRect(find.byType(HomeCoachPresence));
      final imageRect = tester.getRect(
        find.byKey(ValueKey('home-coach-pose-${pose.name}')),
      );
      final figureCenterX =
          imageRect.left + imageRect.width * pose.figureCenterX;

      expect(figureCenterX, closeTo(presenceRect.center.dx, 0.5));
    }
  });

  // 2026-08-17 動效計畫 004：換姿勢改 200ms crossfade（AnimatedSwitcher），
  // 推翻舊的「瞬切、無動畫元件」拍板。
  testWidgets('crossfades between poses and settles on the new one', (
    tester,
  ) async {
    await tester.pumpWidget(_subject(HomeCoachPose.greeting));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_subject(HomeCoachPose.tip));
    await tester.pump(const Duration(milliseconds: 100));

    // 轉場中：新舊姿勢並存（crossfade 的證據）。
    expect(
      find.byKey(const ValueKey('home-coach-pose-greeting')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('home-coach-pose-tip')),
      findsOneWidget,
    );

    await tester.pumpAndSettle();

    // 轉場結束：只剩新姿勢。
    expect(
      find.byKey(const ValueKey('home-coach-pose-greeting')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('home-coach-pose-tip')),
      findsOneWidget,
    );
  });

  testWidgets('exposes Sydney as an accessible image', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_subject(HomeCoachPose.greeting));

    expect(
      find.bySemanticsLabel('VibeSync Coach Sydney，欣欣'),
      findsOneWidget,
    );
    handle.dispose();
  });
}
