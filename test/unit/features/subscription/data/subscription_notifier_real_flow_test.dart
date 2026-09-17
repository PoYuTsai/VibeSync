// 跨模型 review 第三輪（2026-09-17）：不得只測會被整個 override 掉的
// FakeSubscriptionNotifier，要讓真正的 SubscriptionNotifier、其寫回與
// EbookSubscriptionAccess 權限投影一起跑。這裡只在 SDK／HTTP／帳號來源
// 邊界（SupabaseService／RevenueCatService／
// SubscriptionNotifier._loadOrCreateSubscriptionRecord 的測試替身鉤子）
// 造假，不需要真的購買或真的網路。
//
// 純 Dart 單元測試（不是 testWidgets）：SubscriptionNotifier 的每一次寫入都
// 經過 _applyPendingDowngradeMetadata，會讀 StorageService.settingsBox／
// usageBox，所以仍需要一個真正打開的 Hive box——用暫存目錄跑純 Dart
// Hive.init，不會撞到 testWidgets 那種 fake-async 真磁碟 I/O 卡死的問題
// （那個問題只出在 pump 迴圈裡）。

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User, FunctionResponse;
import 'package:vibesync/core/constants/app_constants.dart';
import 'package:vibesync/core/services/revenuecat_service.dart';
import 'package:vibesync/core/services/supabase_service.dart';
import 'package:vibesync/core/services/usage_service.dart';
import 'package:vibesync/features/learning/domain/chat_quiz_access.dart';
import 'package:vibesync/features/learning/domain/models/ebook.dart' show EbookAccess;
import 'package:vibesync/features/learning/presentation/widgets/ebook_access_gate.dart';
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_tier_helper.dart';

User _fakeUser(String id) => User(
      id: id,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: DateTime.now().toIso8601String(),
    );

CustomerInfo _fakeCustomerInfo({
  required String tier,
  DateTime? expiresAt,
  String appUserId = 'rc-user',
}) {
  final productId = switch (tier) {
    SubscriptionTierHelper.essential => 'essential_monthly',
    SubscriptionTierHelper.starter => 'starter_monthly',
    _ => null,
  };
  final entitlements = productId == null
      ? <String, EntitlementInfo>{}
      : {
          tier: EntitlementInfo(
            tier,
            true,
            true,
            DateTime.now().toIso8601String(),
            DateTime.now().toIso8601String(),
            productId,
            true,
            expirationDate: expiresAt?.toIso8601String(),
          ),
        };
  return CustomerInfo(
    EntitlementInfos(entitlements, entitlements),
    const {},
    productId == null ? const [] : [productId],
    productId == null ? const [] : [productId],
    const [],
    DateTime.now().toIso8601String(),
    appUserId,
    const {},
    DateTime.now().toIso8601String(),
    latestExpirationDate: expiresAt?.toIso8601String(),
  );
}

Map<String, dynamic> _fakeSubscriptionRow({
  required String userId,
  String tier = SubscriptionTierHelper.free,
}) {
  final nowIso = DateTime.now().toIso8601String();
  return {
    'user_id': userId,
    'tier': tier,
    'monthly_messages_used': 0,
    'daily_messages_used': 0,
    'daily_reset_at': nowIso,
    'monthly_reset_at': nowIso,
    'expires_at': null,
  };
}

FunctionResponse _fakeSyncResponse({
  required String tier,
  DateTime? expiresAt,
}) {
  return FunctionResponse(
    status: 200,
    data: {
      'tier': tier,
      'monthlyMessagesUsed': 0,
      'dailyMessagesUsed': 0,
      'expiresAt': expiresAt?.toIso8601String(),
    },
  );
}

/// Minimal non-null [Offerings] so `_loadOfferings` actually reaches its own
/// `state.copyWith(offerings: ...)` write (review round 7, requirement 五) —
/// its check is only `if (offerings != null)`, so no packages are needed.
Offerings _fakeOfferings() => const Offerings({});

/// Minimal [StoreProduct] so `_loadStoreProducts` actually reaches its own
/// `state.copyWith(storeProducts: ...)` write instead of the always-empty
/// list `_isInitialized == false` otherwise forces in this pure-Dart harness.
StoreProduct _fakeStoreProduct(String productId) => StoreProduct(
      productId,
      'A fake product for tests',
      'Fake Product',
      9.99,
      r'$9.99',
      'USD',
    );

