import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/core/theme/app_colors.dart';
import 'package:vibesync/features/analysis/presentation/widgets/analysis_action_widgets.dart';

Widget _harness({
  required ScrollController scrollController,
  bool reduceMotion = false,
  double keyboardInset = 0,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        disableAnimations: reduceMotion,
        viewInsets: EdgeInsets.only(bottom: keyboardInset),
      ),
      child: Scaffold(
        appBar: AppBar(title: const Text('對話')),
        floatingActionButtonLocation: const AnalysisSideCenterFabLocation(),
        floatingActionButton: FloatingAnalysisActionButton(onPressed: () {}),
        body: ListView.builder(
          controller: scrollController,
          itemCount: 30,
          itemBuilder: (_, index) => SizedBox(
            height: 72,
            child: Text('訊息 $index'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('analysis orb stays at the right-side viewport center on scroll',
      (tester) async {
    const surfaceSize = Size(390, 844);
    const appBarHeight = kToolbarHeight;
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    await tester.binding.setSurfaceSize(surfaceSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_harness(scrollController: scrollController));
    await tester.pumpAndSettle();

    final orbFinder = find.byKey(FloatingAnalysisActionButton.orbKey);
    final before = tester.getRect(orbFinder);
    expect(before.right, closeTo(surfaceSize.width - 12, 0.01));
    expect(
      before.center.dy,
      closeTo((appBarHeight + surfaceSize.height) / 2, 0.01),
    );

    scrollController.jumpTo(900);
    await tester.pump();

    final after = tester.getRect(orbFinder);
    expect(after, before);
  });

  testWidgets('analysis orb uses a dark core and settles under reduced motion',
      (tester) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      _harness(
        scrollController: scrollController,
        reduceMotion: true,
      ),
    );
    await tester.pump();

    final button = tester.widget<FilledButton>(
      find.byKey(FloatingAnalysisActionButton.buttonKey),
    );
    expect(
      button.style?.backgroundColor?.resolve(<WidgetState>{}),
      AppColors.brandInk,
    );
    expect(
      button.style?.shape?.resolve(<WidgetState>{}),
      isA<CircleBorder>(),
    );
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('analysis orb recenters inside the keyboard-safe viewport',
      (tester) async {
    const surfaceSize = Size(390, 844);
    const keyboardInset = 300.0;
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    await tester.binding.setSurfaceSize(surfaceSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _harness(
        scrollController: scrollController,
        reduceMotion: true,
        keyboardInset: keyboardInset,
      ),
    );
    await tester.pump();

    final orb = tester.getRect(
      find.byKey(FloatingAnalysisActionButton.orbKey),
    );
    expect(
      orb.center.dy,
      closeTo((kToolbarHeight + surfaceSize.height - keyboardInset) / 2, 0.01),
    );
  });
}
