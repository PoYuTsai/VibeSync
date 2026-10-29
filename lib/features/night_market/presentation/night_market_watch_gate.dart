// lib/features/night_market/presentation/night_market_watch_gate.dart
//
// 夜市「復盤要先看完影片」（Eric 2026-10-28）。學習頁的「查看復盤」原本不用看
// 影片就能直接打開、只擋 Essential（ADR #46）；現在要先用這個帳號在這支手機上
// 看完一次（最後一段播完、進到復盤），Essential 的門檻照舊在後面。
library;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/storage_service.dart';
import '../data/night_market_watch_store.dart';
import 'night_market_essential_gate.dart';

final nightMarketWatchStoreProvider = Provider<NightMarketWatchStore>((ref) {
  return HiveNightMarketWatchStore(StorageService.settingsBox);
});

/// 目前帳號在這支手機上看完過夜市影片沒有。跟著帳號變；讀不到一律當沒看完。
final nightMarketWatchedProvider =
    AsyncNotifierProvider<NightMarketWatchedController, bool>(
  NightMarketWatchedController.new,
);

class NightMarketWatchedController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final account = await ref.watch(nightMarketAccountIdProvider.future);
    try {
      return ref.read(nightMarketWatchStoreProvider).hasWatched(account);
    } catch (e) {
      debugPrint('NightMarket watched read failed: $e');
      return false;
    }
  }

  /// 最後一段播完、進到復盤時呼叫，記在 [accountId]（這一輪是誰看的）底下。
  /// 當下的帳號已經不是他就不寫（主審 r1 P1：不能把上一個人的完播記給新帳號）；
  /// 寫入期間換了帳號，也不把「看完」發布出去（新帳號照自己的紀錄重算）。
  Future<void> markWatched(String accountId) async {
    final owner = accountId.trim();
    if (owner.isEmpty || await _currentAccount() != owner) return;
    try {
      await ref.read(nightMarketWatchStoreProvider).markWatched(owner);
    } catch (e) {
      debugPrint('NightMarket watched write failed: $e');
      return;
    }
    if (await _currentAccount() == owner) state = const AsyncData(true);
  }

  Future<String> _currentAccount() async =>
      (await ref.read(nightMarketAccountIdProvider.future))?.trim() ?? '';
}
