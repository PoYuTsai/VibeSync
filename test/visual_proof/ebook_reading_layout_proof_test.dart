// Scoped visual proof — 章節內文排版 framed vs spine（正式 widget＋正式內容）。
// Run: flutter test test/visual_proof/ebook_reading_layout_proof_test.dart
// Out: build/visual_proof/ebook_layout_framed.png、ebook_layout_spine.png
//
// 2026-07-31 夥伴回饋《成為獎賞》不易閱讀。這裡用 lib/ 的 EbookBlockRenderer
// 與 assets 裡真正的 book_5 JSON 渲染同一段內容的兩種排版，讓 Eric 在還沒出
// iOS build 之前就看得到差別。示意圖證明不了 App 裡長什麼樣，所以不畫示意圖。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vibesync/core/theme/app_colors.dart';
import 'package:vibesync/features/learning/data/providers/ebook_providers.dart';
import 'package:vibesync/features/learning/data/repositories/ebook_progress_repository.dart';
import 'package:vibesync/features/learning/presentation/screens/ebook_reader_screen.dart';
import 'package:vibesync/features/learning/presentation/widgets/ebook_access_gate.dart';
import 'package:vibesync/features/learning/data/repositories/ebook_catalog_repository.dart';
import 'package:vibesync/features/learning/domain/models/ebook.dart';
import 'package:vibesync/features/learning/domain/models/ebook_block.dart';
import 'package:vibesync/features/learning/domain/models/ebook_progress.dart';
import 'package:vibesync/features/learning/presentation/widgets/ebook_block_renderer.dart';

import '../helpers/ebook_widget_harness.dart';
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
  // 與其他 proof 一致：本機命中可變字型會變豆腐，有單檔就先覆蓋同名家族。
  // 絕不寫死本機路徑——這些測試會跟著 release gate 在 CI 上跑。
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
  await loadProofFonts();
}

