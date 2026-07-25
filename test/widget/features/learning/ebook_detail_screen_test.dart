// test/widget/features/learning/ebook_detail_screen_test.dart
//
// 書籍目錄頁：封面／完成度／章節清單、開始 vs 繼續閱讀、
// 完成狀態有文字不只顏色、直接 deep link 的返回行為。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/learning/data/providers/ebook_providers.dart';
import 'package:vibesync/features/learning/presentation/widgets/ebook_access_gate.dart';

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
    expect(find.text('閱讀位置'), findsOneWidget);
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
