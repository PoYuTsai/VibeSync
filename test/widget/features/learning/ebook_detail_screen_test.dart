// test/widget/features/learning/ebook_detail_screen_test.dart
//
// 書籍目錄頁：封面／完成度／章節清單、開始 vs 繼續閱讀、
// 完成狀態有文字不只顏色、直接 deep link 的返回行為。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/learning/data/providers/ebook_providers.dart';
import 'package:vibesync/features/learning/domain/models/ebook.dart';
import 'package:vibesync/features/learning/presentation/widgets/ebook_access_gate.dart';
import 'package:vibesync/shared/widgets/brand/brand_kit.dart';

import '../../../helpers/ebook_test_content.dart';
import '../../../helpers/ebook_widget_harness.dart';

const _freeBook = 'test-book-free';

void main() {
  testWidgets('顯示封面、章節清單與完成度', (tester) async {
    await pumpEbookApp(
      tester,
      initialLocation: '/learning/books/$_freeBook',
      catalog: buildTestCatalog(freeChapterCount: 3),
      access: const EbookSubscriptionAccess.free(),
    );
    await tester.pumpAndSettle();

    // 標題列講的是這套教材的名字，不再是「互動電子書」（2026-07-27 Eric）。
    expect(find.text(kEbookCollectionTitle), findsOneWidget);
    expect(find.text('互動電子書'), findsNothing);
    expect(find.text('免費測試書'), findsOneWidget);
    expect(find.text('3 章'), findsOneWidget);
    expect(find.text('約 30 分鐘'), findsOneWidget);
    expect(find.text('已完成 0 / 3 章'), findsOneWidget);
    expect(find.text('完成度'), findsOneWidget);
    expect(find.text('1.1　第 1 章'), findsOneWidget);
    expect(find.text('未完成'), findsWidgets);

    // 第 3 章在畫面外，捲下去確認整份目錄都在。
    await tester.scrollUntilVisible(find.text('1.3　第 3 章'), 200);
    await tester.pumpAndSettle();
    expect(find.text('1.3　第 3 章'), findsOneWidget);
    // 目錄頁不得出現文章額度用語。
    expect(find.textContaining('免費閱讀'), findsNothing);
  });

  testWidgets('沒有進度時 CTA 是「開始閱讀」', (tester) async {
    await pumpEbookApp(
      tester,
      initialLocation: '/learning/books/$_freeBook',
      catalog: buildTestCatalog(freeChapterCount: 3),
    );
    await tester.pumpAndSettle();

    expect(find.text('開始閱讀'), findsOneWidget);
    expect(find.text('繼續閱讀'), findsNothing);
  });

  testWidgets('有進度時 CTA 變「繼續閱讀」並顯示已完成', (tester) async {
    final harness = await pumpEbookApp(
      tester,
      initialLocation: '/learning/books/$_freeBook',
      catalog: buildTestCatalog(freeChapterCount: 3),
    );
    await tester.pumpAndSettle();

    await harness.container
        .read(ebookProgressControllerProvider.notifier)
        .markChapterCompleted(
          bookId: _freeBook,
          chapterId: '$_freeBook-chapter-1',
        );
    await tester.pumpAndSettle();

    expect(find.text('繼續閱讀'), findsOneWidget);
    expect(find.text('已完成 1 / 3 章'), findsOneWidget);
    // 完成狀態同時有文字與圖示。
    expect(find.text('已完成'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
  });

  testWidgets('點章節列進入閱讀器該章', (tester) async {
    await pumpEbookApp(
      tester,
      initialLocation: '/learning/books/$_freeBook',
      catalog: buildTestCatalog(freeChapterCount: 3),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('1.2　第 2 章'));
    await tester.pumpAndSettle();

    expect(find.text('第 2 ／ 3 章'), findsOneWidget);
  });

  // 2026-07-27 夥伴回饋：第 3、4 本沒有試讀章，但目錄要看得到。
  testWidgets('沒有試讀章的付費書：目錄看得到，每一章都鎖著，CTA 是訂閱後解鎖',
      (tester) async {
    final catalog = EbookCatalog(
      books: [
        buildTestEbook(id: _freeBook, number: 1, title: '免費測試書'),
        buildTestEbook(
          id: 'test-book-premium',
          number: 2,
          title: '訂閱測試書',
          access: EbookAccess.premium,
        ),
        buildTestEbook(
          id: 'test-book-locked',
          number: 3,
          title: '無試讀測試書',
          access: EbookAccess.premium,
          chapterCount: 2,
        ),
      ],
    );

    await pumpEbookApp(
      tester,
      initialLocation: '/learning/books/test-book-locked',
      catalog: catalog,
      access: const EbookSubscriptionAccess.free(),
      size: const Size(390, 1400),
    );
    await tester.pumpAndSettle();

    // 目錄仍然看得到，而且沒有被自動彈到 paywall。
    expect(find.text(paywallStubText), findsNothing);
    expect(find.text('無試讀測試書'), findsOneWidget);
    expect(find.text('3.1　第 1 章'), findsOneWidget);
    expect(find.text('3.2　第 2 章'), findsOneWidget);

    // 免費範圍講清楚，且不得出現試讀入口。
    // （「訂閱後解鎖」同時是主按鈕與每一列鎖定章的標籤，所以指定 widget 型別。）
    expect(
      find.widgetWithText(BrandPrimaryButton, '訂閱後解鎖'),
      findsOneWidget,
    );
    expect(find.text('免費試讀第一章'), findsNothing);
    expect(find.text('免費試讀'), findsNothing);
    expect(find.byIcon(Icons.lock_outline), findsNWidgets(3));
    // premium 鎖卡要把 Essential 的多 3 冊賣出來（稽核 P3 補）；
    // 2026-09-04 工作包 7 拆短後的說法。
    expect(
      find.textContaining('Essential 再多開《成為獎賞》三冊'),
      findsOneWidget,
    );

    // 章節列點下去是 paywall，不是閱讀器。
    await tester.tap(find.text('3.1　第 1 章'));
    await tester.pumpAndSettle();
    expect(find.text(paywallStubText), findsOneWidget);
    expect(find.text('閱讀位置'), findsNothing);
  });

  testWidgets('Essential 專屬書的鎖卡講「Essential 專屬」，不對 Starter 謊稱訂閱即全開',
      (tester) async {
    final catalog = EbookCatalog(
      books: [
        buildTestEbook(id: _freeBook, number: 1, title: '免費測試書'),
        buildTestEbook(
          id: 'test-book-essential',
          number: 5,
          title: 'Essential 測試書',
          access: EbookAccess.essential,
          chapterCount: 2,
        ),
      ],
    );

    await pumpEbookApp(
      tester,
      initialLocation: '/learning/books/test-book-essential',
      catalog: catalog,
      access: const EbookSubscriptionAccess.free(),
      size: const Size(390, 1400),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Essential 專屬'), findsOneWidget);
    expect(find.textContaining('Starter 可以讀第 2–4 冊'), findsOneWidget);
    expect(find.textContaining('再多開《成為獎賞》'), findsNothing);
  });

  testWidgets('有試讀章的付費書仍然走試讀分支', (tester) async {
    await pumpEbookApp(
      tester,
      initialLocation: '/learning/books/test-book-premium',
      catalog: buildTestCatalog(),
      access: const EbookSubscriptionAccess.free(),
      size: const Size(390, 1400),
    );
    await tester.pumpAndSettle();

    expect(find.text('免費試讀第一章'), findsOneWidget);
    expect(
      find.widgetWithText(BrandPrimaryButton, '訂閱後解鎖'),
      findsNothing,
    );
    // 試讀卡（工作包 7 拆短）：先講這本的免費範圍與不用照順序讀，再一句講方案。
    expect(
      find.textContaining('其餘 1 章要訂閱；不用照順序讀'),
      findsOneWidget,
    );
    expect(find.textContaining('Essential 再多開《成為獎賞》三冊'), findsOneWidget);
  });

  testWidgets('直接 deep link 進來時返回鍵回學習頁而不是退出 App', (tester) async {
    await pumpEbookApp(
      tester,
      initialLocation: '/learning/books/$_freeBook',
      catalog: buildTestCatalog(),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.text(homeStubText), findsOneWidget);
  });
}