void main() {
  setUpAll(_loadFonts);

  /// 同步解析真檔案：AssetBundle.loadString 對 >50KB 內容會走 isolate，
  /// 在 fake async 下不會完成。
  Ebook readBook(String file) {
    final path = 'assets/learning/ebooks/$file';
    return parseBookJson(File(path).readAsStringSync(), assetPath: path);
  }

  Future<void> shootChapter(
    WidgetTester tester, {
    required EbookChapter chapter,
    required List<EbookBlock> blocks,
    required EbookReadingLayout layout,
    required String name,
    double height = 1700,
  }) async {
    {
      final rootKey = GlobalKey();
      await tester.binding.setSurfaceSize(Size(390, height));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'AppTC', useMaterial3: true),
          home: DefaultTextStyle.merge(
            style: const TextStyle(fontFamily: 'AppTC'),
            // 沒有 Material 祖先時 Text 會套上黃底線的 fallback 樣式，截圖
            // 就不是 App 裡真正的樣子。
            child: Material(
              color: AppColors.brandInk,
              child: RepaintBoundary(
                key: rootKey,
                child: Container(
                  color: AppColors.brandInk,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          chapter.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 20),
                        for (final block in blocks)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 18),
                            child: EbookBlockRenderer(
                              block: block,
                              layout: layout,
                              progress: EbookBookProgress.empty,
                              onQuizSubmitted: (_, __, ___) {},
                              onChecklistItemChanged: (_, __, ___) {},
                              onFunnelTargetTap: (_, __) {},
                              onCrossRefTap: (_) {},
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _capture(tester, rootKey, outPath(name));
    }
  }

  testWidgets('夥伴截圖那一章：framed vs spine', (tester) async {
    // 取到 checklist 之前為止：一屏塞得下，又涵蓋 paragraph／callout／dialogue。
    final chapter = readBook('book_5_core.json').chapters.first;
    final blocks = chapter.blocks
        .takeWhile((block) => block is! EbookChecklistBlock)
        .toList(growable: false);

    for (final (layout, name) in const [
      (EbookReadingLayout.framed, 'ebook_layout_framed.png'),
      (EbookReadingLayout.spine, 'ebook_layout_spine.png'),
    ]) {
      await shootChapter(
        tester,
        chapter: chapter,
        blocks: blocks,
        layout: layout,
        name: name,
      );
    }
  });

  /// 閱讀器頂部：章節列在兩個單元都要長一樣（Eric 2026-07-31）。
  ///
  /// 只截 header 那一段——下面的內文由前兩支負責，這裡要看的是導覽一致性。
  Future<void> shootReaderHeader(
    WidgetTester tester, {
    required String bookId,
    required String chapterId,
    required Ebook book,
    required String name,
  }) async {
    // Essential 專屬單元用 premium(Starter) 會被 lockedBuilder 導去書籍目錄，
    // 截圖就變成 Page Not Found——而測試照樣綠。全開最高權益才拍得到內文。
    final container = ProviderContainer(
      overrides: [
        ebookSubscriptionAccessProvider
            .overrideWith((ref) => const EbookSubscriptionAccess.essential()),
        ebookProgressOwnerProvider
            .overrideWith((ref) => Stream<String?>.value('proof-owner')),
        ebookProgressRepositoryProvider
            .overrideWithValue(EbookProgressRepository(box: InMemoryHiveBox())),
        ebookCatalogProvider
            .overrideWith((ref) async => EbookCatalog(books: [book])),
      ],
    );
    addTearDown(container.dispose);

    final router = GoRouter(
      initialLocation: '/learning/books/$bookId/chapters/$chapterId',
      routes: [
        GoRoute(
          path: '/learning/books/:bookId/chapters/:chapterId',
          builder: (context, state) => EbookReaderScreen(
            bookId: state.pathParameters['bookId']!,
            chapterId: state.pathParameters['chapterId'],
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    final rootKey = GlobalKey();
    await tester.binding.setSurfaceSize(const Size(390, 300));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'AppTC', useMaterial3: true),
          routerConfig: router,
          builder: (context, child) => DefaultTextStyle.merge(
            style: const TextStyle(fontFamily: 'AppTC'),
            child: RepaintBoundary(key: rootKey, child: child!),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 拍到錯誤頁卻通過的 proof 是假證據：先確認閱讀器真的在畫面上，
    // 而且章節列長出來了。
    expect(find.byType(EbookReaderScreen), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('ebook-chapter-chip-0')),
      findsOneWidget,
      reason: '$name 沒拍到章節列',
    );

    await _capture(tester, rootKey, outPath(name));
  }

  testWidgets('閱讀器頂部章節列：兩個單元長一樣', (tester) async {
    final guide = readBook('book_1_bottleneck.json');
    final prize = readBook('book_5_core.json');

    await shootReaderHeader(
      tester,
      bookId: guide.id,
      chapterId: guide.chapters.first.id,
      book: guide,
      name: 'ebook_header_guide.png',
    );
    await shootReaderHeader(
      tester,
      bookId: prize.id,
      chapterId: prize.chapters.first.id,
      book: prize,
      name: 'ebook_header_prize.png',
    );
  });

  testWidgets('callout 最密的一章：framed vs spine', (tester) async {
    // 3.3「天平與砝碼」：三個 callout＋交叉指涉＋條目庫，是密度最高的那型。
    // 整章都拍，框線一個都不少。
    final chapter = readBook('book_6_frames.json').chapters[2];
    final blocks = chapter.blocks;

    for (final (layout, name) in const [
      (EbookReadingLayout.framed, 'ebook_layout_dense_framed.png'),
      (EbookReadingLayout.spine, 'ebook_layout_dense_spine.png'),
    ]) {
      await shootChapter(
        tester,
        chapter: chapter,
        blocks: blocks,
        layout: layout,
        name: name,
        height: 3000,
      );
    }
  });
}
