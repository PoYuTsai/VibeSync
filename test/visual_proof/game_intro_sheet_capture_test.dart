// Game 教學卡兩頁版 proof：第一頁觀念、第二頁機制（七步併五階段圖＋計分）。
// 產出 build/visual_proof/game_intro_page1.png / game_intro_page2.png。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_game_intro_sheet.dart';

import 'proof_support.dart';

void main() {
  setUpAll(loadProofFonts);

  testWidgets('capture game intro sheet pages', (tester) async {
    await tester.binding.setSurfaceSize(kPhone);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final rootKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: rootKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'AppTC', useMaterial3: true),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  key: const ValueKey('open'),
                  onPressed: () => showPracticeGameIntroSheet(
                    context,
                    showUpgradeHook: true,
                    locked: true,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    Future<void> capture(String name) async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(rootKey),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 3.0);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        (File(outPath(name))..createSync(recursive: true))
            .writeAsBytesSync(data!.buffer.asUint8List());
      });
    }

    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();
    await capture('game_intro_page1.png');

    await tester.tap(find.byKey(const ValueKey('practice-game-intro-next')));
    await tester.pumpAndSettle();
    await capture('game_intro_page2.png');
  });
}
