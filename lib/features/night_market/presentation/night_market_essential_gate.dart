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

/// 目前登入帳號 id 的快照，獨立成 provider 方便測試覆寫，也方便在付費牆
/// 回合中途重查「還是不是同一個人在操作」（同 ebookPaidEntitlementProvider
/// 為測試覆寫獨立出來的理由）。
final nightMarketAccountIdProvider = Provider<String?>((ref) {
  return SupabaseService.currentUser?.id;
});

/// 開付費牆 → 回來 → 同步／刷新 → 回報現在是否放行，整段一起做完才回傳，
/// 不在中繼點提早下結論。
///
/// 呼叫端仍要自己保留重入旗標，並在旗標釋放前做完後續動作（重播／進復盤）
/// ——「開牆～後續動作」是同一段不可切開的操作，過早釋放旗標等於沒防到。
///
/// 每個 await 之後都重查帳號 id：中途登出或切換帳號時，剛才那次付費牆結果
/// 不得套用到現在這個帳號身上。
Future<bool> resolveNightMarketEssentialUnlock(
  BuildContext context,
  WidgetRef ref,
) async {
  final account = ref.read(nightMarketAccountIdProvider);
  bool sameAccount() => ref.read(nightMarketAccountIdProvider) == account;
  bool essentialAllowed() =>
      gateFor(
        EbookAccess.essential,
        ref.read(ebookSubscriptionAccessProvider),
      ) ==
      ChatQuizGate.allowed;

  final poppedTier = await context.push<String>('/paywall');
  if (!context.mounted || !sameAccount()) return false;

  if (poppedTier != null && poppedTier.isNotEmpty) {
    try {
      await ref.read(subscriptionProvider.notifier).forceSyncTier(poppedTier);
    } catch (e) {
      debugPrint('NightMarket paywall force sync failed: $e');
    }
    if (!context.mounted || !sameAccount()) return false;
  }

  try {
    await ref.read(subscriptionScreenRefreshProvider)();
  } catch (e) {
    debugPrint('NightMarket paywall refresh failed: $e');
  }
  if (!context.mounted || !sameAccount()) return false;
  if (essentialAllowed()) return true;
  if (poppedTier != SubscriptionTierHelper.essential) return false;

  // Money already changed hands (a real Essential purchase/restore just
  // completed) but our server-side mirror hasn't caught up. A one-shot
  // "trust the popped string" fallback would only unblock this single
  // action — the very next independent gate check still reads the real
  // provider and would block again. Instead reuse the same RevenueCat-backed
  // recovery `syncWithRevenueCat` already performs elsewhere: it asks
  // RevenueCat's own local entitlement cache directly and persists the
  // result into the real subscription state, so this is never a bare trust
  // of the string — if RevenueCat itself does not confirm Essential, this
  // still returns false rather than conjuring access from nothing.
  try {
    await ref.read(subscriptionProvider.notifier).syncWithRevenueCat();
  } catch (e) {
    debugPrint('NightMarket paywall RevenueCat recovery sync failed: $e');
  }
  if (!context.mounted || !sameAccount()) return false;
  return essentialAllowed();
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
