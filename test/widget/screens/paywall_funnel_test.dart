// test/widget/screens/paywall_funnel_test.dart
//
// 付費頁的漏斗事件（Eric 2026-10-18，audit P1-4：量從哪裡打開付費頁、買了哪個方案）。
// - paywall_opened：每開一次一筆，帶入口；路由沒帶入口算一般入口。
// - paywall_purchase_completed：RevenueCat 回成功才記；取消、失敗、例外、逾時、
//   排程降級都不記。
// - 埋點掛住或出錯，付費頁和購買流程都照常。
// - 購買事件只記給發起購買的帳號：確認回來時換了帳號或登出就不記；事件另外帶
//   開始購買時的帳號（purchaser），送出前才換帳號時由伺服器比對擋下。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;
import 'package:vibesync/core/services/funnel_tracker.dart';
import 'package:vibesync/core/services/supabase_service.dart';
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_tier_helper.dart';
import 'package:vibesync/features/subscription/presentation/paywall_entry.dart';
import 'package:vibesync/features/subscription/presentation/screens/paywall_screen.dart';

/// 字典裡 entry 的值（docs/integrations/funnel-events-v1.md）：額度不夠的四種都記
/// quota_exhausted，練習室翻牌撞牆記 practice_draw；加入口要一起補。
const _wireEntry = {
  PaywallEntry.general: 'general',
  PaywallEntry.lockedCards: 'locked_cards',
  PaywallEntry.dailyQuotaUsedUp: 'quota_exhausted',
  PaywallEntry.dailyQuotaShort: 'quota_exhausted',
  PaywallEntry.monthlyQuotaUsedUp: 'quota_exhausted',
  PaywallEntry.monthlyQuotaShort: 'quota_exhausted',
  PaywallEntry.practiceDraw: 'practice_draw',
};

/// 帳號 id 是 UUID（伺服器只收 UUID 的 purchaser）。
const _userA = '8f14e45f-ceea-4c6b-9a8e-3e4d4b5c6a7f';
const _userB = '2b7c1d3e-4f5a-4b6c-8d7e-9f0a1b2c3d4e';

User _fakeUser(String id) => User(
      id: id,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: DateTime.now().toIso8601String(),
    );

/// 目前登入的帳號（null＝沒登入）。
void _signInAs(String? userId) {
  SupabaseService.debugCurrentUserOverride =
      () => userId == null ? null : _fakeUser(userId);
}

class _StubSubscriptionNotifier extends SubscriptionNotifier {
  _StubSubscriptionNotifier({
    this.onPurchase,
    this.onPurchaseStoreProduct,
    this.onRestore,
  });

  final Future<SubscriptionPurchaseResult> Function()? onPurchase;
  final Future<SubscriptionPurchaseResult> Function()? onPurchaseStoreProduct;
  final Future<bool> Function()? onRestore;

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

  @override
  Future<SubscriptionPurchaseResult> purchaseStoreProduct(
    StoreProduct product,
  ) {
    final handler = onPurchaseStoreProduct;
    if (handler == null) {
      fail('purchaseStoreProduct should not be called in this test');
    }
    return handler();
  }

