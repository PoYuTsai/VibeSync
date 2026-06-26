import 'dart:convert';

import 'package:hive_ce/hive_ce.dart';

import '../../domain/entities/practice_draw_draft.dart';

/// 翻牌草稿的本地存取（單筆：當下視窗那張還沒開聊的牌）。
abstract class PracticeDrawDraftStore {
  /// 取回草稿；無草稿或資料損毀回 null。**不**做過期判斷（視窗判斷在 controller，
  /// 用其權威 `now` 對照草稿的 nextResetAt）。
  PracticeDrawDraft? load();
  Future<void> save(PracticeDrawDraft draft);
  Future<void> clear();
}

/// 測試／無持久化情境用的記憶體版本。
class InMemoryPracticeDrawDraftStore implements PracticeDrawDraftStore {
  PracticeDrawDraft? _draft;

  @override
  PracticeDrawDraft? load() => _draft;

  @override
  Future<void> save(PracticeDrawDraft draft) async => _draft = draft;

  @override
  Future<void> clear() async => _draft = null;
}

/// 正式版本：以 JSON 字串存進既有的 settings box（加密）。刻意不新增 Hive typeId／
/// adapter／migration——草稿是短命的單筆狀態，JSON 足矣。
class HivePracticeDrawDraftStore implements PracticeDrawDraftStore {
  HivePracticeDrawDraftStore(this._box);

  final Box _box;

  static const String storageKey = 'practice_draw_draft';

  @override
  PracticeDrawDraft? load() {
    final raw = _box.get(storageKey);
    if (raw is! String) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return PracticeDrawDraft.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      // 損毀／舊格式：當作沒有草稿，避免進場崩潰。
      return null;
    }
  }

  @override
  Future<void> save(PracticeDrawDraft draft) =>
      _box.put(storageKey, jsonEncode(draft.toJson()));

  @override
  Future<void> clear() => _box.delete(storageKey);
}
