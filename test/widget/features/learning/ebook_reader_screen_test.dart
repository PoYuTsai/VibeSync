// test/widget/features/learning/ebook_reader_screen_test.dart
//
// 閱讀器：route chapterId 只決定初始章節、unknown id fallback、
// 完成本章 await 寫入後才翻頁、最末章完成回目錄、續讀、
// 「閱讀位置」與「完成度」是兩個標籤、直接 deep link 的返回行為。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/learning/data/providers/ebook_providers.dart';
import 'package:vibesync/features/learning/domain/ebook_reading_position.dart';
import 'package:vibesync/features/learning/domain/models/ebook.dart';
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

  testWidgets('寫入失敗不會卡在 loading，按鈕可以再按一次', (tester) async {
    await pumpEbookApp(
      tester,
      initialLocation: '/learning/books/$_freeBook/chapters/${_chapter(1)}',
      catalog: buildTestCatalog(freeChapterCount: 3),
      progressBox: FailingHiveBox(),
    );
    await tester.pumpAndSettle();

    await revealInChapter(tester, find.text('完成本章，下一章'));
    await tester.tap(find.text('完成本章，下一章'));
    await tester.pumpAndSettle();

    // 沒有翻頁、沒有假裝完成，而且按鈕回到可按狀態並提示重試。
    expect(find.text('第 1 ／ 3 章'), findsOneWidget);
    expect(find.text('完成度 0 ／ 3 章'), findsOneWidget);
    expect(find.text('進度沒有存起來，請再按一次。'), findsOneWidget);

    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, '完成本章，下一章').first,
    );
    expect(button.onPressed, isNotNull, reason: '按鈕必須解除 loading 可以再按');
  });

  testWidgets('付費書的閱讀器：未訂閱只放行試讀章，其餘章仍被閘門擋下', (tester) async {
    await pumpEbookApp(
      tester,
      initialLocation:
          '/learning/books/test-book-premium/chapters/test-book-premium-chapter-2',
      catalog: buildTestCatalog(),
      access: const EbookSubscriptionAccess.free(),
    );
    await tester.pumpAndSettle();

    expect(find.text(paywallStubText), findsOneWidget);
    expect(find.text('閱讀位置'), findsNothing);
  });

  testWidgets('漏斗跳到未解鎖的書：落在該書的試讀章，不是 paywall', (tester) async {
    // 免費書第一章放一個漏斗，目標是付費書的第二章（未訂閱讀不到）。
    final catalog = EbookCatalog(
      books: [
        buildTestEbook(
          id: _freeBook,
          number: 1,
          title: '免費測試書',
          chapters: [
            buildTestChapter(
              id: '$_freeBook-chapter-1',
              number: '1.1',
              title: '第 1 章',
              blocks: [
                buildTestStageFunnel(
                  id: 'funnel-nav',
                  targetBookId: 'test-book-premium',
                  targetChapterId: 'test-book-premium-chapter-2',
                  stageCount: 2,
                ),
                buildTestFlipCard(id: 'flip-nav'),
              ],
            ),
          ],
        ),
        buildTestEbook(
          id: 'test-book-premium',
          number: 2,
          title: '訂閱測試書',
          access: EbookAccess.premium,
          chapterCount: 2,
        ),
      ],
    );

    await pumpEbookApp(
      tester,
      initialLocation: '/learning/books/$_freeBook/chapters/$_freeBook-chapter-1',
      catalog: catalog,
      access: const EbookSubscriptionAccess.free(),
      size: const Size(390, 1600),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('症狀 1'));
    await tester.pumpAndSettle();
    await revealInChapter(tester, find.text('前往目標 1'));
    await tester.tap(find.text('前往目標 1'));
    await tester.pumpAndSettle();

    // 落在付費書的試讀章，而不是被 paywall 攔掉。
    expect(find.text(paywallStubText), findsNothing);
    expect(find.text('免費試讀章'), findsOneWidget);
    expect(find.text('第 1 章'), findsOneWidget);
    expect(find.text('第 2 章'), findsNothing);
  });

  testWidgets('已訂閱時漏斗直接跳到指定章，不降級成試讀章', (tester) async {
    final catalog = EbookCatalog(
      books: [
        buildTestEbook(
          id: _freeBook,
          number: 1,
          title: '免費測試書',
          chapters: [
            buildTestChapter(
              id: '$_freeBook-chapter-1',
              number: '1.1',
              title: '第 1 章',
              blocks: [
                buildTestStageFunnel(
                  id: 'funnel-nav-paid',
                  targetBookId: 'test-book-premium',
                  targetChapterId: 'test-book-premium-chapter-2',
                  stageCount: 2,
                ),
                buildTestFlipCard(id: 'flip-nav-paid'),
              ],
            ),
          ],
        ),
        buildTestEbook(
          id: 'test-book-premium',
          number: 2,
          title: '訂閱測試書',
          access: EbookAccess.premium,
          chapterCount: 2,
        ),
      ],
    );

    await pumpEbookApp(
      tester,
      initialLocation: '/learning/books/$_freeBook/chapters/$_freeBook-chapter-1',
      catalog: catalog,
      access: const EbookSubscriptionAccess.premium(),
      size: const Size(390, 1600),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('症狀 0'));
    await tester.pumpAndSettle();
    await revealInChapter(tester, find.text('前往目標 0'));
    await tester.tap(find.text('前往目標 0'));
    await tester.pumpAndSettle();

    expect(find.text('第 2 章'), findsOneWidget);
    expect(find.text('免費試讀章'), findsNothing);
  });

  testWidgets('訂閱狀態未確認時漏斗不提前改目標：確認為付費後仍到指定章',
      (tester) async {
    // Codex 審查 finding 2.1：用 ebookLockedFor 會把 resolving／unavailable
    // 也當成鎖著，付費使用者冷啟動或離線點漏斗會被永久改送到第一章。
    for (final pending in const [
      EbookSubscriptionAccess.resolving(),
      EbookSubscriptionAccess.unavailable(),
      EbookSubscriptionAccess.cachedPremium(unexpired: false),
    ]) {
      final catalog = EbookCatalog(
        books: [
          buildTestEbook(
            id: _freeBook,
            number: 1,
            title: '免費測試書',
            chapters: [
              buildTestChapter(
                id: '$_freeBook-chapter-1',
                number: '1.1',
                title: '第 1 章',
                blocks: [
                  buildTestStageFunnel(
                    id: 'funnel-pending',
                    targetBookId: 'test-book-premium',
                    targetChapterId: 'test-book-premium-chapter-2',
                    stageCount: 2,
                  ),
                  buildTestFlipCard(id: 'flip-pending'),
                ],
              ),
            ],
          ),
          buildTestEbook(
            id: 'test-book-premium',
            number: 2,
            title: '訂閱測試書',
            access: EbookAccess.premium,
            chapterCount: 2,
          ),
        ],
      );

      final harness = await pumpEbookApp(
        tester,
        initialLocation:
            '/learning/books/$_freeBook/chapters/$_freeBook-chapter-1',
        catalog: catalog,
        access: pending,
        size: const Size(390, 1600),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('症狀 1'));
      await tester.pumpAndSettle();
      await revealInChapter(tester, find.text('前往目標 1'));
      await tester.tap(find.text('前往目標 1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // 未確認期間不得漏出付費內容。
      expect(find.text('段落內容。'), findsNothing, reason: '$pending 期間漏出內容');

      harness.setAccess(const EbookSubscriptionAccess.premium());
      await tester.pumpAndSettle();

      // 狀態確認為付費後，應該落在漏斗原本指定的第二章。
      expect(find.text('第 2 章'), findsOneWidget,
          reason: '$pending 之後沒有回到指定章');
      expect(find.text('免費試讀章'), findsNothing);
    }
  });

  testWidgets('試讀模式：只有一頁可讀、橫滑不到第二章、主按鈕導 paywall',
      (tester) async {
    await pumpEbookApp(
      tester,
      initialLocation:
          '/learning/books/test-book-premium/chapters/test-book-premium-chapter-1',
      catalog: buildTestCatalog(),
      access: const EbookSubscriptionAccess.free(),
      size: const Size(390, 1600),
    );
    await tester.pumpAndSettle();

    expect(find.text('第 1 章'), findsOneWidget);
    expect(find.text('免費試讀章'), findsOneWidget);
    // 分母仍是整本章數，才不會讓人以為這本只有一章。
    expect(find.text('第 1 ／ 2 章'), findsOneWidget);

    // 往左滑想換章：試讀只有一頁，滑不出第二章。
    await tester.drag(find.text('段落內容。').first, const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(find.text('第 2 章'), findsNothing);

    await tester.tap(find.text('訂閱後解鎖其餘 1 章'));
    await tester.pumpAndSettle();
    expect(find.text(paywallStubText), findsOneWidget);
  });
}
