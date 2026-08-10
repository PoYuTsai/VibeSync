// B9 對照：paywall 卡片堆疊改分層（S9）整頁 capture。
// 出圖 build/visual_proof/prod_paywall.png（430x1700 全高，看區塊分層節奏）。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';
import 'package:vibesync/features/subscription/presentation/screens/paywall_screen.dart';

import 'proof_support.dart';

void main() {
  setUpAll(loadProofFonts);

  testWidgets('capture paywall full page', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final rootKey = GlobalKey();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          subscriptionScreenRefreshProvider.overrideWithValue(() async {}),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'AppTC', useMaterial3: true),
          home: DefaultTextStyle.merge(
            style: const TextStyle(fontFamily: 'AppTC'),
            child: RepaintBoundary(
              key: rootKey,
              child: const PaywallScreen(),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 800));

    final boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(rootKey));
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2.0);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      (File(outPath('prod_paywall.png'))..createSync(recursive: true))
          .writeAsBytesSync(data!.buffer.asUint8List());
    });
  });
}
