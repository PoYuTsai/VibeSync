// Scoped visual proof — 文案優化工作包 7 的尺寸矩陣（規格 §13.2）：
// 390／320 pt × 文字縮放 1.0／1.3／2.0，正式 widget＋正式 JSON。
// Run: flutter test test/visual_proof/ebook_copy_matrix_proof_test.dart
// Out: build/visual_proof/ebook_wp7_shelf_{390,320}_{100,130,200}.png
//        書架入口：標題卡＋繼續閱讀卡（停在 7.4）＋兩張收合的單元卡
//      build/visual_proof/ebook_wp7_shelf_before_{390,320}_{100,130,200}.png
//        同一張書架，但 7.4 換回工作包 7 之前的 25 字舊章名（§13.1 的前後對照）
//      build/visual_proof/ebook_wp7_dense_{390,320}_{100,130,200}_p{n}.png
//        6.3 整章（第 5–7 冊頂層 callout＋comparison 最多的那型：2＋2，另有
//        條目庫與前往按鈕），spine 排版，每 2400 pt 一頁
//      build/visual_proof/ebook_scenario_order_{390,320}_{100,130,200}.png
//        第 2 冊 2.1 的 F／E／I／R 四張比較卡：題目（scenario）必須排在答案卡
//        之上（2026-09-04），四格都用畫面座標驗證過才截圖
//
// 每一格都先把整段內容 layout 完再截圖：RenderFlex overflow 會以 exception
// 冒出來，所以 takeException() 為 null 才是「不 overflow」的證據；截圖是給
// Eric 看章名、字級與閱讀節奏用的（§13.1、§15 工作包 7 由 Eric 真機驗收）。
// 這裡刻意用 lib/ 的 EbookShelfSection 與 EbookBlockRenderer 配 assets 裡的
// 正式 JSON，不畫示意圖、不用手工假資料（§18 第 9 條）。
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vibesync/core/theme/app_colors.dart';
import 'package:vibesync/core/theme/app_typography.dart';
import 'package:vibesync/features/learning/data/providers/ebook_providers.dart';
import 'package:vibesync/features/learning/data/repositories/ebook_catalog_repository.dart';
import 'package:vibesync/features/learning/data/repositories/ebook_progress_repository.dart';
import 'package:vibesync/features/learning/domain/models/ebook.dart';
import 'package:vibesync/features/learning/domain/models/ebook_block.dart';
import 'package:vibesync/features/learning/domain/models/ebook_progress.dart';
import 'package:vibesync/features/learning/presentation/widgets/ebook_access_gate.dart';
import 'package:vibesync/features/learning/presentation/widgets/ebook_block_renderer.dart';
import 'package:vibesync/features/learning/presentation/widgets/ebook_shelf_section.dart';

import '../helpers/ebook_test_content.dart';
import '../helpers/ebook_widget_harness.dart';
import 'proof_support.dart';

/// §13.2 的矩陣：兩種寬度 × 三種文字縮放。
const List<double> _widths = <double>[390, 320];
const List<double> _scales = <double>[1.0, 1.3, 2.0];

/// 工作包 7 之前 7.4 的章名（#67 head `53bd993` 與 main `a20e14f` 的正式 JSON）。
/// 只在「前後對照」那組截圖裡把 7.4 換回去，其餘欄位都是現在的正式內容。
const String _beforeTitle = '聊了三個月還是「網友」？因為你的訊息少了這兩樣東西';

String _cell(String subject, double width, double scale) =>
    'ebook_wp7_${subject}_${width.toInt()}_${(scale * 100).round()}';

String _cellName(double width, double scale) =>
    'ebook_scenario_order_${width.toInt()}_${(scale * 100).round()}';

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

Future<void> _capture(
  WidgetTester tester,
  GlobalKey rootKey,
  String path, {
  double pixelRatio = 3.0,
}) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(rootKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    (File(path)..createSync(recursive: true))
        .writeAsBytesSync(data!.buffer.asUint8List());
  });
}

