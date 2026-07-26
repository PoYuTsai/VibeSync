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

  testWidgets('顯示四本書並標出免費與鎖定', (tester) async {
    await pumpShelf(tester, catalog: _realCatalog, size: const Size(390, 1600));
    await tester.pumpAndSettle();

    expect(find.text('互動電子書'), findsOneWidget);
    expect(find.text('先找到真正卡點'), findsOneWidget);
    expect(find.text('看懂一段對話'), findsOneWidget);
    expect(find.text('對話急救室：該救，還是該停'), findsOneWidget);
    expect(find.text('從聊天走到見面'), findsOneWidget);

    // Free 使用者：Book 1 免費、其餘三本鎖定。
    expect(find.text('免費'), findsOneWidget);
    expect(find.text('訂閱解鎖'), findsNWidgets(3));
    expect(find.byIcon(Icons.lock_outline), findsNWidgets(3));

    // 書架區塊本身不得出現文章每日額度用語。
    expect(find.textContaining('免費閱讀'), findsNothing);
    expect(find.textContaining('今日剩餘'), findsNothing);
  });

  testWidgets('付費使用者四本全部解鎖', (tester) async {
    await pumpShelf(
      tester,
      catalog: _realCatalog,
      access: const EbookSubscriptionAccess.premium(),
      size: const Size(390, 1600),
    );
    await tester.pumpAndSettle();

    expect(find.text('訂閱解鎖'), findsNothing);
    expect(find.text('免費'), findsOneWidget);
    expect(find.text('已解鎖'), findsNWidgets(3));
  });

  testWidgets('點鎖定書進目錄頁（第一章試讀），不在書架就攔成 paywall', (tester) async {
    await pumpShelf(tester, catalog: _realCatalog, size: const Size(390, 1600));
    await tester.pumpAndSettle();

    await tester.tap(find.text('看懂一段對話'));
    await tester.pumpAndSettle();
    // 2026-07-26 拍板：鎖定書也進目錄頁，由目錄頁的閘門顯示試讀與鎖定章。
    expect(find.text('DETAIL_ebook-2-conversation'), findsOneWidget);
    expect(find.text(paywallStubText), findsNothing);
  });

  testWidgets('點免費書進入書籍目錄', (tester) async {
    await pumpShelf(tester, catalog: _realCatalog, size: const Size(390, 1600));
    await tester.pumpAndSettle();

    await tester.tap(find.text('先找到真正卡點'));
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
    expect(find.text('確認訂閱中'), findsNWidgets(3));
    expect(find.text('免費'), findsOneWidget);

    await tester.tap(find.text('看懂一段對話'));
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

    await tester.tap(find.text('對話急救室：該救，還是該停'));
    await tester.pumpAndSettle();
    expect(find.text(paywallStubText), findsNothing);
    expect(find.text('DETAIL_ebook-3-rescue'), findsOneWidget);
  });

  testWidgets('內容載入失敗只降級書架區塊', (tester) async {
    await pumpShelf(tester, catalog: null, catalogError: true);
    await tester.pumpAndSettle();

    expect(find.textContaining('電子書內容暫時無法載入'), findsOneWidget);
    expect(find.text('先找到真正卡點'), findsNothing);
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
