// 跨模型 review R1/R2（2026-09-17）：forceSyncTier／syncWithRevenueCat 共用的
// 寫入前帳號檢查，以及「剛完成購買，RevenueCat 本機已確認但伺服器回應還沒
// 追上」的單向採用判斷。兩者都是純函式，直接單元測試，不需要真的打
// Supabase／RevenueCat（那兩個服務目前沒有測試替身可插）。

import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_tier_helper.dart';

void main() {
  group('subscriptionSyncStillAppliesToAccount', () {
    test('同一個帳號 id（含都未登入的 null）→ 仍然適用', () {
      expect(
        subscriptionSyncStillAppliesToAccount(
          startedForUserId: 'user-a',
          currentUserId: 'user-a',
        ),
        isTrue,
      );
      expect(
        subscriptionSyncStillAppliesToAccount(
          startedForUserId: null,
          currentUserId: null,
        ),
        isTrue,
      );
    });

    test('同步途中換了帳號 → 不適用，回應必須丟棄', () {
      expect(
        subscriptionSyncStillAppliesToAccount(
          startedForUserId: 'user-a',
          currentUserId: 'user-b',
        ),
        isFalse,
      );
      // 同步途中登出：也不得把「登出前那個人」的回應套用到現在（未登入）。
      expect(
        subscriptionSyncStillAppliesToAccount(
          startedForUserId: 'user-a',
          currentUserId: null,
        ),
        isFalse,
      );
    });
  });

  group('shouldAdoptRevenueCatTier', () {
    test('RevenueCat 比目前檔位高 → 採用（剛付款、伺服器還沒追上）', () {
      expect(
        shouldAdoptRevenueCatTier(
          currentTier: SubscriptionTierHelper.free,
          revenueCatTier: SubscriptionTierHelper.essential,
        ),
        isTrue,
      );
      expect(
        shouldAdoptRevenueCatTier(
          currentTier: SubscriptionTierHelper.starter,
          revenueCatTier: SubscriptionTierHelper.essential,
        ),
        isTrue,
      );
    });

    test('RevenueCat 與目前檔位相同 → 不採用（沒有新資訊）', () {
      expect(
        shouldAdoptRevenueCatTier(
          currentTier: SubscriptionTierHelper.essential,
          revenueCatTier: SubscriptionTierHelper.essential,
        ),
        isFalse,
      );
    });

    test(
        'RevenueCat 比目前檔位低 → 不採用（可能只是本機 SDK 快取還沒更新；'
        '真正的撤銷／到期／降級交給既有 syncWithRevenueCat／_loadSubscription 的'
        '例行同步處理，這個單向函式永遠不會反過來降級）', () {
      expect(
        shouldAdoptRevenueCatTier(
          currentTier: SubscriptionTierHelper.essential,
          revenueCatTier: SubscriptionTierHelper.free,
        ),
        isFalse,
      );
      expect(
        shouldAdoptRevenueCatTier(
          currentTier: SubscriptionTierHelper.essential,
          revenueCatTier: SubscriptionTierHelper.starter,
        ),
        isFalse,
      );
    });
  });
}
