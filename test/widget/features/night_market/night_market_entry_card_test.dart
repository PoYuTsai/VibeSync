import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vibesync/features/learning/presentation/widgets/ebook_access_gate.dart';
import 'package:vibesync/features/night_market/presentation/night_market_watch_gate.dart';
import 'package:vibesync/features/night_market/presentation/widgets/night_market_entry_card.dart';

import '../../../helpers/night_market_paywall_harness.dart';

Future<NightMarketPaywallHarness> _pump(
  WidgetTester tester, {
  EbookSubscriptionAccess access = const EbookSubscriptionAccess.essential(),
  bool forceSyncTierShouldFail = false,
  bool revenueCatRecoveryConfirmsEssential = false,
  bool alreadyWatched = true,
}) {
  return pumpNightMarketPaywallHarness(
    tester,
    builder: (_, __) => const Scaffold(body: NightMarketEntryCard()),
    extraRoutes: [
      GoRoute(
        path: '/practice-night-market',
        builder: (_, __) => const Scaffold(body: Text('night-market-page')),
      ),
    ],
    access: access,
    forceSyncTierShouldFail: forceSyncTierShouldFail,
    revenueCatRecoveryConfirmsEssential: revenueCatRecoveryConfirmsEssential,
    alreadyWatched: alreadyWatched,
  );
}

