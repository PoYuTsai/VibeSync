// test/helpers/night_market_paywall_harness.dart
//
// 夜市付費牆情境共用鷹架：可變訂閱切片、真的走 StreamProvider 契約的可控帳號
// 來源（模擬中途切換帳號時走的是正式 reactive 路徑，不是側門直接改值）、一個
// 含 /paywall stub 的 GoRouter，以及可控制 forceSyncTier／refresh 是否失敗、
// 可暫停 forceSyncTier 完成時機的假 SubscriptionNotifier。
// night_market_screen_test 與 night_market_entry_card_test 共用同一份，避免
// 各自重寫一次可能各自漏檢查的鷹架（root-cause fix，2026-09-17；跨模型
// review R1 後改用真的 stream 契約，2026-09-17）。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vibesync/features/night_market/presentation/night_market_essential_gate.dart';
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_tier_helper.dart';

const paywallStubText = 'PAYWALL_STUB';

final testNightMarketAccessProvider = StateProvider<EbookSubscriptionAccess>(
  (ref) => const EbookSubscriptionAccess.essential(),
);

Stream<String?> _accountStream(String? initial, Stream<String?> changes) async* {
  yield initial;
  yield* changes;
}

/// Stands in for the real notifier so tests never touch Supabase/RevenueCat.
/// - [forceSyncTierShouldFail] simulates "purchase succeeded but the server
///   sync call failed".
/// - [forceSyncTierGate], when set, makes `forceSyncTier` await it before
///   returning — lets a test pause mid-round-trip to exercise reentrancy
///   (R4: "paywall already returned, provider already flipped allowed, but
///   the whole operation hasn't finished").
/// - [onAdoptRevenueCatTierIfHigher] stands in for what the real method does
///   (ask RevenueCat's local cache and persist the result into real state)
///   so tests can prove night market calls *this* recovery path — never the
///   old, reviewer-flagged `syncWithRevenueCat` — and can tell "recovery
///   confirms the purchase" apart from "recovery also can't confirm it".
class FakeSubscriptionNotifier extends SubscriptionNotifier {
  FakeSubscriptionNotifier(
    SubscriptionState seed, {
    this.forceSyncTierShouldFail = false,
    this.onAdoptRevenueCatTierIfHigher,
  }) {
    state = seed;
  }

  final bool forceSyncTierShouldFail;
  // Not `final`: a test can flip this between two taps to simulate "the
  // subscription resolved independently between one retry and the next"
  // (review round 3, requirement 四.4 — confirmation retry must not reopen
  // the store paywall).
  VoidCallback? onAdoptRevenueCatTierIfHigher;
  Completer<void>? forceSyncTierGate;
  int forceSyncTierCalls = 0;
  int refreshCalls = 0;
  int adoptRevenueCatTierIfHigherCalls = 0;
  int syncWithRevenueCatCalls = 0;

  @override
  Future<void> forceSyncTier(String tier) async {
    forceSyncTierCalls++;
    if (forceSyncTierGate != null) await forceSyncTierGate!.future;
    if (forceSyncTierShouldFail) {
      throw Exception('sync failed (test)');
    }
  }

  @override
  Future<void> refresh() async {
    refreshCalls++;
  }

  @override
  Future<bool> adoptRevenueCatTierIfHigher() async {
    // The base constructor's own `_initialize()` fire-and-forgets a call to
    // `syncWithRevenueCat` before any test interaction happens (it no-ops
    // for real, since SupabaseService.currentUser is null in tests). Only
    // react to *this* method once a real paywall round trip has actually
    // called forceSyncTier, otherwise a leftover call could prematurely
    // flip access before the scenario under test even starts.
    if (forceSyncTierCalls == 0) return false;
    adoptRevenueCatTierIfHigherCalls++;
    onAdoptRevenueCatTierIfHigher?.call();
    return onAdoptRevenueCatTierIfHigher != null;
  }

  @override
  Future<void> syncWithRevenueCat() async {
    // Real production code should never reach this for the night-market
    // recovery path (that's exactly what R2 flagged); tests assert this
    // stays 0 for that flow, after the same leftover-init filter as above.
    if (forceSyncTierCalls == 0) return;
    syncWithRevenueCatCalls++;
  }
}