  @override
  Future<bool> restorePurchases() {
    final handler = onRestore;
    if (handler == null) {
      fail('restorePurchases should not be called in this test');
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

/// 漏斗 tracker 一律當作已登入（沒登入會先排隊不送）：這裡測的是付費頁自己對
/// 帳號的檢查，跟 tracker 的排隊無關。
String? _trackerSignedIn() => _userA;

FunnelTracker _recordingTracker(_Sent sent) => FunnelTracker(
      invoker: (fn, {required body}) async {
        sent.events.add(body['event'] as Map<String, dynamic>);
        return 200;
      },
      currentUserId: _trackerSignedIn,
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

/// 只有 App Store 商品、沒有 RevenueCat 套裝（offerings 還沒同步到）：付費頁走
/// purchaseStoreProduct 那條。
SubscriptionState _storeProductOnly(String productId, String title) =>
    SubscriptionState(
      storeProducts: {
        productId: StoreProduct(
          productId,
          'description',
          title,
          590,
          r'$590',
          'TWD',
          subscriptionPeriod: 'P1M',
        ),
      },
    );

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
  Future<SubscriptionPurchaseResult> Function()? onPurchaseStoreProduct,
  Future<bool> Function()? onRestore,
  SubscriptionState? seededState,
  String? signedInAs = _userA,
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  // 方案狀態一建立就會去讀登入帳號；先清掉，畫面與價格都好了再登入。
  SupabaseService.debugResetForTesting();

  final stub = _StubSubscriptionNotifier(
    onPurchase: onPurchase,
    onPurchaseStoreProduct: onPurchaseStoreProduct,
    onRestore: onRestore,
  );
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
    // 免費用戶預設選 Starter 月繳（Onboarding 第 9 步）；種的狀態只有 Essential 有
    // 價格時，下一幀才換到有價格的那一張。
    await tester.pump();
  }
  _signInAs(signedInAs);
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
  // 這裡的方案都是免費：看購買版（Onboarding 第 9 步）。
  expect(find.text('升級方案'), findsOneWidget);
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
  tearDown(SupabaseService.debugResetForTesting);

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
        entry: PaywallEntry.dailyQuotaUsedUp,
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
          currentUserId: _trackerSignedIn,
        ),
        FunnelTracker(
          invoker: (fn, {required body}) async => throw StateError('boom'),
          currentUserId: _trackerSignedIn,
        ),
      ]) {
        await _pumpPaywall(
          tester,
          tracker: tracker,
          entry: PaywallEntry.lockedCards,
        );
        expect(
          find.text(
            PaywallEntry.lockedCards.headlineFor(SubscriptionTierHelper.free),
          ),
          findsOneWidget,
        );
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
        {'tier': 'essential', 'entry': 'locked_cards', 'purchaser': _userA},
      ]);
      // 成功流程照舊：慶祝訊息＋離開付費頁。
      expect(find.textContaining('方案已更新'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('home-root'), findsOneWidget);
      await _flush(tester);
    });

    testWidgets('沒有套裝、直接用 App Store 商品購買：成功一樣記', (tester) async {
      final sent = _Sent();
      var storeProductPurchases = 0;
      await _pumpPaywall(
        tester,
        tracker: _recordingTracker(sent),
        entry: PaywallEntry.lockedCards,
        onPurchaseStoreProduct: () async {
          storeProductPurchases++;
          return _success(SubscriptionTierHelper.essential);
        },
        seededState:
            _storeProductOnly('vibesync_essential_monthly', 'Essential'),
      );

      await _tapSubscribe(tester, '訂閱 Essential');

      expect(storeProductPurchases, 1, reason: '走的是 purchaseStoreProduct 那條');
      expect(sent.propsOf('paywall_purchase_completed'), [
        {'tier': 'essential', 'entry': 'locked_cards', 'purchaser': _userA},
      ]);
      await _flush(tester);
    });

    testWidgets('恢復購買成功：不記 paywall_purchase_completed', (tester) async {
      final sent = _Sent();
      var restores = 0;
      await _pumpPaywall(
        tester,
        tracker: _recordingTracker(sent),
        entry: PaywallEntry.lockedCards,
        onRestore: () async {
          restores++;
          return true;
        },
        seededState: _stateWith('vibesync_essential_monthly', 'Essential'),
      );

      final restoreLink = find.widgetWithText(TextButton, '恢復購買');
      await tester.ensureVisible(restoreLink);
      await tester.pump();
      await tester.tap(restoreLink, warnIfMissed: false);
      await tester.pump();
      // 確認框的按鈕跟頁尾連結同字，確認框在最上層，取最後一個。
      await tester.tap(
        find.widgetWithText(TextButton, '恢復購買').last,
        warnIfMissed: false,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(restores, 1);
      expect(find.text('訂閱狀態已更新。'), findsOneWidget);
      expect(sent.names, ['paywall_opened']);
      await _flush(tester);
    });

    testWidgets('買 Starter：tier 記 starter', (tester) async {
      final sent = _Sent();
      await _pumpPaywall(
        tester,
        tracker: _recordingTracker(sent),
        entry: PaywallEntry.monthlyQuotaShort,
        onPurchase: () async => _success(SubscriptionTierHelper.starter),
        // 免費用戶預設就是 Starter 月繳。
        seededState: _stateWith('vibesync_starter_monthly', 'Starter'),
      );
      await tester.pump();

      await _tapSubscribe(tester, '訂閱 Starter');

      expect(sent.propsOf('paywall_purchase_completed'), [
        {'tier': 'starter', 'entry': 'quota_exhausted', 'purchaser': _userA},
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
        entry: PaywallEntry.dailyQuotaShort,
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
        {'tier': 'essential', 'entry': 'quota_exhausted', 'purchaser': _userA},
      ]);
      expect(tester.takeException(), isNull);
      await _flush(tester);
    });

    // 付款確認要等一陣子，這段時間可能登出、換帳號；送事件用的是當下的登入，
    // 換了就不記，免得 A 買的算到 B（主審 r1 P2）。
    final accountChanges = <String, String?>{
      '換成別的帳號': _userB,
      '登出': null,
    };
    for (final change in accountChanges.entries) {
      testWidgets('付款確認回來前關掉付費頁並${change.key}：不記', (tester) async {
        final sent = _Sent();
        final pending = Completer<SubscriptionPurchaseResult>();
        await _pumpPaywall(
          tester,
          tracker: _recordingTracker(sent),
          entry: PaywallEntry.lockedCards,
          onPurchase: () => pending.future,
          seededState: _stateWith('vibesync_essential_monthly', 'Essential'),
        );

        await _tapSubscribe(tester, '訂閱 Essential');
        await tester.tap(find.byIcon(Icons.close));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        _signInAs(change.value);

        pending.complete(_success(SubscriptionTierHelper.essential));
        await tester.pump();
        await tester.pump();

        expect(sent.propsOf('paywall_purchase_completed'), isEmpty);
        expect(sent.names, ['paywall_opened']);
        expect(tester.takeException(), isNull);
        await _flush(tester);
      });
    }

    // 主審 r2 P2：認證權杖是送出當下才取（functions_client 先等 JSON 編碼，
    // AuthHttpClient.send 才拿權杖），付費頁的檢查擋不住「檢查過了才換帳號」。
    // 事件帶開始購買時的帳號，伺服器發現跟登入的不同就整筆丟掉。
    testWidgets('檢查之後、送出前才換帳號：事件仍帶開始購買時的帳號', (tester) async {
      final sent = _Sent();
      final signedInAtSend = <String?>[];
      await _pumpPaywall(
        tester,
        tracker: FunnelTracker(
          invoker: (fn, {required body}) async {
            final event = body['event'] as Map<String, dynamic>;
            if (event['event'] == 'paywall_purchase_completed') {
              // 傳輸層拿權杖之前換成 B。
              _signInAs(_userB);
            }
            signedInAtSend.add(SupabaseService.currentUser?.id);
            sent.events.add(event);
            return 200;
          },
          currentUserId: _trackerSignedIn,
        ),
        entry: PaywallEntry.lockedCards,
        onPurchase: () async => _success(SubscriptionTierHelper.essential),
        seededState: _stateWith('vibesync_essential_monthly', 'Essential'),
      );

      await _tapSubscribe(tester, '訂閱 Essential');

      expect(sent.propsOf('paywall_purchase_completed'), [
        {'tier': 'essential', 'entry': 'locked_cards', 'purchaser': _userA},
      ]);
      // 送出時已經是 B 的登入：伺服器拿 purchaser 比對，這筆整筆拒絕。
      expect(signedInAtSend.last, _userB);
      await _flush(tester);
    });

    testWidgets('沒登入就開始的購買：不記（沒有帳號可以算）', (tester) async {
      final sent = _Sent();
      await _pumpPaywall(
        tester,
        tracker: _recordingTracker(sent),
        entry: PaywallEntry.general,
        onPurchase: () async => _success(SubscriptionTierHelper.essential),
        seededState: _stateWith('vibesync_essential_monthly', 'Essential'),
        signedInAs: null,
      );

      await _tapSubscribe(tester, '訂閱 Essential');

      expect(find.textContaining('方案已更新'), findsOneWidget);
      expect(sent.propsOf('paywall_purchase_completed'), isEmpty);
      await _flush(tester);
    });

    testWidgets('埋點掛住或出錯：購買成功照樣慶祝並離開付費頁', (tester) async {
      for (final tracker in [
        FunnelTracker(
          invoker: (fn, {required body}) => Completer<int>().future,
          currentUserId: _trackerSignedIn,
        ),
        FunnelTracker(
          invoker: (fn, {required body}) async => throw StateError('boom'),
          currentUserId: _trackerSignedIn,
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
