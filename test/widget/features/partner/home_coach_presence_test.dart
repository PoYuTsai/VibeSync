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
      await tester.pump();

      final image = tester.widget<Image>(find.byType(Image));
      final provider = image.image as AssetImage;

      expect(provider.assetName, pose.assetPath);
      expect(image.fit, BoxFit.contain);
      expect(image.alignment, Alignment.bottomRight);
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

  testWidgets('anchors Sydney on the right side of the home canvas', (
    tester,
  ) async {
    await tester.pumpWidget(_subject(HomeCoachPose.greeting));

    final presenceRect = tester.getRect(find.byType(HomeCoachPresence));
    final imageRect = tester.getRect(
      find.byKey(const ValueKey('home-coach-pose-greeting')),
    );

    expect(imageRect.right, closeTo(presenceRect.right, 0.01));
    expect(
      imageRect.left,
      greaterThan(presenceRect.left + presenceRect.width * 0.2),
    );
  });

  testWidgets('switches pose immediately without an animation widget', (
    tester,
  ) async {
    await tester.pumpWidget(_subject(HomeCoachPose.greeting));
    await tester.pumpWidget(_subject(HomeCoachPose.tip));

    expect(
      find.byKey(const ValueKey('home-coach-pose-greeting')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('home-coach-pose-tip')),
      findsOneWidget,
    );
    expect(find.byType(AnimatedSwitcher), findsNothing);
    expect(find.byType(AnimatedOpacity), findsNothing);
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
