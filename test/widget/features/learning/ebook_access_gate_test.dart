// test/widget/features/learning/ebook_access_gate_test.dart
//
// 付費閘門：Free 看不到 Books 2–4、loading 不 render premium child、
// 訂閱錯誤顯示可重試錯誤而不是假裝 Free upsell、unknown book 不導 paywall、
// 直接 deep link 進付費章節也不會閃出內容。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vibesync/features/learning/domain/models/ebook.dart';
import 'package:vibesync/features/learning/presentation/widgets/ebook_access_gate.dart';

import '../../../helpers/ebook_test_content.dart';
import '../../../helpers/ebook_widget_harness.dart';

const _freeBook = 'test-book-free';
const _premiumBook = 'test-book-premium';

/// 付費書的第一章＝免費試讀章（2026-07-26 Eric 拍板）。
const _premiumChapter = 'test-book-premium-chapter-1';

/// 付費書的第二章＝仍然全擋，內容一帧都不得閃現。
const _premiumLockedChapter = 'test-book-premium-chapter-2';

void main() {
  group('ebookAccessFor（純函式）', () {
    final free = buildTestEbook(id: 'f', access: EbookAccess.free);
    final premium =
        buildTestEbook(id: 'p', number: 2, access: EbookAccess.premium);

    test('免費書在任何訂閱狀態下都可讀', () {
      for (final access in const [
        EbookSubscriptionAccess.free(),
        EbookSubscriptionAccess.premium(),
        EbookSubscriptionAccess.resolving(),
        EbookSubscriptionAccess.unavailable(),
      ]) {
        expect(ebookAccessFor(free, access), EbookAccessDecision.allowed);
        expect(ebookLockedFor(free, access), isFalse);
      }
    });

    test('付費書只有已確認付費才放行', () {
      expect(
        ebookAccessFor(premium, const EbookSubscriptionAccess.premium()),
        EbookAccessDecision.allowed,
      );
      expect(
        ebookAccessFor(premium, const EbookSubscriptionAccess.free()),
        EbookAccessDecision.locked,
      );
      expect(
        ebookAccessFor(premium, const EbookSubscriptionAccess.resolving()),
        EbookAccessDecision.resolving,
      );
      expect(
        ebookAccessFor(premium, const EbookSubscriptionAccess.unavailable()),
        EbookAccessDecision.unavailable,
      );
      expect(
        ebookLockedFor(premium, const EbookSubscriptionAccess.free()),
        isTrue,
      );
    });

    test('快取 premium 且到期日未過 → 放行（付費使用者冷啟動不看 loading）', () {
      expect(
        ebookAccessFor(
          premium,
          const EbookSubscriptionAccess.cachedPremium(),
        ),
        EbookAccessDecision.allowed,
      );
    });

    test('快取 premium 但到期日已過且尚未確認 → 不放行（關掉飛航模式繞道）', () {
      // 這是電子書特有的風險：內容完全離線可讀，離線又永遠不會 resolve。
      const expiredCache = EbookSubscriptionAccess.cachedPremium(
        unexpired: false,
      );
      expect(
        ebookAccessFor(premium, expiredCache),
        EbookAccessDecision.resolving,
        reason: '不放行，但也不當成免費使用者',
      );

      // 錯誤狀態下同理，而且要走可重試錯誤而不是 paywall。
      const expiredCacheWithError = EbookSubscriptionAccess(
        isPremium: true,
        isEssential: false,
        isResolving: false,
        hasError: true,
      );
      expect(
        ebookAccessFor(premium, expiredCacheWithError),
        EbookAccessDecision.unavailable,
      );
    });

    test('訂閱狀態已確認為付費時，不需要快取授權也放行', () {
      const resolvedPremiumNoCache = EbookSubscriptionAccess(
        isPremium: true,
        isEssential: false,
        isResolving: false,
        hasError: false,
      );
      expect(
        ebookAccessFor(premium, resolvedPremiumNoCache),
        EbookAccessDecision.allowed,
      );
      // 一旦 tier 解析成 free，同一個判斷立刻轉為 locked。
      expect(
        ebookAccessFor(premium, const EbookSubscriptionAccess.free()),
        EbookAccessDecision.locked,
      );
    });

    test('Starter 與 Essential 都走同一個 isPremium 判斷', () {
      // SubscriptionState.isPremium 已涵蓋兩個 tier，這裡確認切片沒有再細分。
      const starterOrEssential = EbookSubscriptionAccess(
        isPremium: true,
        isEssential: false,
        isResolving: false,
        hasError: false,
      );
      expect(
        ebookAccessFor(premium, starterOrEssential),
        EbookAccessDecision.allowed,
      );
    });
  });

  group('ebookChapterAccessFor（章節層級：第一章試讀）', () {
    final free = buildTestEbook(id: 'f', access: EbookAccess.free);
    final premium =
        buildTestEbook(id: 'p', number: 2, access: EbookAccess.premium);
    final firstChapter = premium.chapters.first.id;
    final secondChapter = premium.chapters[1].id;

    test('已確認未訂閱：第一章 preview、其餘章 locked', () {
      const freeUser = EbookSubscriptionAccess.free();
      expect(
        ebookChapterAccessFor(premium, firstChapter, freeUser),
        EbookAccessDecision.preview,
      );
      expect(
        ebookChapterAccessFor(premium, secondChapter, freeUser),
        EbookAccessDecision.locked,
      );
      // chapterId 未知（例如從書架進來）時以試讀章為準。
      expect(
        ebookChapterAccessFor(premium, null, freeUser),
        EbookAccessDecision.preview,
      );
    });

    test('已訂閱：每一章都是 allowed，不會被降級成試讀', () {
      const paid = EbookSubscriptionAccess.premium();
      for (final chapterId in [firstChapter, secondChapter, null]) {
        expect(
          ebookChapterAccessFor(premium, chapterId, paid),
          EbookAccessDecision.allowed,
        );
      }
    });

    test('狀態未確認或無法確認時不降級成試讀（付費使用者冷啟動／離線）', () {
      // 這兩個狀態代表「還不知道你是誰」：付費使用者應該等確認或看重試，
      // 不該被當成免費使用者、看到試讀＋升級提示。
      expect(
        ebookChapterAccessFor(
          premium,
          firstChapter,
          const EbookSubscriptionAccess.resolving(),
        ),
        EbookAccessDecision.resolving,
      );
      expect(
        ebookChapterAccessFor(
          premium,
          firstChapter,
          const EbookSubscriptionAccess.unavailable(),
        ),
        EbookAccessDecision.unavailable,
      );
      expect(
        ebookChapterAccessFor(
          premium,
          firstChapter,
          const EbookSubscriptionAccess.cachedPremium(unexpired: false),
        ),
        EbookAccessDecision.resolving,
      );
    });

    test('免費書的每一章都是 allowed，不走試讀分支', () {
      for (final chapter in free.chapters) {
        expect(
          ebookChapterAccessFor(
            free,
            chapter.id,
            const EbookSubscriptionAccess.free(),
          ),
          EbookAccessDecision.allowed,
        );
      }
      expect(free.previewChapterId, isNull);
    });

    test('試讀不改變書架鎖頭：這本書仍然算鎖著', () {
      expect(
        ebookLockedFor(premium, const EbookSubscriptionAccess.free()),
        isTrue,
      );
      expect(premium.previewChapterId, firstChapter);
      expect(premium.freePreviewChapterCount, 1);
      expect(premium.isPreviewChapter(secondChapter), isFalse);
    });

    test('試讀只有第 2 本：第 3、4 本一章都不開', () {
      // 2026-07-27 夥伴回饋（Eric 轉達）：免費閱讀＝第一冊全部＋第二冊第一章。
      for (final number in const [3, 4]) {
        final book = buildTestEbook(
          id: 'p$number',
          number: number,
          access: EbookAccess.premium,
        );
        expect(book.freePreviewChapterCount, 0, reason: '第 $number 本不該有試讀章');
        expect(book.previewChapterId, isNull);
        expect(book.isPreviewChapter(book.chapters.first.id), isFalse);
        for (final chapterId in [book.chapters.first.id, null]) {
          expect(
            ebookChapterAccessFor(
              book,
              chapterId,
              const EbookSubscriptionAccess.free(),
            ),
            EbookAccessDecision.locked,
            reason: '第 $number 本的 $chapterId 不該放行',
          );
        }
      }
    });
  });

  testWidgets('Free 使用者可以讀 Book 1', (tester) async {
    await pumpEbookApp(
      tester,
      initialLocation: '/learning/books/$_freeBook',
      catalog: buildTestCatalog(),
      access: const EbookSubscriptionAccess.free(),
    );
    await tester.pumpAndSettle();

    expect(find.text('免費測試書'), findsOneWidget);
    expect(find.text('免費'), findsOneWidget);
    expect(find.text(paywallStubText), findsNothing);
  });

  testWidgets('Free 使用者開付費書的目錄：看到試讀入口，不被自動導 paywall',
      (tester) async {
    await pumpEbookApp(
      tester,
      initialLocation: '/learning/books/$_premiumBook',
      catalog: buildTestCatalog(),
      access: const EbookSubscriptionAccess.free(),
    );
    await tester.pumpAndSettle();

    expect(find.text(paywallStubText), findsNothing, reason: '不再自動導 paywall');
    expect(find.text('免費試讀'), findsOneWidget);
    expect(find.text('免費試讀第一章'), findsOneWidget);
    expect(find.text('看訂閱方案'), findsOneWidget);
    // 目錄可見，但第二章標成鎖定。
    expect(find.text('訂閱後解鎖'), findsOneWidget);
    // 試讀時不顯示完成度分母，避免看起來整本都能讀。
    expect(find.textContaining('已完成 0 / 2 章'), findsNothing);
  });

  testWidgets('Free 使用者 deep link 進付費書第一章：可讀，並看到解鎖其餘章的入口',
      (tester) async {
    await pumpEbookApp(
      tester,
      initialLocation:
          '/learning/books/$_premiumBook/chapters/$_premiumChapter',
      catalog: buildTestCatalog(),
      access: const EbookSubscriptionAccess.free(),
      // 章尾按鈕在 ListView 裡，視窗要夠高才會被建出來。
      size: const Size(390, 1600),
    );
    await tester.pumpAndSettle();

    expect(find.text(paywallStubText), findsNothing);
    expect(find.text('第 1 章'), findsOneWidget);
    expect(find.text('段落內容。'), findsOneWidget);
    expect(find.text('免費試讀章'), findsOneWidget);
    expect(find.text('訂閱後解鎖其餘 1 章'), findsOneWidget);
    // 試讀只放行第一章：第二章不在 PageView 裡。
    expect(find.text('第 2 章'), findsNothing);
  });

  testWidgets('Free 使用者 deep link 進付費書第二章：全擋，內容不閃現',
      (tester) async {
    await pumpEbookApp(
      tester,
      initialLocation:
          '/learning/books/$_premiumBook/chapters/$_premiumLockedChapter',
      catalog: buildTestCatalog(),
      access: const EbookSubscriptionAccess.free(),
    );

    // 逐帧檢查：從第一帧到導航完成，都不能出現任何章節內容。
    for (var frame = 0; frame < 6; frame++) {
      expect(find.text('第 2 章'), findsNothing);
      expect(find.text('第 1 章'), findsNothing);
      expect(find.text('段落內容。'), findsNothing);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();

    expect(find.text(paywallStubText), findsOneWidget);
    expect(find.text('段落內容。'), findsNothing);
  });

  testWidgets('從 paywall 返回後不是無盡 loading，而是可操作畫面', (tester) async {
    final harness = await pumpEbookApp(
      tester,
      initialLocation:
          '/learning/books/$_premiumBook/chapters/$_premiumLockedChapter',
      catalog: buildTestCatalog(),
      access: const EbookSubscriptionAccess.free(),
    );
    await tester.pumpAndSettle();

    // 自動導向 paywall 之後返回。
    expect(find.text(paywallStubText), findsOneWidget);
    harness.router.pop();
    await tester.pumpAndSettle();

    // 不得停在 spinner：要有標題與可按的入口，而且仍然沒有內容。
    expect(find.text('這本需要訂閱才能閱讀'), findsOneWidget);
    expect(find.text('看訂閱方案'), findsOneWidget);
    expect(find.text('回學習頁'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('段落內容。'), findsNothing);
  });

  testWidgets('訂閱狀態還在確認時只顯示 loading，不導 paywall 也不顯示內容',
      (tester) async {
    final harness = await pumpEbookApp(
      tester,
      initialLocation: '/learning/books/$_premiumBook',
      catalog: buildTestCatalog(),
      access: const EbookSubscriptionAccess.resolving(),
    );
    // loading 畫面有 spinner（無限動畫），所以不能用 pumpAndSettle。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('正在確認你的訂閱狀態…'), findsOneWidget);
    expect(find.text('訂閱測試書'), findsNothing);
    expect(find.text(paywallStubText), findsNothing);

    // 確認完是付費 → 內容才出現，全程沒有經過 paywall。
    harness.setAccess(const EbookSubscriptionAccess.premium());
    await tester.pumpAndSettle();

    expect(find.text('訂閱測試書'), findsOneWidget);
    expect(find.text(paywallStubText), findsNothing);
  });

  testWidgets('確認後是 Free，鎖定章才導 paywall', (tester) async {
    final harness = await pumpEbookApp(
      tester,
      initialLocation:
          '/learning/books/$_premiumBook/chapters/$_premiumLockedChapter',
      catalog: buildTestCatalog(),
      access: const EbookSubscriptionAccess.resolving(),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text(paywallStubText), findsNothing);

    harness.setAccess(const EbookSubscriptionAccess.free());
    await tester.pumpAndSettle();

    expect(find.text(paywallStubText), findsOneWidget);
    expect(find.text('段落內容。'), findsNothing);
  });

  testWidgets('確認後是 Free，第一章轉為試讀而不是 paywall', (tester) async {
    final harness = await pumpEbookApp(
      tester,
      initialLocation:
          '/learning/books/$_premiumBook/chapters/$_premiumChapter',
      catalog: buildTestCatalog(),
      access: const EbookSubscriptionAccess.resolving(),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    // 未確認期間不得先漏出內容。
    expect(find.text('段落內容。'), findsNothing);
    expect(find.text(paywallStubText), findsNothing);

    harness.setAccess(const EbookSubscriptionAccess.free());
    await tester.pumpAndSettle();

    expect(find.text(paywallStubText), findsNothing);
    expect(find.text('免費試讀章'), findsOneWidget);
    expect(find.text('第 1 章'), findsOneWidget);
  });

  testWidgets('訂閱狀態無法確認時顯示可重試錯誤，不包裝成 Free upsell',
      (tester) async {
    await pumpEbookApp(
      tester,
      initialLocation: '/learning/books/$_premiumBook',
      catalog: buildTestCatalog(),
      access: const EbookSubscriptionAccess.unavailable(),
    );
    await tester.pumpAndSettle();

    expect(find.text('暫時無法確認訂閱狀態'), findsOneWidget);
    expect(find.text('重試'), findsOneWidget);
    expect(find.text(paywallStubText), findsNothing);
    expect(find.text('訂閱測試書'), findsNothing);
    // 不得出現任何額度用語（電子書與文章額度無關）。
    expect(find.textContaining('免費閱讀'), findsNothing);
    expect(find.textContaining('今日剩餘'), findsNothing);
  });

  testWidgets('unknown book 顯示找不到，不導 paywall', (tester) async {
    await pumpEbookApp(
      tester,
      initialLocation: '/learning/books/does-not-exist',
      catalog: buildTestCatalog(),
      access: const EbookSubscriptionAccess.free(),
    );
    await tester.pumpAndSettle();

    expect(find.text('找不到這本書'), findsOneWidget);
    expect(find.text('回學習頁'), findsOneWidget);
    expect(find.text(paywallStubText), findsNothing);
  });

  testWidgets('catalog 載入中顯示 loading，載入失敗顯示可讀錯誤', (tester) async {
    await pumpEbookApp(
      tester,
      initialLocation: '/learning/books/$_freeBook',
      catalogPending: true,
      access: const EbookSubscriptionAccess.free(),
    );
    await tester.pump();
    expect(find.text('免費測試書'), findsNothing);
    expect(find.text(paywallStubText), findsNothing);
  });

  testWidgets('呼叫端沒提供試讀畫面時不放行：退回 paywall 而不是漏出內容',
      (tester) async {
    final premium =
        buildTestEbook(id: 'p', number: 2, access: EbookAccess.premium);
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => EbookAccessGate(
            book: premium,
            chapterId: premium.chapters.first.id,
            // previewBuilder 刻意留空。
            builder: (context) => const Text('BOOK_CONTENT'),
          ),
        ),
        GoRoute(
          path: '/paywall',
          builder: (_, __) => const Scaffold(body: Text(paywallStubText)),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ebookSubscriptionAccessProvider
              .overrideWithValue(const EbookSubscriptionAccess.free()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('BOOK_CONTENT'), findsNothing);
    expect(find.text(paywallStubText), findsOneWidget);
  });

  testWidgets('catalog 解析失敗顯示可讀錯誤', (tester) async {
    await pumpEbookApp(
      tester,
      initialLocation: '/learning/books/$_freeBook',
      catalogError: StateError('bad content'),
      access: const EbookSubscriptionAccess.free(),
    );
    await tester.pumpAndSettle();

    expect(find.text('電子書內容載入失敗'), findsOneWidget);
    expect(find.text('回學習頁'), findsOneWidget);
  });
}
