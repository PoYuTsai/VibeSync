import 'dart:convert';

import 'package:hive_ce/hive_ce.dart';

/// 角色圖鑑解鎖記錄的本地存取（append-only 的 profileId 集合）。
///
/// 只記「曾經遇到過誰」，與翻牌扣費／session 生命週期完全解耦；
/// 老用戶歷史上抽過但未記錄的對象不回填（接受的限制，從現在起累積）。
abstract class PracticeCollectionStore {
  /// 已解鎖的 profileId 集合；無資料或資料損毀回空集合，絕不丟例外。
  Set<String> load();

  /// 記錄一位解鎖。空字串護欄：不寫入；重複 add 冪等。
  Future<void> add(String profileId);
}

/// 測試／無持久化情境用的記憶體版本。
class InMemoryPracticeCollectionStore implements PracticeCollectionStore {
  final Set<String> _ids = <String>{};

  @override
  Set<String> load() => {..._ids};

  @override
  Future<void> add(String profileId) async {
    if (profileId.isEmpty) return;
    _ids.add(profileId);
  }
}

/// 正式版本：JSON list 存進既有的加密 settings box。比照
/// HivePracticeDrawDraftStore 刻意不新增 Hive typeId／adapter／migration。
class HivePracticeCollectionStore implements PracticeCollectionStore {
  HivePracticeCollectionStore(this._box);

  final Box _box;

  static const String storageKey = 'practice_collection_unlocked';

  @override
  Set<String> load() {
    final raw = _box.get(storageKey);
    if (raw is! String) return <String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <String>{};
      return decoded
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet();
    } catch (_) {
      // 損毀／舊格式：當作沒有記錄，避免圖鑑進場崩潰；下次 add 會重建。
      return <String>{};
    }
  }

  @override
  Future<void> add(String profileId) async {
    if (profileId.isEmpty) return;
    final current = load();
    if (!current.add(profileId)) return; // 已存在：不重寫
    final list = current.toList()..sort();
    await _box.put(storageKey, jsonEncode(list));
  }
}
