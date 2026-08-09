// test/widget/features/learning/ebook_shelf_section_test.dart
//
// 書架：單元群組收合（2026-08-09 減長批）、免費／鎖定 badge、完成度、
// 繼續閱讀捷徑卡、內容載入失敗只降級這個區塊、書架本身不出現文章額度用語。
//
// 預設展開規則：無進度＝展開第一單元（終極指引）、第二單元收合；
// 有進度＝兩單元全收合＋繼續閱讀卡。
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

/// 點單元群組卡展開該單元的書卡。
Future<void> expandUnit(WidgetTester tester, EbookUnit unit) async {
  await tester.tap(find.byKey(ebookUnitGroupKey(unit)));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    _realCatalog = await loadProductionCatalog();
  });

  testWidgets('無進度預設：第一單元展開，第二單元點了才亮出七本與鎖定', (tester) async {
    await pumpShelf(tester, catalog: _realCatalog, size: const Size(390, 2000));
    await tester.pumpAndSettle();

    // 2026-08-09 拍板二輪：hero 副標改「系統化實戰教材」，THE FIELD GUIDE
    // 只留在第一單元群組卡（kicker 移到中文標題下方），不再重複兩次。
    expect(find.text('系統化實戰教材'), findsOneWidget);
    expect(find.text('THE FIELD GUIDE'), findsOneWidget);
    expect(find.text('THE PRIZE'), findsOneWidget);
    expect(find.textContaining('成為獎賞'), findsOneWidget);
    expect(find.text('互動電子書'), findsNothing);

    // 無進度：沒有繼續閱讀卡；群組摘要都是 0 本已開始。
    expect(find.byKey(ebookResumeCardKey), findsNothing);
    expect(find.text('0/4 本已開始'), findsOneWidget);
    expect(find.text('0/3 本已開始'), findsOneWidget);

    // 第一單元展開：四本書卡與 Free 視角的 badge 直接可見。
    expect(find.text('診斷 · 配對開場'), findsOneWidget);
    expect(find.text('續航 · 讓對話活下去'), findsOneWidget);
    expect(find.text('避雷 · 該救還是該停'), findsOneWidget);
    expect(find.text('約會 · 從聊天到到場'), findsOneWidget);
    expect(find.text('免費'), findsOneWidget);
    expect(find.text('訂閱解鎖'), findsNWidgets(3));
    expect(find.byIcon(Icons.lock_outline), findsNWidgets(3));

    // 第二單元收合：書卡與 Essential 標籤都還不出現。
    expect(find.text('內核 · 吸引怎麼發生'), findsNothing);
    expect(find.text('Essential 解鎖'), findsNothing);

    await expandUnit(tester, EbookUnit.becomeThePrize);
    expect(find.text('內核 · 吸引怎麼發生'), findsOneWidget);
    expect(find.text('框架 · 這段關係誰在主導'), findsOneWidget);
    expect(find.text('進階聊天 · 讀懂反應再出手'), findsOneWidget);
    expect(find.text('Essential 解鎖'), findsNWidgets(3));
    expect(find.byIcon(Icons.lock_outline), findsNWidgets(6));

    // 再點一次收回去。
    await expandUnit(tester, EbookUnit.becomeThePrize);
    expect(find.text('內核 · 吸引怎麼發生'), findsNothing);

    // 書架區塊本身不得出現文章每日額度用語。
    expect(find.textContaining('免費閱讀'), findsNothing);
    expect(find.textContaining('今日剩餘'), findsNothing);
  });

  // 2026-07-27 夥伴回饋：書號方塊改成人物照（官網 Blog 卡的做法）。
  testWidgets('每本書的封面是人物照，書號仍然讀得到', (tester) async {
    await pumpShelf(tester, catalog: _realCatalog, size: const Size(390, 2600));
    await tester.pumpAndSettle();
    // 封面斷言要看到全部七本：先展開收合中的第二單元。
    await expandUnit(tester, EbookUnit.becomeThePrize);
    final catalog = _realCatalog!;

    final assets = tester
        .widgetList<Image>(find.byType(Image))
        .map((image) => image.image)
        .whereType<AssetImage>()
        .map((image) => image.assetName)
        .toSet();
    for (final book in catalog.books) {
      expect(
        assets,
        contains(ebookCoverPhotoAsset(book)),
        reason: '${book.id} 沒有封面照',
      );
    }
    final coverAssets =
        catalog.books.map(ebookCoverPhotoAsset).toList(growable: false);
    final ultimateAssets = catalog.books
        .where((book) => book.unit == EbookUnit.ultimateGuide)
        .map(ebookCoverPhotoAsset)
        .toSet();
    final prizeAssets = catalog.books
        .where((book) => book.unit == EbookUnit.becomeThePrize)
        .map(ebookCoverPhotoAsset)
        .toSet();

    // 七本書各自使用不同女孩；新單元三張也不能重用終極指引四張。
    expect(coverAssets.toSet(), hasLength(coverAssets.length));
    expect(prizeAssets, hasLength(3));
    expect(prizeAssets.intersection(ultimateAssets), isEmpty);
    expect(assets.length, greaterThanOrEqualTo(catalog.books.length));

    // 書號在單元內從 1 起算：「第 1～3 冊」在兩個單元各出現一次。
    expect(find.text('第 1 冊'), findsNWidgets(2));
    expect(find.text('第 2 冊'), findsNWidgets(2));
    expect(find.text('第 3 冊'), findsNWidgets(2));
    expect(find.text('第 4 冊'), findsOneWidget);
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
    await expandUnit(tester, EbookUnit.becomeThePrize);
    expect(find.text('訂閱解鎖'), findsNothing);
    expect(find.text('Essential 解鎖'), findsNWidgets(3));
  });

  testWidgets('Essential：兩單元全部解鎖', (tester) async {
    await pumpShelf(
      tester,
      catalog: _realCatalog,
      access: const EbookSubscriptionAccess.essential(),
      size: const Size(390, 2000),
    );
    await tester.pumpAndSettle();
    await expandUnit(tester, EbookUnit.becomeThePrize);

    expect(find.text('訂閱解鎖'), findsNothing);
    expect(find.text('Essential 解鎖'), findsNothing);
    expect(find.text('免費'), findsOneWidget);
    expect(find.text('已解鎖'), findsNWidgets(6));
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

    // 有進度：兩單元預設收合、頂端出繼續閱讀卡指向那本讀到一半的書。
    expect(find.byKey(ebookResumeCardKey), findsOneWidget);
    expect(find.text('繼續閱讀'), findsOneWidget);
    expect(find.text('續航 · 讓對話活下去'), findsOneWidget);
    expect(find.text('1/4 本已開始'), findsOneWidget);
    expect(find.text('診斷 · 配對開場'), findsNothing);

    // 展開第一單元後，鎖定書卡照舊顯示完成度（降級後不假裝沒讀過）。
    await expandUnit(tester, EbookUnit.ultimateGuide);
    expect(find.text('訂閱解鎖'), findsNWidgets(3));
    // 不寫死總章數，內容擴充時不該讓這個斷言變脆。
    expect(find.textContaining('已完成 1／'), findsOneWidget);

    await expandUnit(tester, EbookUnit.becomeThePrize);
    expect(find.text('Essential 解鎖'), findsNWidgets(3));
  });

  testWidgets('進度到位前不拍板預設：有進度的使用者絕不閃現第一單元展開', (tester) async {
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

    // 逐幀推進到收斂：進度 provider 第一幀是 loading（人人看似無進度），
    // 那時若就拍板預設，會先閃現第一單元展開、下一幀又收回。任何一幀都
    // 不得出現第一單元的書卡——含 pumpWidget 已產出的首幀（先斷言再推進）。
    expect(find.text('診斷 · 配對開場'), findsNothing);
    for (var i = 0; i < 24; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('診斷 · 配對開場'), findsNothing);
    }
    await tester.pumpAndSettle();

    expect(find.text('診斷 · 配對開場'), findsNothing);
    expect(find.byKey(ebookResumeCardKey), findsOneWidget);
  });

  testWidgets('session 中進度更新：繼續閱讀卡即時出現，使用者展開狀態不重置', (tester) async {
    final container = await pumpShelf(
      tester,
      catalog: _realCatalog,
      size: const Size(390, 2000),
    );
    await tester.pumpAndSettle();

    // 無進度預設：第一單元展開、沒有繼續閱讀卡。
    expect(find.text('診斷 · 配對開場'), findsOneWidget);
    expect(find.byKey(ebookResumeCardKey), findsNothing);

    // 模擬同 session 讀完一章回到書架（進度 reload）。
    await container
        .read(ebookProgressControllerProvider.notifier)
        .markChapterCompleted(
          bookId: 'ebook-1-bottleneck',
          chapterId: 'ebook-1-chapter-1',
        );
    await tester.pumpAndSettle();

    // 繼續閱讀卡即時出現；已決定過的展開狀態不因進度更新被重置收合。
    // 書名出現兩次＝繼續閱讀卡＋仍展開的書卡；同單元另一本也還看得到。
    expect(find.byKey(ebookResumeCardKey), findsOneWidget);
    expect(find.text('1/4 本已開始'), findsOneWidget);
    expect(find.text('診斷 · 配對開場'), findsNWidgets(2));
    expect(find.text('續航 · 讓對話活下去'), findsOneWidget);
  });

  testWidgets('點繼續閱讀卡直接進該書目錄頁', (tester) async {
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

    await tester.tap(find.byKey(ebookResumeCardKey));
    await tester.pumpAndSettle();
    expect(find.text('DETAIL_ebook-2-conversation'), findsOneWidget);
    expect(find.text(paywallStubText), findsNothing);
  });

  testWidgets('訂閱還在確認時：不顯示「訂閱解鎖」、不導 paywall', (tester) async {
    await pumpShelf(
      tester,
      catalog: _realCatalog,
      access: const EbookSubscriptionAccess.resolving(),
      size: const Size(390, 1600),
    );
    await tester.pumpAndSettle();

    // 狀態未確認不得包裝成 Free upsell。第一單元展開＝免費 1＋確認中 3。
    expect(find.text('訂閱解鎖'), findsNothing);
    expect(find.text('已解鎖'), findsNothing);
    expect(find.text('確認訂閱中'), findsNWidgets(3));
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
    expect(find.text('確認訂閱中'), findsNWidgets(3));

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

  testWidgets('320px 寬 + 2.0 text scale 不 overflow（含展開第二單元）', (tester) async {
    await pumpShelf(
      tester,
      catalog: _realCatalog,
      textScale: 2.0,
      size: const Size(320, 4000),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await expandUnit(tester, EbookUnit.becomeThePrize);
    expect(tester.takeException(), isNull);
  });
}
