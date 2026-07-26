// Scoped visual proof — 換成夥伴內容之後的條目庫（收合／展開兩態）。
// Run: flutter test test/visual_proof/ebook_library_proof_test.dart
// Out: build/visual_proof/ebook_library_collapsed.png
//      build/visual_proof/ebook_library_expanded.png
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/core/theme/app_colors.dart';
import 'package:vibesync/features/learning/data/repositories/ebook_catalog_repository.dart';
import 'package:vibesync/features/learning/domain/models/ebook_block.dart';
import 'package:vibesync/features/learning/domain/models/ebook_progress.dart';
import 'package:vibesync/features/learning/presentation/widgets/ebook_block_renderer.dart';

import 'proof_support.dart';

Future<void> _loadFonts() async {
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

  testWidgets('對話拆解庫：收合與展開', (tester) async {
    const path = 'assets/learning/ebooks/book_2_conversation.json';
    final book = parseBookJson(File(path).readAsStringSync(), assetPath: path);
    final library = book.chapters[4].blocks.whereType<EbookEntryListBlock>().single;

    final rootKey = GlobalKey();
    final contentKey = GlobalKey();
    addTearDown(() => tester.binding.setSurfaceSize(null));

    Future<void> pumpAt(double height) async {
      await tester.binding.setSurfaceSize(Size(390, height));
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
                child: SingleChildScrollView(
                  child: KeyedSubtree(
                    key: contentKey,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: EbookBlockRenderer(
                        block: library,
                        progress: EbookBookProgress.empty,
                        onQuizSubmitted: (_, __, ___) {},
                        onChecklistItemChanged: (_, __, ___) {},
                        onFunnelTargetTap: (_, __) {},
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> shoot(String name) async {
      final boundary =
          tester.renderObject<RenderRepaintBoundary>(find.byKey(rootKey));
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 3.0);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        (File(outPath(name))..createSync(recursive: true))
            .writeAsBytesSync(data!.buffer.asUint8List());
      });
    }

    await pumpAt(4000);
    await pumpAt(tester.getSize(find.byKey(contentKey)).height.ceilToDouble());
    await shoot('ebook_library_collapsed.png');

    // 展開第一條案例。
    await pumpAt(4000);
    await tester.tap(find.text(library.entries.first.title));
    await tester.pumpAndSettle();
    final expanded = tester.getSize(find.byKey(contentKey)).height;
    await tester.binding.setSurfaceSize(Size(390, expanded.ceilToDouble()));
    await tester.pumpAndSettle();
    await shoot('ebook_library_expanded.png');
  });
}
