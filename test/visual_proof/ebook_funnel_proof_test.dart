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

/// 這台 WSL 上 `loadProofFonts` 命中的是 NotoSansTC-VF（可變字型），headless
/// 渲染出來是豆腐字。改先註冊微軟正黑體（靜態 ttc），再讓 loadProofFonts 補
/// MaterialIcons。
Future<void> _loadFonts() async {
  const tcCandidates = [
    '/mnt/c/Windows/Fonts/msjh.ttc',
    '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
  ];
  for (final path in tcCandidates) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final bytes = file.readAsBytesSync();
    await (FontLoader('AppTC')
          ..addFont(Future.value(ByteData.view(bytes.buffer))))
        .load();
    break;
  }
  // 只補 MaterialIcons；不呼叫 loadProofFonts，避免 AppTC 家族被重複註冊
  // （NotoSansTC-VF 疊上來會在無頭渲染留下黃色底線 artifact）。
  final mi = File(
    '/home/eric1/flutter/bin/cache/artifacts/material_fonts/'
    'MaterialIcons-Regular.otf',
  ).readAsBytesSync();
  await (FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.view(mi.buffer))))
      .load();
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