class NightMarketPaywallHarness {
  NightMarketPaywallHarness({
    required this.container,
    required this.router,
    required this.notifier,
    required StreamController<String?> accountController,
  }) : _accountController = accountController;

  final ProviderContainer container;
  final GoRouter router;
  final FakeSubscriptionNotifier notifier;
  final StreamController<String?> _accountController;

  void setAccess(EbookSubscriptionAccess access) {
    container.read(testNightMarketAccessProvider.notifier).state = access;
  }

  /// Emits a real account-id change through the same `StreamProvider`
  /// contract `nightMarketAccountIdProvider` uses in production, rather
  /// than mutating a side-channel value directly.
  void switchAccount(String? id) => _accountController.add(id);
}

/// Pumps whatever [builder] returns at '/' inside a GoRouter that also owns a
/// controllable /paywall stub, with the night-market subscription/account
/// seams overridden. The stub's four buttons cover every purchase outcome a
/// gate needs to survive:
///  - "buy essential"            -> server catches up before pop returns.
///  - "buy essential (sync lag)" -> pop says essential but the access
///    provider is left exactly as it was, so only [forceSyncTierShouldFail]
///    being false, or the RevenueCat recovery, can unlock this.
///  - "buy starter"               -> pops starter; must stay locked.
///  - "cancel"                    -> pops null.
Future<NightMarketPaywallHarness> pumpNightMarketPaywallHarness(
  WidgetTester tester, {
  required Widget Function(BuildContext, GoRouterState) builder,
  EbookSubscriptionAccess access = const EbookSubscriptionAccess.essential(),
  bool forceSyncTierShouldFail = false,
  bool revenueCatRecoveryConfirmsEssential = false,
  String? initialAccountId = 'harness-owner',
  List<GoRoute> extraRoutes = const [],
  Size size = const Size(390, 844),
}) async {
  late final ProviderContainer container;
  final notifier = FakeSubscriptionNotifier(
    const SubscriptionState(tier: SubscriptionTierHelper.free),
    forceSyncTierShouldFail: forceSyncTierShouldFail,
    onAdoptRevenueCatTierIfHigher: revenueCatRecoveryConfirmsEssential
        ? () => container.read(testNightMarketAccessProvider.notifier).state =
            const EbookSubscriptionAccess.essential()
        : null,
  );
  final accountController = StreamController<String?>.broadcast();

  container = ProviderContainer(
    overrides: [
      testNightMarketAccessProvider.overrideWith((ref) => access),
      ebookSubscriptionAccessProvider
          .overrideWith((ref) => ref.watch(testNightMarketAccessProvider)),
      nightMarketAccountIdProvider.overrideWith(
        (ref) => _accountStream(initialAccountId, accountController.stream),
      ),
      subscriptionProvider.overrideWith((ref) => notifier),
      subscriptionScreenRefreshProvider
          .overrideWith((ref) => () => notifier.refresh()),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(accountController.close);

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: builder),
      ...extraRoutes,
      GoRoute(
        path: '/paywall',
        builder: (context, state) => Consumer(
          builder: (context, ref, _) => Scaffold(
            body: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(paywallStubText),
                TextButton(
                  key: const ValueKey('paywall-buy-essential'),
                  onPressed: () {
                    ref.read(testNightMarketAccessProvider.notifier).state =
                        const EbookSubscriptionAccess.essential();
                    context.pop(SubscriptionTierHelper.essential);
                  },
                  child: const Text('buy essential'),
                ),
                TextButton(
                  key: const ValueKey('paywall-buy-essential-sync-lag'),
                  onPressed: () => context.pop(SubscriptionTierHelper.essential),
                  child: const Text('buy essential (sync lag)'),
                ),
                TextButton(
                  key: const ValueKey('paywall-buy-starter'),
                  onPressed: () {
                    ref.read(testNightMarketAccessProvider.notifier).state =
                        const EbookSubscriptionAccess.premium();
                    context.pop(SubscriptionTierHelper.starter);
                  },
                  child: const Text('buy starter'),
                ),
                TextButton(
                  key: const ValueKey('paywall-cancel'),
                  onPressed: () => context.pop(),
                  child: const Text('cancel'),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );

  return NightMarketPaywallHarness(
    container: container,
    router: router,
    notifier: notifier,
    accountController: accountController,
  );
}
