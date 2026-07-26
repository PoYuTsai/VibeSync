// Scoped visual proof — 電子書第一章的漏斗自我診斷（正式 widget＋正式內容）。
// Run: flutter test test/visual_proof/ebook_funnel_proof_test.dart
// Out: build/visual_proof/ebook_funnel_idle.png، ebook_funnel_selected.png
//
// 這裡刻意用 lib/ 的 EbookStageFunnelView 與 assets 裡真正的 book_1 JSON，
// 不是另外畫一個示意圖——否則截圖證明不了 App 裡長什麼樣。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/core/theme/app_colors.dart';
import 'package:vibesync/features/learning/data/repositories/ebook_catalog_repository.dart';
import 'package:vibesync/features/learning/domain/models/ebook_block.dart';
import 'package:vibesync/features/learning/presentation/widgets/ebook_stage_funnel.dart';

import 'proof_support.dart';

Future<void> _capture(
  WidgetTester tester,
  GlobalKey rootKey,
  String path,
) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(rootKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    (File(path)..createSync(recursive: true))
        .writeAsBytesSync(data!.buffer.asUint8List());
  });
}

Future<void> _loadFonts() async {
  // 本機（WSL）上共用 harness 命中的是可變字型，無頭渲染會變豆腐；有單檔
  // ttf 就先註冊同名家族覆蓋。先註冊的先贏。
  //
  // 但絕不能寫死本機路徑：這些 proof 測試會跟著 release gate 的全套測試在 CI
  // 上跑，路徑不存在就會讓整條 build 掛掉（2026-07-27 build 353 就是這樣死的）。
  for (final path in const [
    '/mnt/c/Windows/Fonts/msjh.ttc',
    '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
  ]) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final bytes = file.readAsBytesSync();
    await (FontLoader('AppTC')
          ..addFont(Future.value(ByteData.view(bytes.buffer))))
        .load();
    break;
  }
  // MaterialIcons 與 TC fallback 一律交給共用 harness 做 SDK／fontconfig 探測。
  await loadProofFonts();
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('漏斗：未選 / 已選兩態', (tester) async {
    // 直接同步解析真檔案：AssetBundle.loadString 對 >50KB 內容會走 isolate，
    // 在 fake async 下不會完成。
    const path = 'assets/learning/ebooks/book_1_bottleneck.json';
    final book = parseBookJson(
      File(path).readAsStringSync(),
      assetPath: path,
    );
    final funnel = book.chapters.first.blocks
        .whereType<EbookStageFunnelBlock>()
        .single;

    final rootKey = GlobalKey();
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'AppTC', useMaterial3: true),
        home: DefaultTextStyle.merge(
          style: const TextStyle(fontFamily: 'AppTC'),
          child: RepaintBoundary(
            key: rootKey,
            child: Container(
              color: AppColors.brandInk,
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                child: EbookStageFunnelView(
                  block: funnel,
                  onOpenTarget: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _capture(tester, rootKey, outPath('ebook_funnel_idle.png'));

    // 點第三層（階段 2 · 續航），與 Bruce 截圖裡選中的那一層相同。
    await tester.tap(find.text(funnel.stages[2].symptom));
    await tester.pumpAndSettle();
    await _capture(tester, rootKey, outPath('ebook_funnel_selected.png'));
  });
}