void main() {
  late EbookCatalog catalog;

  setUpAll(() async {
    await _loadFonts();
    // 內容資產一定要在 testWidgets 之外載入：>50KB 的 loadString 走 isolate，
    // 在 fake async 下永遠不會完成，測試會整個卡死。
    catalog = await loadProductionCatalog();
  });

  /// 書架入口一格：標題卡＋繼續閱讀卡（停在 [resumeChapter]）＋兩張收合的
  /// 單元卡。有進度時兩單元收合，所以沒有書卡、不需要先解碼封面照。
  Future<void> shootShelf(
    WidgetTester tester, {
    required EbookCatalog shelfCatalog,
    required Ebook resumeBook,
    required EbookChapter resumeChapter,
    required double width,
    required double scale,
    required String name,
  }) async {
    final box = InMemoryHiveBox();
    await EbookProgressRepository(box: box).setLastChapter(
      ownerUserId: 'proof-owner',
      bookId: resumeBook.id,
      chapterId: resumeChapter.id,
    );
    final container = ProviderContainer(
      overrides: [
        ebookSubscriptionAccessProvider
            .overrideWith((ref) => const EbookSubscriptionAccess.free()),
        ebookProgressOwnerProvider
            .overrideWith((ref) => Stream<String?>.value('proof-owner')),
        ebookProgressRepositoryProvider
            .overrideWithValue(EbookProgressRepository(box: box)),
        ebookCatalogProvider.overrideWith((ref) async => shelfCatalog),
      ],
    );
    addTearDown(container.dispose);

    final rootKey = GlobalKey();
    final contentKey = GlobalKey();
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => Container(
            color: AppColors.brandInk,
            child: SingleChildScrollView(
              child: KeyedSubtree(
                key: contentKey,
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: EbookShelfSection(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    Future<void> pumpAt(double height) async {
      await tester.binding.setSurfaceSize(Size(width, height));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(fontFamily: 'AppTC', useMaterial3: true),
            routerConfig: router,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: RepaintBoundary(
                key: rootKey,
                child: DefaultTextStyle.merge(
                  style: const TextStyle(fontFamily: 'AppTC'),
                  child: child!,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpAt(2400);
    expect(tester.takeException(), isNull, reason: '$name overflow');
    // 拍到沒有繼續閱讀卡的書架卻通過的 proof 是假證據：先確認卡片與章名都在。
    expect(find.byKey(ebookResumeCardKey), findsOneWidget,
        reason: '$name 沒有繼續閱讀卡');
    expect(find.textContaining(resumeChapter.title), findsOneWidget,
        reason: '$name 沒拍到章名');

    // 縮到內容高度再拍，圖上不留空底；縮完再確認一次沒有 overflow。
    final height = tester.getSize(find.byKey(contentKey)).height;
    await tester.binding.setSurfaceSize(Size(width, height.ceilToDouble()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '$name overflow（內容高度）');
    await _capture(tester, rootKey, outPath('$name.png'));
  }

  /// 把 7.4 的章名換回工作包 7 之前的 25 字舊章名；其餘一個字都不動。
  EbookCatalog beforeCatalog() {
    const path = 'assets/learning/ebooks/book_7_chat.json';
    final raw = File(path).readAsStringSync();
    final current =
        catalog.findBook('ebook-7-chat')!.findChapter('ebook-7-chapter-4')!;
    final needle = '"title": "${current.title}"';
    expect(needle.allMatches(raw).length, 1,
        reason: '7.4 的章名在正式 JSON 裡不是恰好一處：${current.title}');
    final before = parseBookJson(
      raw.replaceFirst(needle, '"title": "$_beforeTitle"'),
      assetPath: path,
    );
    return EbookCatalog(
      books: [
        for (final book in catalog.books)
          if (book.id == before.id) before else book,
      ],
    );
  }

  testWidgets('書架入口＋繼續閱讀卡：390／320 × 1.0／1.3／2.0（含 25 字舊章名對照）',
      (tester) async {
    final afterBook = catalog.findBook('ebook-7-chat')!;
    final afterChapter = afterBook.findChapter('ebook-7-chapter-4')!;
    expect(afterChapter.title, isNot(_beforeTitle),
        reason: '7.4 還是工作包 7 之前的章名');

    final before = beforeCatalog();
    final beforeBook = before.findBook('ebook-7-chat')!;
    final beforeChapter = beforeBook.findChapter('ebook-7-chapter-4')!;
    expect(beforeChapter.title, _beforeTitle);

    for (final width in _widths) {
      for (final scale in _scales) {
        await shootShelf(
          tester,
          shelfCatalog: catalog,
          resumeBook: afterBook,
          resumeChapter: afterChapter,
          width: width,
          scale: scale,
          name: _cell('shelf', width, scale),
        );
        await shootShelf(
          tester,
          shelfCatalog: before,
          resumeBook: beforeBook,
          resumeChapter: beforeChapter,
          width: width,
          scale: scale,
          name: _cell('shelf_before', width, scale),
        );
      }
    }
  });

  /// 一章整章：與閱讀器相同的章號、章名、padding 與區塊間距（見
  /// ebook_reader_screen.dart 的 ListView），排版依該書單元（第 5–7 冊 spine）。
  /// 先 layout 整章（overflow 在這一步就會冒出來），再每 [pageHeight] 一頁截圖。
  Future<void> shootChapterPages(
    WidgetTester tester, {
    required Ebook book,
    required EbookChapter chapter,
    required double width,
    required double scale,
    required String name,
  }) async {
    const pageHeight = 2400.0;
    final rootKey = GlobalKey();
    final contentKey = GlobalKey();
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.binding.setSurfaceSize(Size(width, pageHeight));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'AppTC', useMaterial3: true),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: DefaultTextStyle.merge(
          style: const TextStyle(fontFamily: 'AppTC'),
          // 沒有 Material 祖先時 Text 會套上黃底線的 fallback 樣式。
          child: Material(
            color: AppColors.brandInk,
            child: RepaintBoundary(
              key: rootKey,
              child: Container(
                color: AppColors.brandInk,
                child: SingleChildScrollView(
                  controller: controller,
                  child: KeyedSubtree(
                    key: contentKey,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            chapter.number,
                            style: AppTypography.caption.copyWith(
                              color: AppColors.ctaStart,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            chapter.title,
                            style: AppTypography.headlineLarge.copyWith(
                              color: AppColors.onBackgroundPrimary,
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 24),
                          for (final block in chapter.blocks)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 18),
                              child: EbookBlockRenderer(
                                block: block,
                                layout: book.readingLayout,
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
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '$name overflow');
    expect(find.text(chapter.title), findsOneWidget,
        reason: '$name 沒拍到章名');

    final height = tester.getSize(find.byKey(contentKey)).height;
    final pages = (height / pageHeight).ceil();
    for (var page = 0; page < pages; page++) {
      controller.jumpTo(
        math.min(page * pageHeight, controller.position.maxScrollExtent),
      );
      await tester.pump();
      // 2.0 字級下整章會拉到上萬 pt，pixelRatio 2 已夠看字級與節奏。
      await _capture(
        tester,
        rootKey,
        outPath('${name}_p${page + 1}.png'),
        pixelRatio: 2.0,
      );
    }
  }

  /// 攤平章節區塊，含條目庫裡的巢狀區塊（2.1 的四張比較卡都在條目裡）。
  Iterable<EbookBlock> flatten(Iterable<EbookBlock> blocks) sync* {
    for (final block in blocks) {
      yield block;
      if (block is EbookEntryListBlock) {
        for (final entry in block.entries) {
          yield* flatten(entry.blocks);
        }
      }
    }
  }

  // 2026-09-04：題目原本存在 caption，被渲染在答案之後。這一格把四張卡並排
  // 拍下來，並用畫面座標證明每一張的 scenario 都在第一個答案之上。
  testWidgets('2.1 四張比較卡：題目在答案之上（390／320 × 1.0／1.3／2.0）',
      (tester) async {
    final book = catalog.findBook('ebook-2-conversation')!;
    final chapter = book.findChapter('ebook-2-chapter-1')!;
    final cards = <EbookComparisonBlock>[
      for (final id in const [
        'ebook-2-c1-cmp29',
        'ebook-2-c1-cmp35',
        'ebook-2-c1-cmp42',
        'ebook-2-c1-cmp49',
      ])
        flatten(chapter.blocks)
            .whereType<EbookComparisonBlock>()
            .firstWhere((block) => block.id == id),
    ];
    for (final card in cards) {
      expect(card.scenario, isNotNull, reason: '${card.id} 少了題目');
    }

    final rootKey = GlobalKey();
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final width in _widths) {
      for (final scale in _scales) {
        await tester.binding.setSurfaceSize(Size(width, 4000));
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(fontFamily: 'AppTC', useMaterial3: true),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: DefaultTextStyle.merge(
              style: const TextStyle(fontFamily: 'AppTC'),
              child: Material(
                color: AppColors.brandInk,
                child: RepaintBoundary(
                  key: rootKey,
                  child: Container(
                    color: AppColors.brandInk,
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final card in cards)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 18),
                                child: EbookBlockRenderer(
                                  block: card,
                                  layout: book.readingLayout,
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
          ),
        );
        await tester.pumpAndSettle();
        final cell = _cellName(width, scale);
        expect(tester.takeException(), isNull, reason: '$cell overflow');

        for (final card in cards) {
          final scenarioY = tester.getTopLeft(find.text(card.scenario!)).dy;
          final firstAnswerY =
              tester.getTopLeft(find.text(card.items.first.text)).dy;
          expect(scenarioY, lessThan(firstAnswerY),
              reason: '$cell：${card.id} 的題目掉到答案下面了');
        }

        await _capture(tester, rootKey, outPath('$cell.png'), pixelRatio: 2.0);
      }
    }
  });

  testWidgets('最密 callout／comparison 章（6.3）：390／320 × 1.0／1.3／2.0',
      (tester) async {
    final book = catalog.findBook('ebook-6-frames')!;
    final chapter = book.findChapter('ebook-6-chapter-3')!;
    expect(book.readingLayout, EbookReadingLayout.spine);

    for (final width in _widths) {
      for (final scale in _scales) {
        await shootChapterPages(
          tester,
          book: book,
          chapter: chapter,
          width: width,
          scale: scale,
          name: _cell('dense', width, scale),
        );
      }
    }
  });
}
