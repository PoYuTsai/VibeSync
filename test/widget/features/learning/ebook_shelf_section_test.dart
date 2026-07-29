// test/widget/features/learning/ebook_shelf_section_test.dart
//
// 書架：四本卡、免費／鎖定 badge、完成度、鎖定卡點擊只導 paywall、
// 內容載入失敗只降級這個區塊、書架本身不出現文章額度用語。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/learning/data/providers/ebook_providers.dart';
import 'package:vibesync/features/learning/data/repositories/ebook_progress_repository.dart';
import 'package:vibesync/features/learning/domain/models/ebook.dart';
import 'package:vibesync/features/learning/presentation/widgets/ebook_access_gate.dart';
import 'package:vibesync/features/learning/presentation/widgets/ebook_cover_badge.dart';
import 'package:vibesync/features/learning/presentation/widgets/ebook_shelf_section.dart';

import '../../../helpers/ebook_test_content.dart';
import '../../../helpers/ebook_widget_harness.dart';

/// 用真實的四本內容資產建立書架 catalog。
EbookCatalog? _realCatalog;

Future<ProviderContainer> pumpShelf(
  WidgetTester tester, {
  required EbookCatalog? catalog,
  bool catalogError = false,
  bool catalogPending = false,
  EbookSubscriptionAccess access = const EbookSubscriptionAccess.free(),
  Box? progressBox,
  double textScale = 1.0,
  Size size = const Size(390, 1200),
}) async {
  final box = progressBox ?? InMemoryHiveBox();
  final container = ProviderContainer(
    overrides: [
      ebookSubscriptionAccessProvider.overrideWith((ref) => access),
      ebookProgressOwnerProvider
          .overrideWith((ref) => Stream<String?>.value('shelf-owner')),
      ebookProgressRepositoryProvider
          .overrideWithValue(EbookProgressRepository(box: box)),
      if (catalogPending)
        ebookCatalogProvider
            .overrideWith((ref) => Completer<EbookCatalog>().future)
      else if (catalogError)
        ebookCatalogProvider
            .overrideWith((ref) async => throw StateError('bad content'))
      else
        ebookCatalogProvider.overrideWith((ref) async => catalog!),
    ],
  );
  addTearDown(container.dispose);

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: EbookShelfSection(),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/paywall',
        builder: (_, __) => const Scaffold(
          body: Center(child: Text(paywallStubText)),
        ),
      ),
      GoRoute(
        path: '/learning/books/:bookId',
        builder: (context, state) => Scaffold(
          body: Center(
            child: Text('DETAIL_${state.pathParameters['bookId']}'),
          ),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    ),
  );
  return container;
}

