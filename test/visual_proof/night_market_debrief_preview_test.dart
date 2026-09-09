import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/core/theme/app_theme.dart';
import 'package:vibesync/features/night_market/data/night_market_story.dart';
import 'package:vibesync/features/night_market/presentation/screens/night_market_review_screen.dart';

import 'proof_support.dart';

void main() {
  setUpAll(loadProofFonts);

  testWidgets('real debrief overview, chapter and disclosure visual proof',
      (tester) async {
    await tester.binding.setSurfaceSize(kPhone);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final captureKey = GlobalKey();
    final theme = AppTheme.darkTheme;
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: 'AppTC'),
        primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: 'AppTC'),
        appBarTheme: theme.appBarTheme.copyWith(
          titleTextStyle:
              theme.appBarTheme.titleTextStyle!.copyWith(fontFamily: 'AppTC'),
        ),
      ),
      builder: (context, child) => RepaintBoundary(
        key: captureKey,
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
      ),
      home: NightMarketReviewScreen(
        scenario: buildNightMarketScenario(),
        onRestart: () {},
        onExit: () {},
      ),
    ));
    await tester.pumpAndSettle();

    Future<void> capture(String name) async {
      expect(tester.takeException(), isNull);
      final boundary =
          tester.renderObject<RenderRepaintBoundary>(find.byKey(captureKey));
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        (File(outPath(name))..createSync(recursive: true))
            .writeAsBytesSync(data!.buffer.asUint8List());
        image.dispose();
      });
    }

    Future<void> tap(String label) async {
      await tester.ensureVisible(find.text(label));
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    await capture('night_market_debrief_overview.png');
    await tap('接住感受，建立信任');
    await capture('night_market_debrief_chapter.png');
    await tap('看完整解析');
    await tester.ensureVisible(find.text('繼續看「同理心陳述＋背景介紹」'));
    await tester.pumpAndSettle();
    await capture('night_market_debrief_expanded.png');
    await tap('繼續看「同理心陳述＋背景介紹」');
    await capture('night_market_debrief_knowledge.png');
    await tap('下一步怎麼做');
    await capture('night_market_debrief_next_step.png');
  });
}
