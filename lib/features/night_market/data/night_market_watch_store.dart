// lib/features/night_market/data/night_market_watch_store.dart
//
// 夜市影片「看完過一次」的本機紀錄（Eric 2026-10-28：學習頁的「查看復盤」要先
// 看完影片才打得開）。看完＝最後一段播完、真的進到復盤那一刻。
//
// 只記在這支手機（Eric 拍板，不動伺服器與資料庫）：換手機或刪 App 重裝要再看
// 一次。存在加密的 settingsBox，key 一律綁帳號 id；沒有帳號時不寫入、讀到
// 沒看完（fail closed），不建立共用 key。
library;

import 'package:hive_ce/hive_ce.dart';

abstract class NightMarketWatchStore {
  /// 這個帳號在這支手機上看完過沒有。沒有帳號一律 false。
  bool hasWatched(String? accountId);

  /// 記成看完。冪等；沒有帳號不寫入。
  Future<void> markWatched(String accountId);
}

/// 測試／無持久化情境用的記憶體版本。
class InMemoryNightMarketWatchStore implements NightMarketWatchStore {
  InMemoryNightMarketWatchStore({Iterable<String> watchedAccounts = const []})
      : _watched = {...watchedAccounts};

  final Set<String> _watched;

  Set<String> get watchedAccounts => Set.unmodifiable(_watched);

  @override
  bool hasWatched(String? accountId) {
    final id = accountId?.trim() ?? '';
    return id.isNotEmpty && _watched.contains(id);
  }

  @override
  Future<void> markWatched(String accountId) async {
    final id = accountId.trim();
    if (id.isNotEmpty) _watched.add(id);
  }
}

/// 正式版本：存看完那一刻的 UTC 時間字串，只拿來判斷有沒有看完。刻意不新增
/// Hive typeId／adapter／migration。
class HiveNightMarketWatchStore implements NightMarketWatchStore {
  HiveNightMarketWatchStore(this._box, {DateTime Function()? now})
      : _now = now ?? DateTime.now;

  static const String storageKeyPrefix = 'night_market_watched_v1';

  final Box _box;
  final DateTime Function() _now;

  static String storageKeyFor(String accountId) {
    final id = accountId.trim();
    if (id.isEmpty) {
      throw ArgumentError('accountId 不得為空：夜市看完紀錄必須綁定帳號');
    }
    return '$storageKeyPrefix:$id';
  }

  @override
  bool hasWatched(String? accountId) {
    final id = accountId?.trim() ?? '';
    if (id.isEmpty) return false;
    return _box.get(storageKeyFor(id)) is String;
  }

  @override
  Future<void> markWatched(String accountId) async {
    final id = accountId.trim();
    if (id.isEmpty || hasWatched(id)) return;
    await _box.put(storageKeyFor(id), _now().toUtc().toIso8601String());
  }
}
