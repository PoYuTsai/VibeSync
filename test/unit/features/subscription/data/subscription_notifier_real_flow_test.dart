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
      SupabaseService.debugInvokeFunctionOverride = (name, {body}) async =>
          _fakeSyncResponse(tier: SubscriptionTierHelper.essential, expiresAt: expiry);

      await notifier.refresh();

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
}
