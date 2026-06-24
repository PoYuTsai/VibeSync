import 'package:hive_ce/hive_ce.dart';

import '../../domain/entities/practice_session.dart';

/// 最近練習場次的本地保存。只保留最近 5 場（local-only、加密）。
class PracticeSessionRepository {
  PracticeSessionRepository(this._box);

  final Box<PracticeSession> _box;

  static const int maxSessions = 5;

  /// 寫入/更新一場，並把舊場修剪到只剩最近 [maxSessions] 場。
  Future<void> save(PracticeSession session) async {
    await _box.put(session.id, session);
    await _trim();
  }

  /// 最近場次，依建立時間新到舊。
  List<PracticeSession> recentSessions() {
    final all = _box.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return all.take(maxSessions).toList();
  }

  PracticeSession? getById(String id) => _box.get(id);

  Future<void> delete(String id) => _box.delete(id);

  Future<void> _trim() async {
    if (_box.length <= maxSessions) return;
    final sorted = _box.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final stale = sorted.skip(maxSessions).map((s) => s.id).toList();
    await _box.deleteAll(stale);
  }
}
