// lib/features/night_market/presentation/night_market_essential_gate.dart
//
// 夜市付費邊界共用邏輯。停點門檻（night_market_screen）與復盤入口
// （night_market_entry_card）是兩個獨立呼叫點，但「開付費牆 → 回來 →
// 同步／刷新 → 重查是否放行」這段必須是同一份實作：分別各寫一份，兩份
// 就有各自出錯、各自漏掉帳號一致性檢查的風險（root-cause fix，2026-09-17）。
//
// 重用電子書／測驗那套訂閱切片與 gateFor，不新增訂閱資料來源；essential
// 只認 isEssential，不得照抄 isPremium（chat_quiz_access.dart 的教訓）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/supabase_service.dart';
import '../../learning/domain/chat_quiz_access.dart';
import '../../learning/domain/models/ebook.dart';
import '../../learning/presentation/widgets/ebook_access_gate.dart';
import '../../subscription/data/providers/subscription_providers.dart';
import '../../subscription/domain/services/subscription_tier_helper.dart';

export '../../learning/domain/chat_quiz_access.dart' show ChatQuizGate, gateFor;
export '../../learning/domain/models/ebook.dart' show EbookAccess;
export '../../learning/presentation/widgets/ebook_access_gate.dart'
    show EbookSubscriptionAccess, ebookSubscriptionAccessProvider;

/// 目前登入帳號 id，跟著 Supabase auth 狀態即時更新——不是算一次就永久快取
/// 的普通 Provider。中途登出換帳號時，`ref.read(...).future` 必須讀到新值，
/// 不能停在啟動當下那個人（跨模型 review R1，2026-09-17：舊版用普通
/// `Provider<String?>` 內部直接呼叫靜態 getter，沒有任何 reactive
/// dependency，等於算一次快取一輩子，帳號一致性檢查形同虛設）。呼叫端讀
/// `.future` 而不是 `.value`：這個 provider 通常在付費牆流程裡第一次被
/// 讀到，`.value` 在 stream 還沒送出第一個事件前是 null，會把「還沒到」
/// 誤判成「換人了」。
///
/// 獨立成自己的 provider（不是重用 `ebookProgressOwnerProvider`）：雖然底層
/// 都是 `SupabaseService.authStateChanges`，但兩邊語意不同——一個是「進度
/// 歸屬」，一個是「這筆付費操作中途還是不是同一人在按」，不宜互相耦合。
final nightMarketAccountIdProvider = StreamProvider<String?>((ref) async* {
  yield SupabaseService.currentUser?.id;
  yield* SupabaseService.authStateChanges
      .map((authState) => authState.session?.user.id);
});

/// 開付費牆 → 回來 → 同步／刷新 → 回報現在是否放行，整段一起做完才回傳，
/// 不在中繼點提早下結論。
///
/// 呼叫端仍要自己保留重入旗標，並在旗標釋放前做完後續動作（重播／進復盤）
/// ——「開牆～後續動作」是同一段不可切開的操作，過早釋放旗標等於沒防到。
///
/// 每個 await 之後都重查帳號 id：中途登出或切換帳號時，剛才那次付費牆結果
/// 不得套用到現在這個帳號身上。真正的寫入前帳號一致性檢查在
/// `SubscriptionNotifier._syncSubscriptionViaEdgeFunction`
/// （`subscriptionSyncStillAppliesToAccount`）——不能只在這裡的外層 await
/// 結束後才發現切帳，那時內部早就寫進 `SubscriptionState`／`UsageService`
/// 了；這裡的重查是第二層、給夜市自己這次判斷用的防線。
Future<bool> resolveNightMarketEssentialUnlock(
  BuildContext context,
  WidgetRef ref,
) async {
  // `.future` (not `.value`) so the very first read waits for the stream's
  // first event instead of racing it: this provider is typically read for
  // the first time right here, and `.value` on a still-loading
  // `StreamProvider` is null — comparing that transient null against the
  // real id once it arrives would misfire as "account changed" on every
  // single call, never a real switch.
  final account = await ref.read(nightMarketAccountIdProvider.future);
  if (!context.mounted) return false;
  Future<bool> sameAccount() async =>
      await ref.read(nightMarketAccountIdProvider.future) == account;
  bool essentialAllowed() =>
      gateFor(
        EbookAccess.essential,
        ref.read(ebookSubscriptionAccessProvider),
      ) ==
      ChatQuizGate.allowed;

  final poppedTier = await context.push<String>('/paywall');
  if (!context.mounted) return false;
  if (!await sameAccount()) return false;

  if (poppedTier != null && poppedTier.isNotEmpty) {
    try {
      await ref.read(subscriptionProvider.notifier).forceSyncTier(poppedTier);
    } catch (e) {
      debugPrint('NightMarket paywall force sync failed: $e');
    }
    if (!context.mounted) return false;
    if (!await sameAccount()) return false;
  }

  try {
    await ref.read(subscriptionScreenRefreshProvider)();
  } catch (e) {
    debugPrint('NightMarket paywall refresh failed: $e');
  }
  if (!context.mounted) return false;
  if (!await sameAccount()) return false;
  if (essentialAllowed()) return true;
  if (poppedTier != SubscriptionTierHelper.essential) return false;

  // Money already changed hands (a real Essential purchase/restore just
  // completed) but our server-side mirror hasn't caught up — and calling
  // the existing routine `syncWithRevenueCat` cannot be treated as having
  // resolved this: it can itself adopt a stale-but-"successful" server
  // response over a fresher RevenueCat read (`syncedTier ?? rcTier` only
  // falls back when the call fails outright). `adoptRevenueCatTierIfHigher`
  // asks RevenueCat's local entitlement cache directly and only ever raises
  // the tier, never lowers it, so it can't be used to paper over a genuine
  // revocation/expiry — if RevenueCat itself does not confirm Essential,
  // this still falls through to "cannot confirm" below rather than
  // conjuring access from nothing.
  try {
    await ref.read(subscriptionProvider.notifier).adoptRevenueCatTierIfHigher();
  } catch (e) {
    debugPrint('NightMarket paywall RevenueCat recovery sync failed: $e');
  }
  if (!context.mounted) return false;
  if (!await sameAccount()) return false;
  if (essentialAllowed()) return true;
  if (!context.mounted) return false;

  // Genuinely cannot confirm the purchase that was just made. This is not a
  // cancellation, so a second paywall would look like asking to pay again —
  // give a neutral confirm/retry instead.
  showNightMarketGateNotice(context, '已收到你的購買，正在確認中，請稍後再試一次');
  return false;
}

/// resolving／unavailable 的中性提示；locked 由呼叫端各自決定要不要先開牆。
void showNightMarketGateNotice(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(message),
    action: actionLabel != null && onAction != null
        ? SnackBarAction(label: actionLabel, onPressed: onAction)
        : null,
  ));
}
