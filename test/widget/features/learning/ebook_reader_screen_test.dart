// test/widget/features/learning/ebook_reader_screen_test.dart
//
// 閱讀器：route chapterId 只決定初始章節、unknown id fallback、
// 完成本章 await 寫入後才翻頁、最末章完成回目錄、續讀、
// 「閱讀位置」與「完成度」是兩個標籤、直接 deep link 的返回行為。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/learning/data/providers/ebook_providers.dart';
import 'package:vibesync/features/learning/domain/ebook_reading_position.dart';
import 'package:vibesync/features/learning/domain/models/ebook_progress.dart';
import 'package:vibesync/features/learning/presentation/widgets/ebook_access_gate.dart';

import '../../../helpers/ebook_test_content.dart';
import '../../../helpers/ebook_widget_harness.dart';

const _freeBook = 'test-book-free';
String _chapter(int index) => '$_freeBook-chapter-$index';

/// 章末按鈕與 Quiz 在折線下方：先捲到它被建出來，再 ensureVisible 讓它真的
/// 進入可點擊區域（ListView 的 cacheExtent 會先建出畫面外的 widget）。
Future<void> revealInChapter(WidgetTester tester, Finder target) async {
  for (var attempt = 0; attempt < 15 && target.evaluate().isEmpty; attempt++) {
    await tester.drag(find.byType(PageView), const Offset(0, -320));
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

void main() {
  group('resolveInitialChapterIndex（純函式）', () {
    final book = buildTestEbook(id: _freeBook, chapterCount: 3);

    test('route chapterId 合法時直接用它', () {
      expect(
        resolveInitialChapterIndex(
          book,
          routeChapterId: _chapter(3),
          progress: EbookBookProgress.empty,
        ),
        2,
      );
    });

    test('unknown chapter fallback 到保存的 lastChapterId', () {
      expect(
        resolveInitialChapterIndex(
          book,
          routeChapterId: 'nope',
          progress: EbookBookProgress(lastChapterId: _chapter(2)),
        ),
        1,
      );
    });

    test('unknown chapter 且 lastChapterId 也失效時回第一章', () {
      expect(
        resolveInitialChapterIndex(
          book,
          routeChapterId: 'nope',
          progress: const EbookBookProgress(lastChapterId: 'gone'),
        ),
        0,
      );
    });

    test('沒有 route chapter 時，續讀落在第一個未完成章節', () {
      expect(
        resolveResumeChapterId(
          book,
          EbookBookProgress(completedChapterIds: {_chapter(1)}),
        ),
        _chapter(2),
      );
    });

    test('全部完成時回第一章', () {
      expect(
        resolveResumeChapterId(
          book,
          EbookBookProgress(
            completedChapterIds: {_chapter(1), _chapter(2), _chapter(3)},
          ),
        ),
        _chapter(1),
      );
    });

    test('lastChapterId 優先於「第一個未完成」', () {
      expect(
        resolveResumeChapterId(
          book,
          EbookBookProgress(
            lastChapterId: _chapter(3),
            completedChapterIds: {_chapter(1)},
          ),
        ),
        _chapter(3),
      );
    });

    test('ebookHasStarted 只在有進度時為 true', () {
      expect(ebookHasStarted(book, EbookBookProgress.empty), isFalse);
      expect(
        ebookHasStarted(book, const EbookBookProgress(lastChapterId: 'gone')),
        isFalse,
      );
      expect(
        ebookHasStarted(book, EbookBookProgress(lastChapterId: _chapter(2))),
        isTrue,
      );
    });
  });

  testWidgets('route chapterId 決定初始章節，位置與完成度是兩個標籤',
      (tester) async {
    await pumpEbookApp(
      tester,
      initialLocation: '/learning/books/$_freeBook/chapters/${_chapter(2)}',
      catalog: buildTestCatalog(freeChapterCount: 3),
    );
    await tester.pumpAndSettle();

    expect(find.text('第 2 ／ 3 章'), findsOneWidget);
    expect(find.text('閱讀位置'), findsOneWidget);
    expect(find.text('完成度 0 ／ 3 章'), findsOneWidget);
    expect(find.text('第 2 章'), findsOneWidget);

    await revealInChapter(tester, find.text('完成本章，下一章'));
    expect(find.text('完成本章，下一章'), findsOneWidget);
  });

  testWidgets('unknown chapter fallback 到第一章而不是空白', (tester) async {
    await pumpEbookApp(
      tester,
      initialLocation: '/learning/books/$_freeBook/chapters/does-not-exist',
      catalog: buildTestCatalog(freeChapterCount: 3),
    );
    await tester.pumpAndSettle();

    expect(find.text('第 1 ／ 3 章'), findsOneWidget);
    expect(find.text('第 1 章'), findsOneWidget);
  });

  testWidgets('重啟後續讀：unknown chapter 回到保存的續讀章節', (tester) async {
    // 同一個 box 跨兩次 pump，等同 App 重啟後仍讀到本機進度。
    final box = InMemoryHiveBox();

    final harness = await pumpEbookApp(
      tester,
      initialLocation: '/learning/books/$_freeBook/chapters/${_chapter(1)}',
      catalog: buildTestCatalog(freeChapterCount: 3),
      progressBox: box,
    );
    await tester.pumpAndSettle();

    await harness.container
        .read(ebookProgressControllerProvider.notifier)
        .setLastChapter(bookId: _freeBook, chapterId: _chapter(3));
    await tester.pumpAndSettle();

    await pumpEbookApp(
      tester,
      initialLocation: '/learning/books/$_freeBook/chapters/bogus',
      catalog: buildTestCatalog(freeChapterCount: 3),
      progressBox: box,
    );
    await tester.pumpAndSettle();

    expect(find.text('第 3 ／ 3 章'), findsOneWidget);
  });

  testWidgets('重啟後目錄頁的「繼續閱讀」指向保存的章節', (tester) async {
    final box = InMemoryHiveBox();

    final harness = await pumpEbookApp(
      tester,
      initialLocation: '/learning/books/$_freeBook/chapters/${_chapter(1)}',
      catalog: buildTestCatalog(freeChapterCount: 3),
      progressBox: box,
    );
    await tester.pumpAndSettle();
    await harness.container
        .read(ebookProgressControllerProvider.notifier)
        .setLastChapter(bookId: _freeBook, chapterId: _chapter(2));
    await tester.pumpAndSettle();

    await pumpEbookApp(
      tester,
      initialLocation: '/learning/books/$_freeBook',
      catalog: buildTestCatalog(freeChapterCount: 3),
      progressBox: box,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('繼續閱讀'));
    await tester.pumpAndSettle();

    expect(find.text('第 2 ／ 3 章'), findsOneWidget);
  });

  testWidgets('完成本章：await 寫入後才翻到下一章', (tester) async {
    final harness = await pumpEbookApp(
      tester,
      initialLocation: '/learning/books/$_freeBook/chapters/${_chapter(1)}',
      catalog: buildTestCatalog(freeChapterCount: 3),
    );
    await tester.pumpAndSettle();

    await revealInChapter(tester, find.text('完成本章，下一章'));
    await tester.tap(find.text('完成本章，下一章'));
    await tester.pumpAndSettle();

    expect(find.text('第 2 ／ 3 章'), findsOneWidget);
    expect(find.text('完成度 1 ／ 3 章'), findsOneWidget);

    final snapshot =
        harness.container.read(ebookProgressControllerProvider).value!;
    expect(
      snapshot.bookProgress(_freeBook).completedChapterIds,
      {_chapter(1)},
    );
    // 續讀位置已經跟著翻到第 2 章。
    expect(snapshot.bookProgress(_freeBook).lastChapterId, _chapter(2));
  });

  testWidgets('已完成的章節按鈕改成「下一章」', (tester) async {
    final harness = await pumpEbookApp(
      tester,
      initialLocation: '/learning/books/$_freeBook/chapters/${_chapter(1)}',
      catalog: buildTestCatalog(freeChapterCount: 3),
    );
    await tester.pumpAndSettle();

    await harness.container
        .read(ebookProgressControllerProvider.notifier)
        .markChapterCompleted(bookId: _freeBook, chapterId: _chapter(1));
    await tester.pumpAndSettle();

    await revealInChapter(tester, find.text('下一章'));
    expect(find.text('下一章'), findsOneWidget);
    expect(find.text('完成本章，下一章'), findsNothing);
    expect(find.text('本章已完成'), findsOneWidget);
  });

  testWidgets('最末章顯示完成本書，完成後離開閱讀器', (tester) async {
    final harness = await pumpEbookApp(
      tester,
      initialLocation: '/learning/books/$_freeBook/chapters/${_chapter(3)}',
      catalog: buildTestCatalog(freeChapterCount: 3),
    );
    await tester.pumpAndSettle();

    await revealInChapter(tester, find.text('完成本書'));
    expect(find.text('完成本書'), findsOneWidget);

    await tester.tap(find.text('完成本書'));
    await tester.pumpAndSettle();

    // 直接 deep link 沒有可 pop 的 route → 回書籍目錄。
    expect(find.text('免費測試書'), findsOneWidget);
    expect(
      harness.container
          .read(ebookProgressControllerProvider)
          .value!
          .bookProgress(_freeBook)
          .completedChapterIds,
      {_chapter(3)},
    );
  });

  testWidgets('橫滑換章會更新續讀位置', (tester) async {
    final harness = await pumpEbookApp(
      tester,
      initialLocation: '/learning/books/$_freeBook/chapters/${_chapter(1)}',
      catalog: buildTestCatalog(freeChapterCount: 3),
    );
    await tester.pumpAndSettle();

    await tester.fling(
      find.text('第 1 章'),
      const Offset(-400, 0),
      1200,
    );
    await tester.pumpAndSettle();

    expect(find.text('第 2 ／ 3 章'), findsOneWidget);
    expect(
      harness.container
          .read(ebookProgressControllerProvider)
          .value!
          .bookProgress(_freeBook)
          .lastChapterId,
      _chapter(2),
    );
  });

  testWidgets('章節內的 Quiz 作答會保存', (tester) async {
    final harness = await pumpEbookApp(
      tester,
      initialLocation: '/learning/books/$_freeBook/chapters/${_chapter(1)}',
      catalog: buildTestCatalog(freeChapterCount: 3),
    );
    await tester.pumpAndSettle();

    const rightChoice = '發生什麼事，是人的問題還是事的問題';
    await revealInChapter(tester, find.text(rightChoice));
    await tester.tap(find.text(rightChoice));
    await tester.pump();

    await revealInChapter(tester, find.text('送出答案'));
    await tester.tap(find.text('送出答案'));
    await tester.pumpAndSettle();

    final progress = harness.container
        .read(ebookProgressControllerProvider)
        .value!
        .bookProgress(_freeBook);
    final quizState =
        progress.quizStateFor('$_freeBook-chapter-1-quiz', 1);
    expect(quizState, isNotNull);
    expect(quizState!.solved, isTrue);
    expect(quizState.selectedChoiceIds,
        ['$_freeBook-chapter-1-quiz-b']);
  });

  testWidgets('閱讀器返回鍵在沒有 back stack 時回書籍目錄', (tester) async {
    await pumpEbookApp(
      tester,
      initialLocation: '/learning/books/$_freeBook/chapters/${_chapter(1)}',
      catalog: buildTestCatalog(freeChapterCount: 3),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.text('免費測試書'), findsOneWidget);
    expect(find.text('章節'), findsOneWidget);
  });

  testWidgets('付費書的閱讀器同樣受閘門保護', (tester) async {
    await pumpEbookApp(
      tester,
      initialLocation:
          '/learning/books/test-book-premium/chapters/test-book-premium-chapter-1',
      catalog: buildTestCatalog(),
      access: const EbookSubscriptionAccess.free(),
    );
    await tester.pumpAndSettle();

    expect(find.text(paywallStubText), findsOneWidget);
    expect(find.text('閱讀位置'), findsNothing);
  });
}