void main() {
  testWidgets('entry card navigates to the independent night market route',
      (tester) async {
    await _pump(tester);
    expect(find.text('簡易搭訕流程詳解'), findsOneWidget);
    expect(find.text('夜市實戰版：從注意到她到加聯繫方式'), findsOneWidget);
    expect(find.textContaining('2 個選擇'), findsNothing);
    expect(find.text('查看復盤'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('night-market-entry-card')));
    await tester.pumpAndSettle();
    expect(find.text('night-market-page'), findsOneWidget);
  });

  testWidgets(
      'Essential: review entry opens without playback and can return or restart',
      (tester) async {
    final harness = await _pump(tester);
    await tester.tap(find.text('查看復盤'));
    await tester.pumpAndSettle();
    expect(find.text('復盤'), findsOneWidget);
    expect(find.text('帶著確信，走過去'), findsOneWidget);
    expect(find.text('night-market-page'), findsNothing);

    await tester.tap(find.byTooltip('回練習室'));
    await tester.pumpAndSettle();
    expect(find.text('查看復盤'), findsOneWidget);
    await tester.tap(find.text('查看復盤'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('再練一次'));
    await tester.tap(find.text('再練一次'));
    await tester.pumpAndSettle();
    expect(find.text('night-market-page'), findsOneWidget);
    harness.router.pop();
    await tester.pumpAndSettle();
    expect(find.text('查看復盤'), findsOneWidget);
    expect(find.text('復盤'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  group('復盤要先看完影片（Eric 2026-10-28）', () {
    testWidgets('沒看完：按鈕寫「看完影片解鎖復盤」，點了只提示，不開復盤也不開付費牆', (tester) async {
      await _pump(tester, alreadyWatched: false);
      expect(find.text(NightMarketEntryCard.lockedReviewLabel), findsOneWidget);
      expect(find.text(NightMarketEntryCard.reviewLabel), findsNothing);

      await tester.tap(find.byKey(const ValueKey('night-market-review-entry')));
      await tester.pump();

      expect(find.text(NightMarketEntryCard.watchFirstNotice), findsOneWidget);
      expect(find.text('復盤'), findsNothing);
      expect(find.text(paywallStubText), findsNothing);
    });

    testWidgets('沒看完的免費帳號也只提示先看影片，不直接開付費牆', (tester) async {
      await _pump(
        tester,
        access: const EbookSubscriptionAccess.free(),
        alreadyWatched: false,
      );
      await tester.tap(find.byKey(const ValueKey('night-market-review-entry')));
      await tester.pump();

      expect(find.text(NightMarketEntryCard.watchFirstNotice), findsOneWidget);
      expect(find.text(paywallStubText), findsNothing);
    });

    testWidgets('提示上的「去看影片」直接進影片', (tester) async {
      await _pump(tester, alreadyWatched: false);
      await tester.tap(find.byKey(const ValueKey('night-market-review-entry')));
      // 等提示滑進來，按鈕才點得到。
      await tester.pumpAndSettle();

      await tester.tap(find.text('去看影片'));
      await tester.pumpAndSettle();
      expect(find.text('night-market-page'), findsOneWidget);
    });

    testWidgets('看完的紀錄綁帳號：換成沒看過的帳號就鎖回去', (tester) async {
      final harness = await _pump(tester);
      expect(find.text(NightMarketEntryCard.reviewLabel), findsOneWidget);

      harness.switchAccount('another-owner');
      await tester.pumpAndSettle();
      expect(find.text(NightMarketEntryCard.lockedReviewLabel), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('night-market-review-entry')));
      await tester.pump();
      expect(find.text(NightMarketEntryCard.watchFirstNotice), findsOneWidget);
      expect(find.text('復盤'), findsNothing);
    });

    testWidgets('看完之後就照原本的 Essential 門檻打開復盤', (tester) async {
      final harness = await _pump(tester, alreadyWatched: false);
      await harness.watchStore.markWatched('harness-owner');
      harness.container.invalidate(nightMarketWatchedProvider);
      await tester.pumpAndSettle();
      expect(find.text(NightMarketEntryCard.reviewLabel), findsOneWidget);

      await tester.tap(find.text(NightMarketEntryCard.reviewLabel));
      await tester.pumpAndSettle();
      expect(find.text('復盤'), findsOneWidget);
    });
  });

  group('review entry paywall (Free/Starter)', () {
    testWidgets('opens the paywall instead of the recap', (tester) async {
      await _pump(tester, access: const EbookSubscriptionAccess.free());
      await tester.tap(find.text('查看復盤'));
      await tester.pumpAndSettle();
      expect(find.text(paywallStubText), findsOneWidget);
      expect(find.text('復盤'), findsNothing);
    });

    testWidgets('cancel leaves the entry card with no restricted content',
        (tester) async {
      await _pump(tester, access: const EbookSubscriptionAccess.free());
      await tester.tap(find.text('查看復盤'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('paywall-cancel')));
      await tester.pumpAndSettle();
      expect(find.text('查看復盤'), findsOneWidget);
      expect(find.text('復盤'), findsNothing);
    });

    testWidgets('double tap opens only one paywall', (tester) async {
      await _pump(tester, access: const EbookSubscriptionAccess.free());
      await tester.tap(find.text('查看復盤'));
      await tester.tap(find.text('查看復盤'));
      await tester.pumpAndSettle();
      expect(find.text(paywallStubText), findsOneWidget);
    });

    testWidgets('Starter also opens the paywall', (tester) async {
      await _pump(tester, access: const EbookSubscriptionAccess.premium());
      await tester.tap(find.text('查看復盤'));
      await tester.pumpAndSettle();
      expect(find.text(paywallStubText), findsOneWidget);
    });

    testWidgets('resolving shows a neutral notice, never a paywall',
        (tester) async {
      await _pump(tester, access: const EbookSubscriptionAccess.resolving());
      await tester.tap(find.text('查看復盤'));
      await tester.pump();
      expect(find.text(paywallStubText), findsNothing);
      expect(find.text('正在確認你的訂閱狀態，請稍後再點一次'), findsOneWidget);
    });

    testWidgets('unavailable shows a retry notice, never a paywall',
        (tester) async {
      await _pump(tester, access: const EbookSubscriptionAccess.unavailable());
      await tester.tap(find.text('查看復盤'));
      await tester.pump();
      expect(find.text(paywallStubText), findsNothing);
      expect(find.text('暫時無法確認訂閱狀態'), findsOneWidget);
    });
  });

  group('review entry unlock consistency', () {
    testWidgets('buying Essential goes straight into the recap, not S1 playback',
        (tester) async {
      await _pump(tester, access: const EbookSubscriptionAccess.free());
      await tester.tap(find.text('查看復盤'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('paywall-buy-essential')));
      await tester.pumpAndSettle();
      expect(find.text('復盤'), findsOneWidget);
      expect(find.text('night-market-page'), findsNothing);
    });

    testWidgets('buying Starter only stays on the entry card, no recap',
        (tester) async {
      await _pump(tester, access: const EbookSubscriptionAccess.free());
      await tester.tap(find.text('查看復盤'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('paywall-buy-starter')));
      await tester.pumpAndSettle();
      expect(find.text('復盤'), findsNothing);
      expect(find.text('查看復盤'), findsOneWidget);
    });

    testWidgets(
        'sync failure but RevenueCat confirms the purchase: unlocks and '
        'persists, not just this one attempt', (tester) async {
      final harness = await _pump(
        tester,
        access: const EbookSubscriptionAccess.free(),
        forceSyncTierShouldFail: true,
        revenueCatRecoveryConfirmsEssential: true,
      );
      await tester.tap(find.text('查看復盤'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('paywall-buy-essential-sync-lag')),
      );
      await tester.pumpAndSettle();
      expect(harness.notifier.forceSyncTierCalls, 1);
      expect(harness.notifier.adoptRevenueCatTierIfHigherCalls, 1);
      expect(find.text('復盤'), findsOneWidget);

      await tester.tap(find.byTooltip('回練習室'));
      await tester.pumpAndSettle();
      // Recovery persisted into the real subscription state: the very next
      // independent attempt must go straight into the recap, not the paywall.
      await tester.tap(find.text('查看復盤'));
      await tester.pumpAndSettle();
      expect(find.text(paywallStubText), findsNothing);
      expect(find.text('復盤'), findsOneWidget);
    });

    testWidgets(
        'sync failure and RevenueCat also cannot confirm it: stays locked, '
        'no standing bypass from the popped string alone', (tester) async {
      final harness = await _pump(
        tester,
        access: const EbookSubscriptionAccess.free(),
        forceSyncTierShouldFail: true,
      );
      await tester.tap(find.text('查看復盤'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('paywall-buy-essential-sync-lag')),
      );
      await tester.pumpAndSettle();
      expect(harness.notifier.forceSyncTierCalls, 1);
      expect(harness.notifier.adoptRevenueCatTierIfHigherCalls, 1);
      expect(find.text('復盤'), findsNothing);
      expect(find.text('查看復盤'), findsOneWidget);
    });

    testWidgets(
        'account switch while the paywall is open does not apply the stale result',
        (tester) async {
      final harness =
          await _pump(tester, access: const EbookSubscriptionAccess.free());
      await tester.tap(find.text('查看復盤'));
      await tester.pumpAndSettle();
      harness.switchAccount('a-different-user');
      // Let the real StreamProvider actually deliver the new account id
      // before continuing, same as a genuine auth-state event would.
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('paywall-buy-essential')));
      await tester.pumpAndSettle();
      expect(find.text('復盤'), findsNothing);
      // 換成的帳號沒看完過影片，回到卡片時按鈕鎖回去（Eric 2026-10-28）。
      expect(find.text(NightMarketEntryCard.lockedReviewLabel), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
