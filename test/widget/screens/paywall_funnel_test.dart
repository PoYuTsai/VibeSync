// test/widget/screens/paywall_funnel_test.dart
//
// 付費頁的漏斗事件（Eric 2026-10-18，audit P1-4：量從哪裡打開付費頁、買了哪個方案）。
// - paywall_opened：每開一次一筆，帶入口；路由沒帶入口算一般入口。
// - paywall_purchase_completed：RevenueCat 回成功才記；取消、失敗、例外、逾時、
//   排程降級都不記。
// - 埋點掛住或出錯，付費頁和購買流程都照常。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:vibesync/core/services/funnel_tracker.dart';
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_tier_helper.dart';
import 'package:vibesync/features/subscription/presentation/paywall_entry.dart';
import 'package:vibesync/features/subscription/presentation/screens/paywall_screen.dart';

/// 字典裡 entry 的值（docs/integrations/funnel-events-v1.md）；加入口要一起補。
const _wireEntry = {
  PaywallEntry.general: 'general',
  PaywallEntry.lockedCards: 'locked_cards',
  PaywallEntry.quotaExhausted: 'quota_exhausted',
};

class _StubSubscriptionNotifier extends SubscriptionNotifier {
  _StubSubscriptionNotifier({this.onPurchase});

  final Future<SubscriptionPurchaseResult> Function()? onPurchase;

  void seedState(SubscriptionState value) => state = value;

  @override
  Future<void> refresh() async {}

  @override
  Future<SubscriptionPurchaseResult> purchase(Package package) {
    final handler = onPurchase;
    if (handler == null) {
      fail('purchase should not be called in this test');
    }
    return handler();
  }
}

/// 送出去的事件（照順序）。
class _Sent {
  final events = <Map<String, dynamic>>[];

  List<String> get names => [for (final e in events) e['event'] as String];

  List<Object?> propsOf(String name) => [
        for (final e in events)
          if (e['event'] == name) e['properties'],
      ];
}

FunnelTracker _recordingTracker(_Sent sent) => FunnelTracker(
      invoker: (fn, {required body}) async {
        sent.events.add(body['event'] as Map<String, dynamic>);
        return 200;
      },
    );

SubscriptionState _stateWith(String productId, String title) {
  final package = Package(
    r'$rc_monthly',
    PackageType.monthly,
    StoreProduct(
      productId,
      'description',
      title,
      590,
      r'$590',
      'TWD',
      subscriptionPeriod: 'P1M',
    ),
    const PresentedOfferingContext('default', null, null),
  );
  final offering = Offering('default', 'Default offering', const {}, [package]);
  return SubscriptionState(
    offerings: Offerings({'default': offering}, current: offering),
  );
}

SubscriptionPurchaseResult _success(String tier) => SubscriptionPurchaseResult(
      success: true,
      cancelled: false,
      isDeferredDowngrade: false,
      requestedTier: tier,
      previousTier: SubscriptionTierHelper.free,
      activeTier: tier,
    );

