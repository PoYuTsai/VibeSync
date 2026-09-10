import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vibesync/core/theme/app_theme.dart';
import 'package:vibesync/core/theme/app_colors.dart';
import 'package:vibesync/features/night_market/presentation/screens/night_market_screen.dart';
import 'package:vibesync/features/night_market/presentation/widgets/night_market_entry_card.dart';

import 'proof_support.dart';

void main() {
  setUpAll(loadProofFonts);

  testWidgets('real debrief overview, chapter and disclosure visual proof',
      (tester) async {
    await tester.binding.setSurfaceSize(kPhone);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final captureKey = GlobalKey();
    final theme = AppTheme.darkTheme;
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => Scaffold(
          backgroundColor: AppColors.brandInk,
          appBar: AppBar(title: const Text('學習')),
          body: const Padding(
            padding: EdgeInsets.all(16),
            child: NightMarketEntryCard(),
          ),
        ),
      ),
      GoRoute(
        path: '/practice-night-market',
        builder: (_, __) => const NightMarketScreen(),
      ),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(
      routerConfig: router,
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

    await tester.runAsync(() => precacheImage(
          const AssetImage('assets/images/night_market/cover.jpg'),
          tester.element(find.byType(NightMarketEntryCard)),
        ));
    await tester.pumpAndSettle();
    await capture('night_market_review_entry.png');
    await tap('查看復盤');
    await capture('night_market_debrief_overview.png');
    await tap('接住感受，建立信任');
    await capture('night_market_debrief_chapter.png');
    await tap('看完整解析');
    await tester.ensureVisible(find.text('同理心陳述＋背景介紹'));
    await tester.pumpAndSettle();
    await capture('night_market_debrief_expanded.png');
    await tap('同理心陳述＋背景介紹');
    await capture('night_market_debrief_knowledge.png');
    await tap('下一步怎麼做');
    await capture('night_market_debrief_next_step.png');
  });
}
