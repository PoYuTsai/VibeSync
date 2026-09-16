// test/helpers/night_market_paywall_harness.dart
//
// 夜市付費牆情境共用鷹架：可變訂閱切片、可變帳號 id（模擬中途切換帳號）、
// 一個含 /paywall stub 的 GoRouter，以及可控制 forceSyncTier／refresh 是否
// 失敗的假 SubscriptionNotifier。night_market_screen_test 與
// night_market_entry_card_test 共用同一份，避免各自重寫一次可能各自漏檢查
// 的鷹架（root-cause fix，2026-09-17）。
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

final testNightMarketAccountIdProvider =
    StateProvider<String?>((ref) => 'harness-owner');

/// Stands in for the real notifier so tests never touch Supabase/RevenueCat.
/// [forceSyncTierShouldFail] simulates "purchase succeeded but the server
/// sync call failed"; [onRevenueCatRecovery] stands in for what the real
/// `syncWithRevenueCat` does (ask RevenueCat's local cache and persist the
/// result into real state) so tests can tell "recovery confirms the
/// purchase" apart from "recovery also can't confirm it" without any
/// network.
class FakeSubscriptionNotifier extends SubscriptionNotifier {
  FakeSubscriptionNotifier(
    SubscriptionState seed, {
    this.forceSyncTierShouldFail = false,
    this.onRevenueCatRecovery,
  }) {
    state = seed;
  }

  final bool forceSyncTierShouldFail;
  final VoidCallback? onRevenueCatRecovery;
  int forceSyncTierCalls = 0;
  int refreshCalls = 0;
  int revenueCatRecoveryCalls = 0;

  @override
  Future<void> forceSyncTier(String tier) async {
    forceSyncTierCalls++;
    if (forceSyncTierShouldFail) {
      throw Exception('sync failed (test)');
    }
  }

  @override
  Future<void> refresh() async {
    refreshCalls++;
  }

  @override
  Future<void> syncWithRevenueCat() async {
    // The base constructor's own `_initialize()` fire-and-forgets a call to
    // this same method before any test interaction happens (it no-ops for
    // real, since SupabaseService.currentUser is null in tests). Only react
    // once a real paywall round trip has actually called forceSyncTier,
    // otherwise that leftover call would prematurely flip access before the
    // scenario under test even starts.
    if (forceSyncTierCalls == 0) return;
    revenueCatRecoveryCalls++;
    onRevenueCatRecovery?.call();
  }
}

class NightMarketPaywallHarness {
  NightMarketPaywallHarness({
    required this.container,
    required this.router,
    required this.notifier,
  });

  final ProviderContainer container;
  final GoRouter router;
  final FakeSubscriptionNotifier notifier;

  void setAccess(EbookSubscriptionAccess access) {
    container.read(testNightMarketAccessProvider.notifier).state = access;
  }

  void switchAccount(String? id) {
    container.read(testNightMarketAccountIdProvider.notifier).state = id;
  }
}

/// Pumps whatever [builder] returns at '/' inside a GoRouter that also owns a
/// controllable /paywall stub, with the night-market subscription/account
/// seams overridden. The stub's three buttons cover every purchase outcome a
/// gate needs to survive:
///  - "buy essential"            -> server catches up before pop returns.
///  - "buy essential (sync lag)" -> pop says essential but the access
///    provider is left exactly as it was, so only [forceSyncTierShouldFail]
///    being false, or the [revenueCatRecoveryConfirmsEssential] recovery,
///    can unlock this.
///  - "buy starter"               -> pops starter; must stay locked.
///  - "cancel"                    -> pops null.
Future<NightMarketPaywallHarness> pumpNightMarketPaywallHarness(
  WidgetTester tester, {
  required Widget Function(BuildContext, GoRouterState) builder,
  EbookSubscriptionAccess access = const EbookSubscriptionAccess.essential(),
  bool forceSyncTierShouldFail = false,
  bool revenueCatRecoveryConfirmsEssential = false,
  List<GoRoute> extraRoutes = const [],
  Size size = const Size(390, 844),
}) async {
  late final ProviderContainer container;
  final notifier = FakeSubscriptionNotifier(
    const SubscriptionState(tier: SubscriptionTierHelper.free),
    forceSyncTierShouldFail: forceSyncTierShouldFail,
    onRevenueCatRecovery: revenueCatRecoveryConfirmsEssential
        ? () => container.read(testNightMarketAccessProvider.notifier).state =
            const EbookSubscriptionAccess.essential()
        : null,
  );

  container = ProviderContainer(
    overrides: [
      testNightMarketAccessProvider.overrideWith((ref) => access),
      ebookSubscriptionAccessProvider
          .overrideWith((ref) => ref.watch(testNightMarketAccessProvider)),
      nightMarketAccountIdProvider
          .overrideWith((ref) => ref.watch(testNightMarketAccountIdProvider)),
      subscriptionProvider.overrideWith((ref) => notifier),
      subscriptionScreenRefreshProvider
          .overrideWith((ref) => () => notifier.refresh()),
    ],
  );
  addTearDown(container.dispose);

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
  );
}
