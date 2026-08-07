// 刪帳號本機清理的重放標記（2026-08-07 稽核 #7 前半）。
//
// 遠端帳號刪除成功後、本機清理（Hive 全清＋鍵盤脈絡/憑證清除＋session 登出）
// 完成前，如果 App 被強殺，清理就永遠不會發生——前用戶的資料躺在裝置上等
// 下一個帳號。marker 存 SharedPreferences（不在 Hive：clearAll 會把 Hive
// 清掉，marker 必須活過清理本身），App 啟動時 replayIfNeeded 補完。
//
// 冪等：清理步驟全部是 clear/purge 語意，重放在已清乾淨的裝置上是 no-op。

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

import 'keyboard_privacy_purge_service.dart';
import 'keyboard_token_bridge.dart';
import 'storage_service.dart';
import 'supabase_service.dart';

class AccountDeletionCleanup {
  static const markerKey = 'account_deletion_cleanup_pending_v1';

  /// 遠端刪除成功的當下就落 marker——清理成功後由 [clearMarker] 收走。
  static Future<void> markPending({String? ownerUserId}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(markerKey, ownerUserId ?? '');
  }

  static Future<void> clearMarker() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(markerKey);
  }

  /// App 啟動時呼叫：上一輪刪帳號的本機清理被強殺 → 在任何人登入前補完。
  /// 任一步驟失敗會保留 marker（下次啟動再試）並把錯誤往上拋，呼叫端
  /// 決定要不要擋啟動。
  static Future<void> replayIfNeeded({
    Future<void> Function(String? ownerUserId)? purgeKeyboardContext,
    Future<void> Function()? clearLocalStorage,
    Future<void> Function()? purgeKeyboardCredentials,
    Future<void> Function()? clearSession,
    Future<SharedPreferences> Function()? prefsProvider,
  }) async {
    final prefs =
        await (prefsProvider ?? SharedPreferences.getInstance)();
    final raw = prefs.getString(markerKey);
    if (raw == null) return;

    debugPrint('Replaying interrupted account-deletion local cleanup');
    final owner = raw.isEmpty ? null : raw;
    await (purgeKeyboardContext ?? _defaultPurgeKeyboardContext)(owner);
    await (clearLocalStorage ?? StorageService.clearAll)();
    await (purgeKeyboardCredentials ??
        KeyboardTokenBridge.purgeAllForAccountDeletion)();
    await (clearSession ?? SupabaseService.clearLocalSessionAfterDeletion)();
    await prefs.remove(markerKey);
  }

  static Future<void> _defaultPurgeKeyboardContext(String? ownerUserId) {
    return KeyboardPrivacyPurgeService.live.purge(
      KeyboardContextPurgeScope.accountDeletion,
      ownerUserId: ownerUserId,
    );
  }
}