/// 從首頁推進付費頁（跟正式路由一樣：入口放 extra，沒帶算一般入口）。
Future<(GoRouter, _StubSubscriptionNotifier)> _pumpPaywall(
  WidgetTester tester, {
  required FunnelTracker tracker,
  PaywallEntry? entry,
  Future<SubscriptionPurchaseResult> Function()? onPurchase,
  SubscriptionState? seededState,
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final stub = _StubSubscriptionNotifier(onPurchase: onPurchase);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const Scaffold(body: Text('home-root')),
        routes: [
          GoRoute(
            path: 'paywall',
            builder: (_, state) => PaywallScreen(
              entry: PaywallEntry.fromRouteExtra(state.extra),
            ),
          ),
        ],
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      // 同一個測試裡重開時要整棵換掉，付費頁才會重新 initState。
      key: UniqueKey(),
      overrides: [
        subscriptionProvider.overrideWith((ref) => stub),
        subscriptionScreenRefreshProvider.overrideWithValue(() async {}),
        funnelTrackerProvider.overrideWithValue(tracker),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
  await _openPaywall(tester, router, entry);
  if (seededState != null) {
    stub.seedState(seededState);
    await tester.pump();
  }
  return (router, stub);
}

Future<void> _openPaywall(
  WidgetTester tester,
  GoRouter router,
  PaywallEntry? entry,
) async {
  unawaited(router.push('/paywall', extra: entry));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  expect(find.text('方案與額度'), findsOneWidget);
}

Future<void> _tapSubscribe(WidgetTester tester, String label) async {
  final cta = find.textContaining(label);
  expect(cta, findsOneWidget);
  await tester.ensureVisible(cta);
  await tester.pump();
  await tester.tap(cta, warnIfMissed: false);
  await tester.pump();
  await tester.pump();
}

/// 跑完 snackbar 與轉場的計時器，測試結束時不留 timer。
Future<void> _flush(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 7));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  group('paywall_opened', () {
    testWidgets('每個入口打開各記一筆，只帶 entry', (tester) async {
      for (final entry in PaywallEntry.values) {
        final sent = _Sent();
        await _pumpPaywall(
          tester,
          tracker: _recordingTracker(sent),
          entry: entry,
        );

        expect(sent.names, ['paywall_opened'], reason: '$entry');
        expect(sent.propsOf('paywall_opened'), [
          {'entry': _wireEntry[entry]},
        ]);
      }
    });

    testWidgets('路由沒帶入口：記成一般入口', (tester) async {
      final sent = _Sent();
      await _pumpPaywall(tester, tracker: _recordingTracker(sent));

      expect(sent.propsOf('paywall_opened'), [
        {'entry': 'general'},
      ]);
    });

    testWidgets('同一次打開，畫面重畫不再記；關掉再開才是第二筆', (tester) async {
      final sent = _Sent();
      final (router, stub) = await _pumpPaywall(
        tester,
        tracker: _recordingTracker(sent),
        entry: PaywallEntry.quotaExhausted,
      );

      // 方案價格同步回來會重畫整頁。
      stub.seedState(
        _stateWith('vibesync_essential_monthly', 'Essential'),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(sent.names, ['paywall_opened']);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('home-root'), findsOneWidget);

      await _openPaywall(tester, router, PaywallEntry.lockedCards);
      expect(sent.propsOf('paywall_opened'), [
        {'entry': 'quota_exhausted'},
        {'entry': 'locked_cards'},
      ]);
    });

    testWidgets('埋點掛住或出錯：付費頁照常打開', (tester) async {
      for (final tracker in [
        FunnelTracker(
          invoker: (fn, {required body}) => Completer<int>().future,
        ),
        FunnelTracker(
          invoker: (fn, {required body}) async => throw StateError('boom'),
        ),
      ]) {
        await _pumpPaywall(
          tester,
          tracker: tracker,
          entry: PaywallEntry.lockedCards,
        );
        expect(find.text(PaywallEntry.lockedCards.headline), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('paywall_purchase_completed', () {
    testWidgets('RevenueCat 回成功：記一筆，只帶買的方案與入口', (tester) async {
      final sent = _Sent();
      await _pumpPaywall(
        tester,
        tracker: _recordingTracker(sent),
        entry: PaywallEntry.lockedCards,
        onPurchase: () async => _success(SubscriptionTierHelper.essential),
        seededState: _stateWith('vibesync_essential_monthly', 'Essential'),
      );

      await _tapSubscribe(tester, '訂閱 Essential');

      expect(sent.names, ['paywall_opened', 'paywall_purchase_completed']);
      expect(sent.propsOf('paywall_purchase_completed'), [
        {'tier': 'essential', 'entry': 'locked_cards'},
      ]);
      // 成功流程照舊：慶祝訊息＋離開付費頁。
      expect(find.textContaining('方案已更新'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('home-root'), findsOneWidget);
      await _flush(tester);
    });

    testWidgets('買 Starter：tier 記 starter', (tester) async {
      final sent = _Sent();
      await _pumpPaywall(
        tester,
        tracker: _recordingTracker(sent),
        entry: PaywallEntry.quotaExhausted,
        onPurchase: () async => _success(SubscriptionTierHelper.starter),
        // 只有 Starter 有價格時，預設選取會換到 Starter。
        seededState: _stateWith('vibesync_starter_monthly', 'Starter'),
      );
      await tester.pump();

      await _tapSubscribe(tester, '訂閱 Starter');

      expect(sent.propsOf('paywall_purchase_completed'), [
        {'tier': 'starter', 'entry': 'quota_exhausted'},
      ]);
      await _flush(tester);
    });

    final noEvent = <String, Future<SubscriptionPurchaseResult> Function()>{
      '取消付款': () async => const SubscriptionPurchaseResult(
            success: false,
            cancelled: true,
            isDeferredDowngrade: false,
            requestedTier: SubscriptionTierHelper.essential,
            previousTier: SubscriptionTierHelper.free,
            activeTier: SubscriptionTierHelper.free,
            errorCode: PurchasesErrorCode.purchaseCancelledError,
          ),
      '付款失敗': () async => const SubscriptionPurchaseResult(
            success: false,
            cancelled: false,
            isDeferredDowngrade: false,
            requestedTier: SubscriptionTierHelper.essential,
            previousTier: SubscriptionTierHelper.free,
            activeTier: SubscriptionTierHelper.free,
            errorCode: PurchasesErrorCode.storeProblemError,
          ),
      '購買丟例外': () async => throw StateError('purchase boom'),
      // 降級排到下次續訂：當下沒有新方案生效，不算買到（Eric 決定前的預設）。
      '排程降級': () async => SubscriptionPurchaseResult(
            success: true,
            cancelled: false,
            isDeferredDowngrade: true,
            requestedTier: SubscriptionTierHelper.starter,
            previousTier: SubscriptionTierHelper.essential,
            activeTier: SubscriptionTierHelper.essential,
            effectiveAt: DateTime(2027, 1, 1),
          ),
    };
    for (final scenario in noEvent.entries) {
      testWidgets('${scenario.key}：不記 paywall_purchase_completed',
          (tester) async {
        final sent = _Sent();
        await _pumpPaywall(
          tester,
          tracker: _recordingTracker(sent),
          entry: PaywallEntry.lockedCards,
          onPurchase: scenario.value,
          seededState: _stateWith('vibesync_essential_monthly', 'Essential'),
        );

        await _tapSubscribe(tester, '訂閱 Essential');
        await tester.pump(const Duration(seconds: 1));

        expect(sent.propsOf('paywall_purchase_completed'), isEmpty);
        expect(sent.names, ['paywall_opened']);
        await _flush(tester);
      });
    }

    testWidgets('App Store 確認逾時：不記', (tester) async {
      final sent = _Sent();
      await _pumpPaywall(
        tester,
        tracker: _recordingTracker(sent),
        entry: PaywallEntry.general,
        onPurchase: () => Completer<SubscriptionPurchaseResult>().future,
        seededState: _stateWith('vibesync_essential_monthly', 'Essential'),
      );

      await _tapSubscribe(tester, '訂閱 Essential');
      await tester.pump(const Duration(seconds: 46));
      await tester.pump();

      expect(find.textContaining('付款確認逾時'), findsOneWidget);
      expect(sent.names, ['paywall_opened']);
      await _flush(tester);
    });

    testWidgets('付款確認回來前已關掉付費頁：成功照樣記', (tester) async {
      final sent = _Sent();
      final pending = Completer<SubscriptionPurchaseResult>();
      await _pumpPaywall(
        tester,
        tracker: _recordingTracker(sent),
        entry: PaywallEntry.quotaExhausted,
        onPurchase: () => pending.future,
        seededState: _stateWith('vibesync_essential_monthly', 'Essential'),
      );

      await _tapSubscribe(tester, '訂閱 Essential');
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('home-root'), findsOneWidget);

      pending.complete(_success(SubscriptionTierHelper.essential));
      await tester.pump();
      await tester.pump();

      expect(sent.propsOf('paywall_purchase_completed'), [
        {'tier': 'essential', 'entry': 'quota_exhausted'},
      ]);
      expect(tester.takeException(), isNull);
      await _flush(tester);
    });

    testWidgets('埋點掛住或出錯：購買成功照樣慶祝並離開付費頁', (tester) async {
      for (final tracker in [
        FunnelTracker(
          invoker: (fn, {required body}) => Completer<int>().future,
        ),
        FunnelTracker(
          invoker: (fn, {required body}) async => throw StateError('boom'),
        ),
      ]) {
        await _pumpPaywall(
          tester,
          tracker: tracker,
          entry: PaywallEntry.lockedCards,
          onPurchase: () async => _success(SubscriptionTierHelper.essential),
          seededState: _stateWith('vibesync_essential_monthly', 'Essential'),
        );

        await _tapSubscribe(tester, '訂閱 Essential');

        expect(find.textContaining('方案已更新'), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.text('home-root'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _flush(tester);
      }
    });
  });
}