void main() {
  setUpAll(() async {
    _realCatalog = await loadProductionCatalog();
  });

  testWidgets('顯示兩單元五本書並標出免費與鎖定', (tester) async {
    await pumpShelf(tester, catalog: _realCatalog, size: const Size(390, 2000));
    await tester.pumpAndSettle();

    // 書架標題是整套教材的名字（2026-07-27 夥伴回饋），不是「互動電子書」。
    // THE FIELD GUIDE 出現兩次：標題卡＋單元分隔列（兩個單元以上才顯示）。
    expect(find.text('THE FIELD GUIDE'), findsNWidgets(2));
    expect(find.text('THE PRIZE'), findsOneWidget);
    expect(find.textContaining('成為獎賞'), findsOneWidget);
    expect(find.text('互動電子書'), findsNothing);
    expect(find.text('診斷 · 配對開場'), findsOneWidget);
    expect(find.text('續航 · 讓對話活下去'), findsOneWidget);
    expect(find.text('避雷 · 該救還是該停'), findsOneWidget);
    expect(find.text('約會 · 從聊天到到場'), findsOneWidget);
    expect(find.text('內核 · 吸引怎麼發生'), findsOneWidget);

    // Free 使用者：Book 1 免費、三本訂閱鎖定、成為獎賞標 Essential。
    expect(find.text('免費'), findsOneWidget);
    expect(find.text('訂閱解鎖'), findsNWidgets(3));
    expect(find.text('Essential 解鎖'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsNWidgets(4));

    // 書架區塊本身不得出現文章每日額度用語。
    expect(find.textContaining('免費閱讀'), findsNothing);
    expect(find.textContaining('今日剩餘'), findsNothing);
  });

  // 2026-07-27 夥伴回饋：書號方塊改成人物照（官網 Blog 卡的做法）。
  testWidgets('每本書的封面是人物照，書號仍然讀得到', (tester) async {
    await pumpShelf(tester, catalog: _realCatalog, size: const Size(390, 2000));
    await tester.pumpAndSettle();

    final assets = tester
        .widgetList<Image>(find.byType(Image))
        .map((image) => image.image)
        .whereType<AssetImage>()
        .map((image) => image.assetName)
        .toSet();
    for (final theme in EbookTheme.values) {
      expect(
        assets,
        contains(ebookCoverPhotoAsset(theme)),
        reason: '$theme 沒有封面照',
      );
    }
    // 每個主題的照片必須互不相同，否則書看起來像同一本。
    expect(assets.length, greaterThanOrEqualTo(EbookTheme.values.length));

    // 書號在單元內從 1 起算：「第 1 冊」在兩個單元各出現一次。
    expect(find.text('第 1 冊'), findsNWidgets(2));
    for (var number = 2; number <= 4; number++) {
      expect(find.text('第 $number 冊'), findsOneWidget);
    }
  });

  testWidgets('Starter：終極指引全解鎖，成為獎賞仍標 Essential', (tester) async {
    await pumpShelf(
      tester,
      catalog: _realCatalog,
      access: const EbookSubscriptionAccess.premium(),
      size: const Size(390, 2000),
    );
    await tester.pumpAndSettle();

    expect(find.text('訂閱解鎖'), findsNothing);
    expect(find.text('免費'), findsOneWidget);
    expect(find.text('已解鎖'), findsNWidgets(3));
    // Starter 已付費，Essential 專屬書不得顯示泛用的「訂閱解鎖」。
    expect(find.text('Essential 解鎖'), findsOneWidget);
  });

  testWidgets('Essential：兩單元全部解鎖', (tester) async {
    await pumpShelf(
      tester,
      catalog: _realCatalog,
      access: const EbookSubscriptionAccess.essential(),
      size: const Size(390, 2000),
    );
    await tester.pumpAndSettle();

    expect(find.text('訂閱解鎖'), findsNothing);
    expect(find.text('Essential 解鎖'), findsNothing);
    expect(find.text('免費'), findsOneWidget);
    expect(find.text('已解鎖'), findsNWidgets(4));
  });

  testWidgets('點鎖定書進目錄頁（第一章試讀），不在書架就攔成 paywall', (tester) async {
    await pumpShelf(tester, catalog: _realCatalog, size: const Size(390, 1600));
    await tester.pumpAndSettle();

    await tester.tap(find.text('續航 · 讓對話活下去'));
    await tester.pumpAndSettle();
    // 2026-07-26 拍板：鎖定書也進目錄頁，由目錄頁的閘門顯示試讀與鎖定章。
    expect(find.text('DETAIL_ebook-2-conversation'), findsOneWidget);
    expect(find.text(paywallStubText), findsNothing);
  });

  testWidgets('點免費書進入書籍目錄', (tester) async {
    await pumpShelf(tester, catalog: _realCatalog, size: const Size(390, 1600));
    await tester.pumpAndSettle();

    await tester.tap(find.text('診斷 · 配對開場'));
    await tester.pumpAndSettle();
    expect(find.text('DETAIL_ebook-1-bottleneck'), findsOneWidget);
  });

  testWidgets('鎖定的書仍顯示完成度（降級後不假裝沒讀過）', (tester) async {
    final box = InMemoryHiveBox();
    final repo = EbookProgressRepository(box: box);
    await repo.markChapterCompleted(
      ownerUserId: 'shelf-owner',
      bookId: 'ebook-2-conversation',
      chapterId: 'ebook-2-chapter-1',
    );

    await pumpShelf(
      tester,
      catalog: _realCatalog,
      progressBox: box,
      size: const Size(390, 1600),
    );
    await tester.pumpAndSettle();

    expect(find.text('訂閱解鎖'), findsNWidgets(3));
    expect(find.text('Essential 解鎖'), findsOneWidget);
    // 不寫死總章數，內容擴充時不該讓這個斷言變脆。
    expect(find.textContaining('已完成 1／'), findsOneWidget);
  });

  testWidgets('訂閱還在確認時：不顯示「訂閱解鎖」、不導 paywall', (tester) async {
    await pumpShelf(
      tester,
      catalog: _realCatalog,
      access: const EbookSubscriptionAccess.resolving(),
      size: const Size(390, 1600),
    );
    await tester.pumpAndSettle();

    // 狀態未確認不得包裝成 Free upsell。
    expect(find.text('訂閱解鎖'), findsNothing);
    expect(find.text('已解鎖'), findsNothing);
    expect(find.text('確認訂閱中'), findsNWidgets(4));
    expect(find.text('免費'), findsOneWidget);

    await tester.tap(find.text('續航 · 讓對話活下去'));
    await tester.pumpAndSettle();
    // 進書籍目錄（由閘門顯示 loading／重試），不是 paywall。
    expect(find.text(paywallStubText), findsNothing);
    expect(find.text('DETAIL_ebook-2-conversation'), findsOneWidget);
  });

  testWidgets('訂閱無法確認時：同樣不導 paywall，交給閘門重試', (tester) async {
    await pumpShelf(
      tester,
      catalog: _realCatalog,
      access: const EbookSubscriptionAccess.unavailable(),
      size: const Size(390, 1600),
    );
    await tester.pumpAndSettle();

    expect(find.text('訂閱解鎖'), findsNothing);
    expect(find.text('確認訂閱中'), findsNWidgets(4));

    await tester.tap(find.text('避雷 · 該救還是該停'));
    await tester.pumpAndSettle();
    expect(find.text(paywallStubText), findsNothing);
    expect(find.text('DETAIL_ebook-3-rescue'), findsOneWidget);
  });

  testWidgets('內容載入失敗只降級書架區塊', (tester) async {
    await pumpShelf(tester, catalog: null, catalogError: true);
    await tester.pumpAndSettle();

    expect(find.textContaining('電子書內容暫時無法載入'), findsOneWidget);
    expect(find.text('診斷 · 配對開場'), findsNothing);
  });

  testWidgets('載入中顯示佔位而不是空白', (tester) async {
    await pumpShelf(tester, catalog: null, catalogPending: true);
    await tester.pump();

    expect(find.text('正在載入電子書…'), findsOneWidget);
  });

  testWidgets('320px 寬 + 2.0 text scale 不 overflow', (tester) async {
    await pumpShelf(
      tester,
      catalog: _realCatalog,
      textScale: 2.0,
      size: const Size(320, 4000),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
