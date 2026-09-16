import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vibesync/features/learning/presentation/widgets/ebook_access_gate.dart';
import 'package:vibesync/features/night_market/presentation/widgets/night_market_entry_card.dart';

import '../../../helpers/night_market_paywall_harness.dart';

Future<NightMarketPaywallHarness> _pump(
  WidgetTester tester, {
  EbookSubscriptionAccess access = const EbookSubscriptionAccess.essential(),
  bool forceSyncTierShouldFail = false,
  bool revenueCatRecoveryConfirmsEssential = false,
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
      expect(find.text('查看復盤'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