void main() {
  late Directory hiveDir;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('subscription_notifier_test_hive_');
    Hive.init(hiveDir.path);
    await Hive.openBox(AppConstants.settingsBox);
    await Hive.openBox(AppConstants.usageBox);
  });

  tearDownAll(() async {
    await Hive.close();
    if (await hiveDir.exists()) await hiveDir.delete(recursive: true);
  });

  setUp(() async {
    await Hive.box(AppConstants.settingsBox).clear();
    await Hive.box(AppConstants.usageBox).clear();
    SupabaseService.debugResetForTesting();
    RevenueCatService.debugResetForTesting();
    SubscriptionNotifier.debugLoadOrCreateSubscriptionRecordOverride = null;
    UsageService.debugCurrentUserIdOverride = null;
  });

  /// Boots a real [SubscriptionNotifier] for [userId], with every SDK/HTTP
  /// boundary faked to a stable "confirmed Free" starting point, and waits
  /// for its background `_initialize()` chain to settle.
  Future<SubscriptionNotifier> bootFreeNotifier(String userId) async {
    SupabaseService.debugCurrentUserOverride = () => _fakeUser(userId);
    UsageService.debugCurrentUserIdOverride = userId;
    SubscriptionNotifier.debugLoadOrCreateSubscriptionRecordOverride =
        ({required userId, required tier}) async =>
            _fakeSubscriptionRow(userId: userId);
    RevenueCatService.debugLoginOverride =
        (_) async => _fakeCustomerInfo(tier: SubscriptionTierHelper.free);
    RevenueCatService.debugGetCustomerInfoForAppUserIdOverride =
        (_) async => _fakeCustomerInfo(tier: SubscriptionTierHelper.free);
    // _loadSubscription's own boot-time call reaches _attemptStartupPaidRescue
    // whenever the resolved display tier is Free (i.e. on every boot in this
    // helper) — review round 4, requirement 二 confirmed this branch is very
    // much reachable, not dead code. Default it to "nothing to rescue" so
    // boot stays a clean, uneventful Free baseline; individual tests
    // override this to drive INTO the rescue branch deliberately.
    RevenueCatService.debugSyncPurchasesAndRefreshCustomerInfoOverride =
        ({expectedAppUserId}) async =>
            _fakeCustomerInfo(tier: SubscriptionTierHelper.free);
    SupabaseService.debugInvokeFunctionOverride = (name, {body}) async =>
        _fakeSyncResponse(tier: SubscriptionTierHelper.free);

    final notifier = SubscriptionNotifier();
    // Let the constructor's fire-and-forget _initialize() (login -> row read
    // -> write -> edge sync -> offerings -> syncWithRevenueCat) fully settle
    // before the test takes over.
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(notifier.state.tier, SubscriptionTierHelper.free, reason: 'boot sanity check');
    return notifier;
  }

  group('scenario 1 — adoption persists despite a stale/earlier background response', () {
    test(
        'adoptRevenueCatTierIfHigher adopts Essential; its own background '
        'confirmation returning a stale Free does not undo it', () async {
      final notifier = await bootFreeNotifier('user-a');

      // RevenueCat now confirms Essential (a purchase just went through);
      // the server's own row/edge-function still lags and would say Free.
      RevenueCatService.debugGetCustomerInfoForAppUserIdOverride = (_) async =>
          _fakeCustomerInfo(
            tier: SubscriptionTierHelper.essential,
            expiresAt: DateTime.now().add(const Duration(days: 30)),
          );
      SupabaseService.debugInvokeFunctionOverride = (name, {body}) async =>
          _fakeSyncResponse(tier: SubscriptionTierHelper.free);

      final adopted = await notifier.adoptRevenueCatTierIfHigher();
      expect(adopted, isTrue);
      expect(notifier.state.tier, SubscriptionTierHelper.essential);
      expect(notifier.state.renewsAt, isNotNull);

      // The confirmation call to the server was fired (unawaited) with the
      // stale response above — let it resolve and try to write.
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(
        notifier.state.tier,
        SubscriptionTierHelper.essential,
        reason: 'the stale background confirmation must not have undone the '
            'adoption',
      );

      // A genuinely newer, independent revocation must still be able to
      // take effect — but not through a single `syncWithRevenueCat` tick:
      // that method's own pre-existing, separately-reviewed
      // "local=essential, RevenueCat=free -> keep premium until sync
      // stabilizes" rule deliberately debounces a single transient RC-cache
      // mismatch and is out of this round's scope to change. The real
      // revocation path this notifier relies on is a fresh reload
      // (`refresh` -> `_loadSubscription`) once the server's own row has
      // caught up with an actually-past `expires_at` — reflecting a real
      // subscription lapse, not a momentary read glitch.
      RevenueCatService.debugGetCustomerInfoForAppUserIdOverride =
          (_) async => _fakeCustomerInfo(tier: SubscriptionTierHelper.free);
      SubscriptionNotifier.debugLoadOrCreateSubscriptionRecordOverride =
          ({required userId, required tier}) async =>
              _fakeSubscriptionRow(userId: userId, tier: SubscriptionTierHelper.free)
                ..['expires_at'] = DateTime.now()
                    .subtract(const Duration(days: 1))
                    .toIso8601String();
      SupabaseService.debugInvokeFunctionOverride = (name, {body}) async =>
          _fakeSyncResponse(tier: SubscriptionTierHelper.free);
      await notifier.refresh();
      expect(
        notifier.state.tier,
        SubscriptionTierHelper.free,
        reason: 'a real revocation (server row + RevenueCat both agree, with '
            'an actually-past expiry) must still land on reload',
      );
    });

    test(
        'adopted tier persists an unexpired renewsAt even when the prior '
        'state had none, and offline cache honors it afterwards', () async {
      final notifier = await bootFreeNotifier('user-b');
      expect(notifier.state.renewsAt, isNull);

      final expiry = DateTime.now().add(const Duration(days: 7));
      RevenueCatService.debugGetCustomerInfoForAppUserIdOverride =
          (_) async => _fakeCustomerInfo(
                tier: SubscriptionTierHelper.essential,
                expiresAt: expiry,
              );
      SupabaseService.debugInvokeFunctionOverride = (name, {body}) async =>
          _fakeSyncResponse(tier: SubscriptionTierHelper.essential, expiresAt: expiry);

      final adopted = await notifier.adoptRevenueCatTierIfHigher();
      expect(adopted, isTrue);
      expect(notifier.state.renewsAt, isNotNull);
      expect(notifier.state.renewsAt!.isAfter(DateTime.now()), isTrue);
      expect(UsageService.hasUnexpiredPaidEntitlement(), isTrue);

      // A genuine cold start: a BRAND NEW SubscriptionNotifier instance,
      // whose initial state is built by its constructor purely from
      // persisted storage (`_initialStateFromUsageSnapshot` ->
      // `UsageService().getLocalUsage()`) — not `notifier.state.copyWith`,
      // which would just relabel the same already-resolved live object and
      // prove nothing about what actually got persisted (review round 4,
      // requirement 五). Every SDK/HTTP call is stalled forever so this
      // inspects exactly what the constructor produces synchronously,
      // before `_initialize()` ever resolves anything.
      RevenueCatService.debugLoginOverride =
          (_) => Completer<CustomerInfo?>().future;
      RevenueCatService.debugGetCustomerInfoForAppUserIdOverride =
          (_) => Completer<CustomerInfo?>().future;
      SupabaseService.debugInvokeFunctionOverride =
          (name, {body}) => Completer<FunctionResponse>().future;
      SubscriptionNotifier.debugLoadOrCreateSubscriptionRecordOverride =
          ({required userId, required tier}) =>
              Completer<Map<String, dynamic>>().future;

      final coldStart = SubscriptionNotifier();
      final access = EbookSubscriptionAccess.fromState(
        coldStart.state,
        hasUnexpiredPaidEntitlement: UsageService.hasUnexpiredPaidEntitlement(),
      );
      expect(coldStart.state.tier, SubscriptionTierHelper.essential,
          reason: 'the fresh instance\'s own constructor must read Essential '
              'back from persisted storage, not from the old notifier');
      expect(access.isEssential, isTrue);
      expect(access.isResolved, isFalse); // still "loading" (offline)
      expect(access.hasUnexpiredPaidEntitlement, isTrue);
    });
  });

  group('scenario 2 — refresh/sync ordering: an earlier request must not '
      'clobber a later one', () {
    test('A starts, B starts and finishes, A resolves late with stale data: '
        "B's result wins", () async {
      final notifier = await bootFreeNotifier('user-c');

      final aGate = Completer<FunctionResponse>();
      var callCount = 0;
      SupabaseService.debugInvokeFunctionOverride = (name, {body}) async {
        callCount++;
        if (callCount == 1) {
          // Request A: stalls, then eventually resolves with a stale Free.
          return aGate.future;
        }
        // Request B: resolves immediately with the real, newer Essential.
        return _fakeSyncResponse(
          tier: SubscriptionTierHelper.essential,
          expiresAt: DateTime.now().add(const Duration(days: 30)),
        );
      };
      RevenueCatService.debugGetCustomerInfoForAppUserIdOverride =
          (_) async => _fakeCustomerInfo(tier: SubscriptionTierHelper.essential);

      // A: forceSyncTier('essential') starts and stalls on aGate.
      final aFuture = notifier.forceSyncTier(SubscriptionTierHelper.essential);
      await Future<void>.delayed(Duration.zero);

      // B: a second, independent, more current confirmation completes
      // first (e.g. the RevenueCat-backed recovery running right after).
      final adopted = await notifier.adoptRevenueCatTierIfHigher();
      expect(adopted, isTrue);
      expect(notifier.state.tier, SubscriptionTierHelper.essential);

      // Now let A's long-stalled, stale response land. A's own contract was
      // "confirm at least essential" (`forceSyncTier` floors on the tier it
      // was asked to sync to), so its stale Free reply is correctly
      // rejected as inconclusive rather than accepted as a downgrade —
      // surfacing as this specific call failing, which is why real callers
      // (the night-market gate) already treat forceSyncTier failures as
      // non-fatal and fall back to refresh/adopt.
      aGate.complete(_fakeSyncResponse(tier: SubscriptionTierHelper.free));
      await expectLater(aFuture, throwsException);
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(
        notifier.state.tier,
        SubscriptionTierHelper.essential,
        reason: "A's stale response must not overwrite B's newer result",
      );
    });

    test('account switches while a sync is in flight: the response is '
        'discarded, not applied to the new account', () async {
      final notifier = await bootFreeNotifier('user-d');

      final gate = Completer<FunctionResponse>();
      SupabaseService.debugInvokeFunctionOverride = (name, {body}) => gate.future;
      RevenueCatService.debugGetCustomerInfoForAppUserIdOverride =
          (_) async => _fakeCustomerInfo(tier: SubscriptionTierHelper.essential);

      final future = notifier.forceSyncTier(SubscriptionTierHelper.essential);
      await Future<void>.delayed(Duration.zero);

      // Account changes mid-flight (logout + different login).
      SupabaseService.debugCurrentUserOverride = () => _fakeUser('user-e');

      gate.complete(_fakeSyncResponse(tier: SubscriptionTierHelper.essential));
      await expectLater(future, throwsException); // syncedTier discarded -> null -> throw
      expect(
        notifier.state.tier,
        SubscriptionTierHelper.free,
        reason: "user-d's stale in-flight response must not be written "
            "after the account switched",
      );
    });
  });

  group(
      'scenario 2b (requirement 二) — _loadSubscription\'s own writes, not '
      'just the shared sync helper\'s, must honor account consistency', () {
    test(
        'account switches mid-refresh, before _loadSubscription\'s own '
        'first state write: that write is skipped, not applied to the '
        'account now signed in', () async {
      final notifier = await bootFreeNotifier('user-g');

      // The account switch happens while _loadSubscription is still
      // awaiting its own row fetch — before it reaches its first `state =`
      // write. If that write did not re-check the account, whoever is
      // signed in when it finally executes would receive user-g's row.
      SubscriptionNotifier.debugLoadOrCreateSubscriptionRecordOverride =
          ({required userId, required tier}) async {
        SupabaseService.debugCurrentUserOverride = () => _fakeUser('user-h');
        return _fakeSubscriptionRow(
          userId: userId,
          tier: SubscriptionTierHelper.essential,
        );
      };
      RevenueCatService.debugGetCustomerInfoForAppUserIdOverride =
          (_) async => _fakeCustomerInfo(tier: SubscriptionTierHelper.essential);

      await notifier.refresh();

      expect(
        notifier.state.tier,
        SubscriptionTierHelper.free,
        reason: "_loadSubscription's own write must not apply user-g's row "
            "once user-h is the one actually signed in",
      );
    });
  });

  group('scenario 4 — a failed confirmation retries confirmation only', () {
    test('adoptRevenueCatTierIfHigher failing once, then RevenueCat '
        'confirming on retry, adopts without any second server call storm',
        () async {
      final notifier = await bootFreeNotifier('user-f');

      RevenueCatService.debugGetCustomerInfoForAppUserIdOverride =
          (_) async => null; // RevenueCat itself can't confirm yet
      expect(await notifier.adoptRevenueCatTierIfHigher(), isFalse);
      expect(notifier.state.tier, SubscriptionTierHelper.free);

      // Retry: RevenueCat now confirms it.
      RevenueCatService.debugGetCustomerInfoForAppUserIdOverride =
          (_) async => _fakeCustomerInfo(
                tier: SubscriptionTierHelper.essential,
                expiresAt: DateTime.now().add(const Duration(days: 30)),
              );
      SupabaseService.debugInvokeFunctionOverride = (name, {body}) async =>
          _fakeSyncResponse(tier: SubscriptionTierHelper.essential);
      expect(await notifier.adoptRevenueCatTierIfHigher(), isTrue);
      expect(notifier.state.tier, SubscriptionTierHelper.essential);
    });
  });

  group(
      'scenario 6 (review round 4, requirement 一) — operation ordering, '
      'not just tier-rank comparison', () {
    test(
        'an earlier-started refresh stalls; a newer adopt writes Essential; '
        "the refresh's stale Free response arriving late must not undo it",
        () async {
      final notifier = await bootFreeNotifier('user-i');

      // A: refresh() stalls on its own DB-row fetch, before either of its
      // two write points has run.
      final rowGate = Completer<Map<String, dynamic>>();
      SubscriptionNotifier.debugLoadOrCreateSubscriptionRecordOverride =
          ({required userId, required tier}) => rowGate.future;
      final refreshFuture = notifier.refresh();
      await Future<void>.delayed(Duration.zero);

      // B: a newer, independent recovery completes first.
      RevenueCatService.debugGetCustomerInfoForAppUserIdOverride = (_) async =>
          _fakeCustomerInfo(
            tier: SubscriptionTierHelper.essential,
            expiresAt: DateTime.now().add(const Duration(days: 30)),
          );
      expect(await notifier.adoptRevenueCatTierIfHigher(), isTrue);
      expect(notifier.state.tier, SubscriptionTierHelper.essential);

      // A's long-stalled, stale Free row finally arrives. `minimumSyncedTier`
      // alone would not have caught this (refresh() doesn't confirm a
      // specific floor tier) — only operation ordering does.
      rowGate.complete(_fakeSubscriptionRow(userId: 'user-i'));
      await refreshFuture;
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(
        notifier.state.tier,
        SubscriptionTierHelper.essential,
        reason: "the earlier-started refresh's now-stale Free must not "
            'overwrite the newer adoption',
      );
    });

    test(
        'a newer, genuine revocation already wrote Free; an earlier '
        'essential confirmation arriving late must not resurrect Essential',
        () async {
      final notifier = await bootFreeNotifier('user-j');

      RevenueCatService.debugGetCustomerInfoForAppUserIdOverride = (_) async =>
          _fakeCustomerInfo(
            tier: SubscriptionTierHelper.essential,
            expiresAt: DateTime.now().add(const Duration(days: 30)),
          );
      expect(await notifier.adoptRevenueCatTierIfHigher(), isTrue);
      expect(notifier.state.tier, SubscriptionTierHelper.essential);

      // A: an earlier-started essential-confirmation stalls on its own
      // edge-function call.
      final gate = Completer<FunctionResponse>();
      SupabaseService.debugInvokeFunctionOverride = (name, {body}) => gate.future;
      final staleConfirm =
          notifier.forceSyncTier(SubscriptionTierHelper.essential);
      await Future<void>.delayed(Duration.zero);

      // B: a newer, independent reload discovers a genuine lapse (server
      // row + RevenueCat both agree, with an actually-past expiry) and
      // writes Free.
      RevenueCatService.debugGetCustomerInfoForAppUserIdOverride =
          (_) async => _fakeCustomerInfo(tier: SubscriptionTierHelper.free);
      SubscriptionNotifier.debugLoadOrCreateSubscriptionRecordOverride =
          ({required userId, required tier}) async => _fakeSubscriptionRow(
                userId: userId,
                tier: SubscriptionTierHelper.free,
              )..['expires_at'] = DateTime.now()
                  .subtract(const Duration(days: 1))
                  .toIso8601String();
      SupabaseService.debugInvokeFunctionOverride = (name, {body}) async =>
          _fakeSyncResponse(tier: SubscriptionTierHelper.free);
      await notifier.refresh();
      expect(notifier.state.tier, SubscriptionTierHelper.free);

      // Now A's long-stalled, stale Essential confirmation finally lands.
      // Its OWN `minimumSyncedTier` floor (essential) does NOT reject this —
      // the response IS essential, not below its own floor — only
      // operation ordering catches this.
      gate.complete(_fakeSyncResponse(tier: SubscriptionTierHelper.essential));
      await expectLater(staleConfirm, throwsException);
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(
        notifier.state.tier,
        SubscriptionTierHelper.free,
        reason: "A's stale essential confirmation must not resurrect a tier "
            'that a newer, genuine revocation already superseded',
      );
    });
  });

  group(
      'scenario 7 (review round 4, requirement 二) — _attemptStartupPaidRescue '
      'is reachable from refresh() and must honor the same rules', () {
    test(
        "a real paid entitlement RevenueCat's own resync reveals gets "
        'rescued via refresh(), and the offline cache reflects it '
        'afterward', () async {
      final notifier = await bootFreeNotifier('user-k');

      final expiry = DateTime.now().add(const Duration(days: 14));
      RevenueCatService.debugSyncPurchasesAndRefreshCustomerInfoOverride =
          ({expectedAppUserId}) async => _fakeCustomerInfo(
                tier: SubscriptionTierHelper.essential,
                expiresAt: expiry,
              );
      // _loadSubscription's OWN regular sync call (for displayTier=Free,
      // unrelated to the rescue) must keep seeing Free — only the rescue's
      // OWN confirm call (identifiable by it asking for `expectedTier:
      // essential` in its request body) sees Essential. Otherwise the
      // ordinary sync path alone would resolve this tier and the test
      // would prove nothing about the rescue branch specifically (review
      // round 5, requirement 四 — the previous version of this test set
      // Essential unconditionally for every edge call, so it still passed
      // even with the rescue's own adoption logic removed entirely).
      var sawRescueConfirmCall = false;
      SupabaseService.debugInvokeFunctionOverride = (name, {body}) async {
        final expectedTier = body?['expectedTier'] as String?;
        if (expectedTier == SubscriptionTierHelper.essential) {
          sawRescueConfirmCall = true;
          return _fakeSyncResponse(
            tier: SubscriptionTierHelper.essential,
            expiresAt: expiry,
          );
        }
        return _fakeSyncResponse(tier: SubscriptionTierHelper.free);
      };

      await notifier.refresh();

      expect(sawRescueConfirmCall, isTrue,
          reason: 'the rescue branch must actually have run its own '
              'confirm call, not just the ordinary sync path');
      expect(notifier.state.tier, SubscriptionTierHelper.essential);
      expect(notifier.state.renewsAt, isNotNull);
      expect(UsageService.hasUnexpiredPaidEntitlement(), isTrue);
    });

    test(
        "account switches while the rescue's own RevenueCat resync is in "
        'flight: the response is discarded for both state and the cached '
        'account, not applied to whoever is signed in now', () async {
      final notifier = await bootFreeNotifier('user-l');

      final gate = Completer<CustomerInfo?>();
      RevenueCatService.debugSyncPurchasesAndRefreshCustomerInfoOverride =
          ({expectedAppUserId}) => gate.future;

      final refreshFuture = notifier.refresh();
      // Let _loadSubscription's OWN regular sync call (still expecting
      // Free, unrelated to the rescue) run to completion first — it must
      // stay on the boot-default Free response, otherwise a later override
      // aimed at the rescue's call would corrupt that unrelated call too
      // and the test would stop isolating account consistency specifically.
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      // The rescue's own edge-function confirmation must actually be able
      // to succeed with Essential — otherwise `minimumSyncedTier` alone
      // would block the write regardless of account checks, and the test
      // would prove nothing about account consistency specifically.
      SupabaseService.debugInvokeFunctionOverride = (name, {body}) async =>
          _fakeSyncResponse(
            tier: SubscriptionTierHelper.essential,
            expiresAt: DateTime.now().add(const Duration(days: 14)),
          );

      // Account switches while the rescue's own resync call is stalled —
      // both the auth layer AND the usage-cache layer reflect the new user,
      // not just Supabase.
      SupabaseService.debugCurrentUserOverride = () => _fakeUser('user-m');
      UsageService.debugCurrentUserIdOverride = 'user-m';

      gate.complete(_fakeCustomerInfo(
        tier: SubscriptionTierHelper.essential,
        expiresAt: DateTime.now().add(const Duration(days: 14)),
      ));
      await refreshFuture;
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(
        notifier.state.tier,
        SubscriptionTierHelper.free,
        reason: "user-l's rescued entitlement must not be written after "
            'user-m signed in',
      );
      expect(
        UsageService.hasUnexpiredPaidEntitlement(),
        isFalse,
        reason: "the offline cache must not carry user-l's entitlement into "
            "user-m's session either",
      );
    });
  });

  group(
      'scenario 8 (review round 5, requirement 一) — operation ordering '
      'covers every writer of this same subscription record, not just the '
      'four night-market-specific methods', () {
    test(
        'an earlier-started syncWithRevenueCat stalls and later resolves '
        "with a stale Starter; a newer adopt already wrote Essential in "
        "between; syncWithRevenueCat's late Starter must not overwrite it",
        () async {
      final notifier = await bootFreeNotifier('user-n');

      // A: syncWithRevenueCat() starts — this is exactly what
      // `_initialize()` always calls unconditionally, so it is reachable
      // even though night market never calls it directly — and stalls on
      // its own RevenueCat read.
      final rcGate = Completer<CustomerInfo?>();
      var rcCallCount = 0;
      RevenueCatService.debugGetCustomerInfoForAppUserIdOverride = (_) {
        rcCallCount++;
        if (rcCallCount == 1) return rcGate.future;
        return Future.value(_fakeCustomerInfo(
          tier: SubscriptionTierHelper.essential,
          expiresAt: DateTime.now().add(const Duration(days: 30)),
        ));
      };
      final syncFuture = notifier.syncWithRevenueCat();
      await Future<void>.delayed(Duration.zero);

      // B: a newer, independent adopt completes first (its own RevenueCat
      // read is call #2, resolved immediately above), writing Essential.
      final adopted = await notifier.adoptRevenueCatTierIfHigher();
      expect(adopted, isTrue);
      expect(notifier.state.tier, SubscriptionTierHelper.essential);

      // A's long-stalled RevenueCat read finally resolves with a STALE
      // Starter (e.g. the SDK's local cache hadn't caught up with the
      // purchase that just happened) — a real, plausible race, not
      // `minimumSyncedTier`-relevant since syncWithRevenueCat never sets
      // one; only operation ordering protects this.
      rcGate.complete(_fakeCustomerInfo(
        tier: SubscriptionTierHelper.starter,
        expiresAt: DateTime.now().add(const Duration(days: 30)),
      ));
      await syncFuture;
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(
        notifier.state.tier,
        SubscriptionTierHelper.essential,
        reason: "syncWithRevenueCat's late, stale Starter read must not "
            "overwrite the newer adoption — it is not exempt just because "
            "night market never calls it directly; it still runs from "
            "_initialize() and writes the same subscription record",
      );
    });
  });

  group(
      'scenario 9 (review round 5, requirement 二) — isLoading/error '
      'resolution follows the same winning operation, not a stale one\'s '
      'own finally', () {
    test(
        "refresh() sets isLoading true; a concurrent adopt writes Essential "
        "before refresh's own _loadSubscription resolves; isLoading and the "
        'real permission projection must both end up resolved, not '
        'dangling', () async {
      final notifier = await bootFreeNotifier('user-o');

      // A: refresh() sets isLoading:true as its very first (synchronous)
      // action, then its own _loadSubscription stalls on the DB-row fetch.
      final rowGate = Completer<Map<String, dynamic>>();
      SubscriptionNotifier.debugLoadOrCreateSubscriptionRecordOverride =
          ({required userId, required tier}) => rowGate.future;
      final refreshFuture = notifier.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(notifier.state.isLoading, isTrue,
          reason: "sanity check: refresh()'s own initial write landed");

      // B: a newer, independent adopt completes first, writing Essential.
      RevenueCatService.debugGetCustomerInfoForAppUserIdOverride =
          (_) async => _fakeCustomerInfo(
                tier: SubscriptionTierHelper.essential,
                expiresAt: DateTime.now().add(const Duration(days: 30)),
              );
      expect(await notifier.adoptRevenueCatTierIfHigher(), isTrue);

      // A's stalled DB-row fetch finally resolves — its generation is
      // stale either way and must be discarded entirely, including not
      // touching isLoading/error (see [SubscriptionNotifier._claimWrite]).
      rowGate.complete(_fakeSubscriptionRow(userId: 'user-o'));
      await refreshFuture;
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(notifier.state.tier, SubscriptionTierHelper.essential);
      expect(
        notifier.state.isLoading,
        isFalse,
        reason: "adopt's own write must have explicitly resolved isLoading "
            "itself — the superseded _loadSubscription's early-return "
            "correctly writes nothing at all, so nothing else would ever "
            "clear the flag refresh() set",
      );
      expect(notifier.state.error, isNull);

      // The actual, real permission projection — not just the raw tier
      // field — since a dangling isLoading would make gateFor perpetually
      // report "still resolving" even though the tier is already correct.
      final access = EbookSubscriptionAccess.fromState(
        notifier.state,
        hasUnexpiredPaidEntitlement: UsageService.hasUnexpiredPaidEntitlement(),
      );
      expect(access.isEssential, isTrue);
      expect(access.isResolved, isTrue);
    });
  });
  group(
      'scenario 10 (review round 6, requirement 一) — syncWithRevenueCat\'s '
      'scheduled-downgrade branch must re-check the account after its own '
      'await, not just rely on the shared helper\'s internal check', () {
    test(
        'account switches while the branch\'s own edge-sync call is in '
        "flight; the new account hasn't started any operation of its own, "
        "so only the account re-check — not generation ordering — can "
        'catch this: state and the usage cache must stay untouched',
        () async {
      final notifier = await bootFreeNotifier('user-p');

      // Seed a Hive-backed pending downgrade (essential -> starter) using
      // the same keys `_storePendingDowngrade` writes, since the only
      // production path that calls it is the purchase flow, which has no
      // SDK seam in this harness. Adopting essential next, while this
      // record is already present, lets that adopt's own write (which -
      // like every write in this notifier - passes through
      // `_applyPendingDowngradeMetadata`) pick the pending fields up onto
      // `state`, exactly as a real purchase-time write would.
      final settingsBox = Hive.box(AppConstants.settingsBox);
      await settingsBox.put('pending_downgrade_user_id', 'user-p');
      await settingsBox.put(
          'pending_downgrade_from_tier', SubscriptionTierHelper.essential);
      await settingsBox.put(
          'pending_downgrade_to_tier', SubscriptionTierHelper.starter);
      await settingsBox.put(
          'pending_downgrade_to_product_id', 'starter_monthly');
      await settingsBox.put(
        'pending_downgrade_effective_at',
        DateTime.now().add(const Duration(days: 10)).toIso8601String(),
      );

      final essentialExpiry = DateTime.now().add(const Duration(days: 30));
      RevenueCatService.debugGetCustomerInfoForAppUserIdOverride =
          (_) async => _fakeCustomerInfo(
                tier: SubscriptionTierHelper.essential,
                expiresAt: essentialExpiry,
              );
      expect(await notifier.adoptRevenueCatTierIfHigher(), isTrue);
      expect(notifier.state.tier, SubscriptionTierHelper.essential);
      expect(notifier.state.hasPendingDowngrade, isTrue,
          reason: 'sanity check: the seeded pending record must have been '
              'picked up onto state before the scheduled-downgrade branch '
              'is even reachable');
      final originalRenewsAt = notifier.state.renewsAt;

      // A: syncWithRevenueCat()'s RevenueCat read reports starter — a
      // downgrade from the current essential, non-free — which satisfies
      // `_isScheduledPaidDowngradeSnapshot` and routes into the branch
      // this round's fix targets. Its own edge-function confirmation call
      // stalls.
      final gate = Completer<FunctionResponse>();
      SupabaseService.debugInvokeFunctionOverride = (name, {body}) => gate.future;
      RevenueCatService.debugGetCustomerInfoForAppUserIdOverride =
          (_) async => _fakeCustomerInfo(
                tier: SubscriptionTierHelper.starter,
                expiresAt: DateTime.now().add(const Duration(days: 60)),
              );
      final syncFuture = notifier.syncWithRevenueCat();
      await Future<void>.delayed(Duration.zero);

      // The account switches away. Critically, user-q has not started any
      // operation of its own, so `_claimWrite`'s generation check alone
      // would still succeed here — only the account re-check can catch
      // this (review round 6, requirement 一 is explicit that the helper
      // returning null already does not prove the caller may not still
      // write).
      SupabaseService.debugCurrentUserOverride = () => _fakeUser('user-q');
      UsageService.debugCurrentUserIdOverride = 'user-q';

      gate.complete(_fakeSyncResponse(
        tier: SubscriptionTierHelper.starter,
        expiresAt: DateTime.now().add(const Duration(days: 60)),
      ));
      await syncFuture;
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(
        notifier.state.tier,
        SubscriptionTierHelper.essential,
        reason: "the branch's continuation after the account switched must "
            'not have touched state at all',
      );
      expect(
        notifier.state.renewsAt,
        originalRenewsAt,
        reason: 'renewsAt must not have been overwritten by the stale '
            "branch's continuation either",
      );
      expect(
        UsageService.hasUnexpiredPaidEntitlement(),
        isFalse,
        reason: "the branch's own _syncUsageCache call must not have run "
            'under user-q once the account check catches it',
      );
    });
  });

  group(
      'scenario 11 (review round 6, requirement 四) — the shared edge-sync '
      'helper\'s own success write must resolve isLoading, not just tier',
      () {
    test(
        'an earlier-started refresh stalls after setting isLoading; a '
        'newer forceSyncTier succeeds through the shared helper; the '
        "stale refresh landing later must not resurrect isLoading or "
        'clobber the result', () async {
      final notifier = await bootFreeNotifier('user-r');

      // A: refresh() sets isLoading:true synchronously, then stalls on its
      // own DB-row fetch, before it ever reaches its own write.
      final rowGate = Completer<Map<String, dynamic>>();
      SubscriptionNotifier.debugLoadOrCreateSubscriptionRecordOverride =
          ({required userId, required tier}) => rowGate.future;
      final refreshFuture = notifier.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(notifier.state.isLoading, isTrue,
          reason: "sanity check: refresh()'s own initial write landed");

      // B: a newer, independent forceSyncTier succeeds — its ONLY write
      // path is the shared `_syncSubscriptionViaEdgeFunction` chokepoint,
      // not a `state.copyWith` of its own.
      SupabaseService.debugInvokeFunctionOverride = (name, {body}) async =>
          _fakeSyncResponse(
            tier: SubscriptionTierHelper.essential,
            expiresAt: DateTime.now().add(const Duration(days: 30)),
          );
      await notifier.forceSyncTier(SubscriptionTierHelper.essential);
      expect(notifier.state.tier, SubscriptionTierHelper.essential);
      expect(
        notifier.state.isLoading,
        isFalse,
        reason: "the shared helper's own success write must resolve "
            "isLoading itself — forceSyncTier has no other write path to "
            "do it, so a caller whose isLoading:true this call is meant "
            'to resolve would otherwise hang forever',
      );
      expect(notifier.state.error, isNull);

      // A's long-stalled, stale DB row finally arrives. Its generation is
      // stale either way and must write nothing at all — in particular it
      // must not resurrect isLoading:true over the newer, already-resolved
      // result ("不要由舊操作清掉新操作的 loading").
      rowGate.complete(_fakeSubscriptionRow(userId: 'user-r'));
      await refreshFuture;
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(notifier.state.tier, SubscriptionTierHelper.essential,
          reason: "the stale refresh must not have overwritten "
              "forceSyncTier's newer result");
      expect(
        notifier.state.isLoading,
        isFalse,
        reason: 'the superseded refresh must write nothing at all, not '
            "reset the winning operation's own resolved isLoading",
      );
      expect(notifier.state.error, isNull);

      // The real permission projection, not just the raw tier — a
      // dangling isLoading would make gateFor perpetually report "still
      // resolving" even with the correct tier already in place.
      final access = EbookSubscriptionAccess.fromState(
        notifier.state,
        hasUnexpiredPaidEntitlement: UsageService.hasUnexpiredPaidEntitlement(),
      );
      expect(access.isEssential, isTrue);
      expect(access.isResolved, isTrue);
    });
  });

  group(
      'scenario 12 (review round 6, requirement 五) — _loadSubscription\'s '
      'own catch block must honor the same account/operation ownership as '
      'its success path', () {
    test(
        'a newer confirmation already committed; a still-later, genuinely '
        'in-flight refresh sets isLoading true; the oldest stale DB '
        'request throwing afterward must not resurrect isLoading:false '
        'over it', () async {
      final notifier = await bootFreeNotifier('user-s');

      // A (oldest): refresh() #1 stalls on its own DB-row fetch (call #1
      // to the override below), before it ever reaches its own write.
      // C (newest): a second refresh() #2 will stall on call #2 — used
      // below to put a genuinely in-flight, still-unresolved isLoading:true
      // back onto state AFTER B has already committed, so this test can
      // tell "the guard skipped a stale write" apart from "the write
      // happened to look the same as what was already there" (state.error
      // cannot be used for this: `_applyPendingDowngradeMetadata`'s own
      // `copyWith` calls never pass `error:`, and `copyWith`'s `error`
      // parameter is a direct assignment rather than `?? this.error`, so
      // every write that routes through it — which is effectively all of
      // them — silently resets `error` back to null regardless of this
      // round's fix; a pre-existing, separate bug, out of this round's
      // scope, reported alongside these results rather than fixed here).
      final gateA = Completer<Map<String, dynamic>>();
      final gateC = Completer<Map<String, dynamic>>();
      var loadCallCount = 0;
      SubscriptionNotifier.debugLoadOrCreateSubscriptionRecordOverride =
          ({required userId, required tier}) {
        loadCallCount++;
        return loadCallCount == 1 ? gateA.future : gateC.future;
      };
      final refreshA = notifier.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(notifier.state.isLoading, isTrue,
          reason: "sanity check: A's own initial write landed");

      // B: a newer, independent adopt completes and commits first, writing
      // Essential and resolving isLoading:false.
      RevenueCatService.debugGetCustomerInfoForAppUserIdOverride = (_) async =>
          _fakeCustomerInfo(
            tier: SubscriptionTierHelper.essential,
            expiresAt: DateTime.now().add(const Duration(days: 30)),
          );
      expect(await notifier.adoptRevenueCatTierIfHigher(), isTrue);
      expect(notifier.state.tier, SubscriptionTierHelper.essential);
      expect(notifier.state.isLoading, isFalse);

      // C: a still-newer refresh() #2 starts — its own first (synchronous,
      // ungated) action sets isLoading:true again, genuinely in-flight,
      // then it too stalls on its own DB-row fetch (gateC, never resolved
      // in this test — cleaned up at the end).
      final refreshC = notifier.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(notifier.state.isLoading, isTrue,
          reason: "sanity check: C's own initial write landed");

      // A's long-stalled DB-row fetch finally rejects — a real possibility
      // (network drop, timeout), not just "resolves late with stale
      // data". A's generation is older than B's already-committed one, so
      // it must write nothing at all — in particular it must not stomp
      // C's genuinely in-flight isLoading:true with a stale isLoading:false.
      gateA.completeError(Exception('boom: stale DB request failed'));
      await refreshA;
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(
        notifier.state.isLoading,
        isTrue,
        reason: "A's stale exception must not have resolved isLoading — "
            "that would wrongly tell the UI nothing is loading while C's "
            'own, still-in-flight refresh has not concluded',
      );
      expect(notifier.state.tier, SubscriptionTierHelper.essential,
          reason: "A's stale exception must not have overwritten B's "
              'newer result either');

      // Clean up C so it doesn't dangle past the end of the test.
      gateC.complete(_fakeSubscriptionRow(
        userId: 'user-s',
        tier: SubscriptionTierHelper.essential,
      ));
      await refreshC;
    });

    test(
        'the account switches away while the old load is stalled; its '
        'stale exception landing afterward must not resolve isLoading for '
        'the account now signed in', () async {
      final notifier = await bootFreeNotifier('user-t');

      final rowGate = Completer<Map<String, dynamic>>();
      SubscriptionNotifier.debugLoadOrCreateSubscriptionRecordOverride =
          ({required userId, required tier}) => rowGate.future;
      final refreshFuture = notifier.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(notifier.state.isLoading, isTrue);

      // Account switches mid-flight, before the old load's exception
      // surfaces. No operation for user-u has started, so generation
      // ordering alone would not catch this — only the account re-check
      // does (same shape as scenario 10).
      SupabaseService.debugCurrentUserOverride = () => _fakeUser('user-u');

      rowGate.completeError(Exception('boom: stale DB request failed'));
      await refreshFuture;
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(
        notifier.state.tier,
        SubscriptionTierHelper.free,
        reason: "user-t's stale load failure must not have changed tier "
            'after user-u signed in',
      );
      expect(
        notifier.state.isLoading,
        isTrue,
        reason: "user-t's stale load failure must not resolve isLoading "
            "for user-u's session — a real account switch is expected to "
            'trigger its own fresh load elsewhere in the app, which this '
            "focused test does not simulate; what matters here is that "
            "the stale write is skipped outright, not silently accepted "
            "just because no competing operation happened to be running "
            'for the new account',
      );
    });
  });

  group(
      'scenario 13 (review round 6, requirement 三) — '
      'clearPendingDowngradeMetadata must honor the same account/operation '
      'ownership as every other writer of this record', () {
    test(
        'the account switches away while its own RevenueCat confirmation '
        'is in flight: neither the Hive pending record nor '
        'activeProductId/renewsAt on state may be touched for the new '
        'account, even though the tier itself never changes', () async {
      final notifier = await bootFreeNotifier('user-v');

      final settingsBox = Hive.box(AppConstants.settingsBox);
      await settingsBox.put('pending_downgrade_user_id', 'user-v');
      await settingsBox.put(
          'pending_downgrade_from_tier', SubscriptionTierHelper.essential);
      await settingsBox.put(
          'pending_downgrade_to_tier', SubscriptionTierHelper.starter);
      await settingsBox.put(
          'pending_downgrade_to_product_id', 'starter_monthly');
      await settingsBox.put(
        'pending_downgrade_effective_at',
        DateTime.now().add(const Duration(days: 10)).toIso8601String(),
      );

      final originalExpiry = DateTime.now().add(const Duration(days: 30));
      RevenueCatService.debugGetCustomerInfoForAppUserIdOverride =
          (_) async => _fakeCustomerInfo(
                tier: SubscriptionTierHelper.essential,
                expiresAt: originalExpiry,
              );
      expect(await notifier.adoptRevenueCatTierIfHigher(), isTrue);
      expect(notifier.state.hasPendingDowngrade, isTrue,
          reason: 'sanity check: the seeded pending record must have been '
              'picked up onto state first');
      final originalRenewsAt = notifier.state.renewsAt;

      // clearPendingDowngradeMetadata's own RevenueCat confirmation call
      // stalls. It would report a tier that is NOT a downgrade from the
      // current essential (so the pre-existing "still reports a downgrade"
      // guard alone would not block this), with a materially different
      // expiration — if the account check did not exist, this would still
      // land.
      final gate = Completer<CustomerInfo?>();
      RevenueCatService.debugGetCustomerInfoForAppUserIdOverride =
          (_) => gate.future;
      final clearFuture = notifier.clearPendingDowngradeMetadata();
      await Future<void>.delayed(Duration.zero);

      // The account switches away. No operation for user-w has started.
      SupabaseService.debugCurrentUserOverride = () => _fakeUser('user-w');

      gate.complete(_fakeCustomerInfo(
        tier: SubscriptionTierHelper.essential,
        expiresAt: DateTime.now().add(const Duration(days: 90)),
      ));
      final cleared = await clearFuture;

      expect(cleared, isFalse,
          reason: 'the operation could not complete for the account it '
              'started for');
      expect(
        notifier.state.hasPendingDowngrade,
        isTrue,
        reason: 'the pending fields on state must not have been cleared '
            "for user-w's session",
      );
      expect(
        notifier.state.renewsAt,
        originalRenewsAt,
        reason: 'renewsAt must not have been overwritten by the stale '
            'confirmation either',
      );
      expect(
        settingsBox.get('pending_downgrade_to_tier'),
        SubscriptionTierHelper.starter,
        reason: 'the Hive-backed pending record itself must not have been '
            'cleared out from under the new account',
      );
    });
  });
  group(
      'scenario 14 (review round 7, requirement 四) — a currently valid '
      'query failure must resolve as unavailable through the real gate, '
      'not as a confirmed lock that pushes toward purchase', () {
    test(
        'a fresh account whose subscription load fails outright sees '
        'gateFor(...) == unavailable, never allowed or locked', () async {
      final notifier = await bootFreeNotifier('user-x1');

      SubscriptionNotifier.debugLoadOrCreateSubscriptionRecordOverride =
          ({required userId, required tier}) async =>
              throw Exception('boom: subscription row fetch failed');
      await notifier.refresh();

      expect(notifier.state.error, isNotNull,
          reason: 'sanity check: the failure must actually have set an '
              'error for this to be a meaningful test of requirement 四');
      expect(notifier.state.isLoading, isFalse);

      final access = EbookSubscriptionAccess.fromState(
        notifier.state,
        hasUnexpiredPaidEntitlement: UsageService.hasUnexpiredPaidEntitlement(),
      );
      expect(access.hasError, isTrue);
      expect(
        access.isResolved,
        isFalse,
        reason: 'this is the exact projection night market and the ebook/'
            'quiz gates all read — a real failure must not read back as '
            'resolved (review round 7 P1)',
      );

      expect(
        gateFor(EbookAccess.premium, access),
        ChatQuizGate.unavailable,
        reason: 'a real, current failure must surface as a retryable '
            '"unavailable" screen — never as a confirmed lock, which is '
            'the one decision that actually pushes the UI toward a '
            'purchase CTA',
      );
      expect(
        gateFor(EbookAccess.essential, access),
        ChatQuizGate.unavailable,
        reason: 'same for an Essential-only gate',
      );
    });
  });

  group(
      'scenario 15 (review round 7, requirement 五) — a valid failure must '
      'survive unrelated copyWith updates that succeed afterward in the '
      'same operation chain', () {
    test(
        'offerings and store products both returning real, non-empty '
        'data right after a subscription load failure must not clear '
        "that failure's error", () async {
      final notifier = await bootFreeNotifier('user-x2');

      SubscriptionNotifier.debugLoadOrCreateSubscriptionRecordOverride =
          ({required userId, required tier}) async =>
              throw Exception('boom: subscription row fetch failed');
      // Minimal SDK doubles (review round 7 explicitly allows this) so
      // `_loadOfferings`/`_loadStoreProducts` — which `_isInitialized ==
      // false` would otherwise force to always return null/empty in this
      // pure-Dart harness — actually succeed with real data, exactly the
      // "unrelated update succeeds afterward" case requirement 五 asks for.
      RevenueCatService.debugGetOfferingsOverride =
          () async => _fakeOfferings();
      RevenueCatService.debugGetSubscriptionProductsOverride =
          (productIds) async => [_fakeStoreProduct('essential_monthly')];

      await notifier.refresh();

      expect(notifier.state.offerings, isNotNull,
          reason: 'sanity check: the offerings fetch actually succeeded '
              'with real data');
      expect(notifier.state.storeProducts, isNotEmpty,
          reason: 'sanity check: the store products fetch actually '
              'succeeded with real data');
      expect(
        notifier.state.error,
        isNotNull,
        reason: "the subscription load's own real failure must still be "
            'visible after offerings/store products succeed — neither '
            'represents a subscription confirmation and neither may '
            'clear a currently valid query error (review round 7, item '
            '二)',
      );
    });
  });

  group(
      'scenario 16 (review round 7, requirement 五) — a subsequent '
      'successful retry still explicitly clears the error, restoring the '
      'real gate to its normal decision', () {
    test(
        'after a failed load sets a real error, a fresh successful '
        'refresh clears it and gateFor resolves normally again',
        () async {
      final notifier = await bootFreeNotifier('user-x3');

      SubscriptionNotifier.debugLoadOrCreateSubscriptionRecordOverride =
          ({required userId, required tier}) async =>
              throw Exception('boom: subscription row fetch failed');
      await notifier.refresh();
      expect(notifier.state.error, isNotNull);
      final accessWhileFailing = EbookSubscriptionAccess.fromState(
        notifier.state,
        hasUnexpiredPaidEntitlement: UsageService.hasUnexpiredPaidEntitlement(),
      );
      expect(
        gateFor(EbookAccess.premium, accessWhileFailing),
        ChatQuizGate.unavailable,
      );

      // Retry: the row fetch now succeeds.
      SubscriptionNotifier.debugLoadOrCreateSubscriptionRecordOverride =
          ({required userId, required tier}) async =>
              _fakeSubscriptionRow(userId: userId);
      await notifier.refresh();

      expect(
        notifier.state.error,
        isNull,
        reason: 'a genuinely successful retry must still be able to '
            'explicitly clear a prior error (review round 7, item 三 — '
            'the fix must not have made error impossible to resolve)',
      );
      final accessAfterRetry = EbookSubscriptionAccess.fromState(
        notifier.state,
        hasUnexpiredPaidEntitlement: UsageService.hasUnexpiredPaidEntitlement(),
      );
      expect(accessAfterRetry.isResolved, isTrue);
      expect(
        gateFor(EbookAccess.premium, accessAfterRetry),
        ChatQuizGate.locked,
        reason: 'a confirmed Free user correctly locks a premium-only '
            'gate once resolved — this is the normal, healthy outcome '
            'retrying should restore',
      );
    });
  });

  group(
      'scenario 17 (review round 7, requirement 五) — an older, now-stale '
      'failure must not leak its error text after a newer operation '
      'already succeeded', () {
    test(
        'an earlier-started refresh stalls then fails; a newer adopt '
        'succeeds first; the stale failure landing later must not inject '
        'its error over the newer success', () async {
      final notifier = await bootFreeNotifier('user-x4');

      // A: refresh() stalls on its own DB-row fetch, then will fail.
      final rowGate = Completer<Map<String, dynamic>>();
      SubscriptionNotifier.debugLoadOrCreateSubscriptionRecordOverride =
          ({required userId, required tier}) => rowGate.future;
      final refreshFuture = notifier.refresh();
      await Future<void>.delayed(Duration.zero);

      // B: a newer, independent adopt completes first, writing Essential
      // and explicitly clearing error.
      RevenueCatService.debugGetCustomerInfoForAppUserIdOverride = (_) async =>
          _fakeCustomerInfo(
            tier: SubscriptionTierHelper.essential,
            expiresAt: DateTime.now().add(const Duration(days: 30)),
          );
      expect(await notifier.adoptRevenueCatTierIfHigher(), isTrue);
      expect(notifier.state.tier, SubscriptionTierHelper.essential);
      expect(notifier.state.error, isNull);

      // A's long-stalled DB-row fetch finally rejects. Now that a valid
      // error CAN actually persist (review round 7 fix), it is critical
      // that the pre-existing account/generation guard is still what
      // blocks this specific write from ever happening — otherwise this
      // stale exception's text would now visibly leak through where the
      // old (buggy) copyWith used to accidentally mask it.
      rowGate.completeError(Exception('boom: stale DB request failed'));
      await refreshFuture;
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(
        notifier.state.error,
        isNull,
        reason: "A's stale failure must not have overwritten B's newer, "
            'successful, error-free result',
      );
      expect(notifier.state.tier, SubscriptionTierHelper.essential);

      final access = EbookSubscriptionAccess.fromState(
        notifier.state,
        hasUnexpiredPaidEntitlement: UsageService.hasUnexpiredPaidEntitlement(),
      );
      expect(access.isResolved, isTrue);
      expect(gateFor(EbookAccess.essential, access), ChatQuizGate.allowed);
    });
  });

  group(
      'scenario 18 (review round 7, requirement 五) — the original valid/'
      'expired Essential cache rule still resolves correctly through the '
      'real gate after the error-preservation fix', () {
    test(
        'an unexpired cached Essential entitlement still grants access '
        'through gateFor while the fresh check is still resolving',
        () async {
      final box = Hive.box(AppConstants.usageBox);
      await box.put('last_known_paid_user_id', 'user-x5');
      await box.put('last_known_paid_tier', SubscriptionTierHelper.essential);
      await box.put('last_known_paid_monthly_limit', 999999);
      await box.put('last_known_paid_daily_limit', 999999);
      await box.put(
        'last_known_paid_expires_at',
        DateTime.now().add(const Duration(days: 5)).toIso8601String(),
      );
      await box.put('subscription_tier', SubscriptionTierHelper.free);
      await box.put('usage_user_id', 'user-x5');

      SupabaseService.debugCurrentUserOverride = () => _fakeUser('user-x5');
      UsageService.debugCurrentUserIdOverride = 'user-x5';
      // Cold start: every SDK/HTTP boundary stalls forever (same pattern
      // as scenario 1's cold-start test), so this inspects exactly what
      // the constructor produces synchronously from persisted storage.
      RevenueCatService.debugLoginOverride =
          (_) => Completer<CustomerInfo?>().future;
      RevenueCatService.debugGetCustomerInfoForAppUserIdOverride =
          (_) => Completer<CustomerInfo?>().future;
      SupabaseService.debugInvokeFunctionOverride =
          (name, {body}) => Completer<FunctionResponse>().future;
      SubscriptionNotifier.debugLoadOrCreateSubscriptionRecordOverride =
          ({required userId, required tier}) =>
              Completer<Map<String, dynamic>>().future;

      final coldStart = SubscriptionNotifier();
      expect(UsageService.hasUnexpiredPaidEntitlement(), isTrue);
      final access = EbookSubscriptionAccess.fromState(
        coldStart.state,
        hasUnexpiredPaidEntitlement: UsageService.hasUnexpiredPaidEntitlement(),
      );
      expect(access.isResolving, isTrue);
      expect(
        gateFor(EbookAccess.essential, access),
        ChatQuizGate.allowed,
        reason: 'an unexpired cached Essential entitlement must still '
            'grant access while offline/still-resolving — this is the '
            'pre-existing rule the round 7 error-preservation fix must '
            'not have disturbed',
      );
    });

    test(
        'an expired cached Essential entitlement must not grant access, '
        'and correctly falls through to resolving rather than an '
        'incorrect lock or a false grant', () async {
      final box = Hive.box(AppConstants.usageBox);
      await box.put('last_known_paid_user_id', 'user-x6');
      await box.put('last_known_paid_tier', SubscriptionTierHelper.essential);
      await box.put('last_known_paid_monthly_limit', 999999);
      await box.put('last_known_paid_daily_limit', 999999);
      await box.put(
        'last_known_paid_expires_at',
        DateTime.now().subtract(const Duration(days: 5)).toIso8601String(),
      );
      await box.put('subscription_tier', SubscriptionTierHelper.free);
      await box.put('usage_user_id', 'user-x6');

      SupabaseService.debugCurrentUserOverride = () => _fakeUser('user-x6');
      UsageService.debugCurrentUserIdOverride = 'user-x6';
      RevenueCatService.debugLoginOverride =
          (_) => Completer<CustomerInfo?>().future;
      RevenueCatService.debugGetCustomerInfoForAppUserIdOverride =
          (_) => Completer<CustomerInfo?>().future;
      SupabaseService.debugInvokeFunctionOverride =
          (name, {body}) => Completer<FunctionResponse>().future;
      SubscriptionNotifier.debugLoadOrCreateSubscriptionRecordOverride =
          ({required userId, required tier}) =>
              Completer<Map<String, dynamic>>().future;

      final coldStart = SubscriptionNotifier();
      expect(UsageService.hasUnexpiredPaidEntitlement(), isFalse);
      expect(coldStart.state.tier, SubscriptionTierHelper.free);
      final access = EbookSubscriptionAccess.fromState(
        coldStart.state,
        hasUnexpiredPaidEntitlement: UsageService.hasUnexpiredPaidEntitlement(),
      );
      expect(
        gateFor(EbookAccess.essential, access),
        ChatQuizGate.resolving,
        reason: 'an expired cache must not grant access on its own, but a '
            'genuinely unconfirmed cold start must still show '
            '"resolving" — not a confirmed lock — until the real network '
            'check lands',
      );
    });
  });
}
