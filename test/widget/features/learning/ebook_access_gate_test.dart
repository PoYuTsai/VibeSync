// test/widget/features/learning/ebook_access_gate_test.dart
//
// 付費閘門：Free 看不到 Books 2–4、loading 不 render premium child、
// 訂閱錯誤顯示可重試錯誤而不是假裝 Free upsell、unknown book 不導 paywall、
// 直接 deep link 進付費章節也不會閃出內容。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/learning/domain/models/ebook.dart';
import 'package:vibesync/features/learning/presentation/widgets/ebook_access_gate.dart';

import '../../../helpers/ebook_test_content.dart';
import '../../../helpers/ebook_widget_harness.dart';

const _freeBook = 'test-book-free';
const _premiumBook = 'test-book-premium';
const _premiumChapter = 'test-book-premium-chapter-1';

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

    test('已快取 premium 時優先放行（刻意的既有 entitlement 姿態）', () {
      // App 啟動時 SubscriptionState 會先帶本機快取 tier 且 isLoading=true，
      // 付費使用者不該先看到 loading 或降級。代價是 entitlement 已失效但本機
      // 仍快取 premium 者，在刷新完成前還能開啟——這是刻意接受的既有行為，
      // 且 tier 解析成 free 後閘門會重算成 locked。
      const premiumWhileResolving = EbookSubscriptionAccess(
        isPremium: true,
        isResolving: true,
        hasError: false,
      );
      const premiumWhileError = EbookSubscriptionAccess(
        isPremium: true,
        isResolving: false,
        hasError: true,
      );
      expect(
        ebookAccessFor(premium, premiumWhileResolving),
        EbookAccessDecision.allowed,
      );
      expect(
        ebookAccessFor(premium, premiumWhileError),
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
        isResolving: false,
        hasError: false,
      );
      expect(
        ebookAccessFor(premium, starterOrEssential),
        EbookAccessDecision.allowed,
      );
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

  testWidgets('Free 使用者開付費書會被導到 paywall，且不顯示內容', (tester) async {
    await pumpEbookApp(
      tester,
      initialLocation: '/learning/books/$_premiumBook',
      catalog: buildTestCatalog(),
      access: const EbookSubscriptionAccess.free(),
    );
    await tester.pumpAndSettle();

    expect(find.text(paywallStubText), findsOneWidget);
    expect(find.text('訂閱測試書'), findsNothing);
  });

  testWidgets('直接 deep link 進付費章節也會被擋下，內容不閃現', (tester) async {
    await pumpEbookApp(
      tester,
      initialLocation:
          '/learning/books/$_premiumBook/chapters/$_premiumChapter',
      catalog: buildTestCatalog(),
      access: const EbookSubscriptionAccess.free(),
    );

    // 逐帧檢查：從第一帧到導航完成，都不能出現章節內容。
    for (var frame = 0; frame < 6; frame++) {
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
      initialLocation: '/learning/books/$_premiumBook',
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
    expect(find.text('訂閱測試書'), findsNothing);
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

  testWidgets('確認後是 Free 才導 paywall', (tester) async {
    final harness = await pumpEbookApp(
      tester,
      initialLocation: '/learning/books/$_premiumBook',
      catalog: buildTestCatalog(),
      access: const EbookSubscriptionAccess.resolving(),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text(paywallStubText), findsNothing);

    harness.setAccess(const EbookSubscriptionAccess.free());
    await tester.pumpAndSettle();

    expect(find.text(paywallStubText), findsOneWidget);
    expect(find.text('訂閱測試書'), findsNothing);
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
