import 'package:hive_ce/hive_ce.dart';

import '../../domain/entities/practice_session.dart';

/// 最近練習場次的本地保存。以「visible thread（同一位對象）」為單位保留最近 5 段
/// 對話（local-only、加密）。同一位續玩多輪會共用一個 visiblePracticeThreadId，
/// 顯示與修剪都視為「一段對話」，不是多筆 session。
class PracticeSessionRepository {
  PracticeSessionRepository(this._box);

  final Box<PracticeSession> _box;

  /// 最多保留幾「段對話」（visible thread），非 session 數。
  static const int maxThreads = 5;

  /// 寫入/更新一場，並把舊段修剪到只剩最近 [maxThreads] 段對話。
  Future<void> save(PracticeSession session) async {
    await _box.put(session.id, session);
    await _trim();
  }

  /// 最近對話，每段（visible thread）只取最新一輪，依該段最新時間新到舊，
  /// 最多 [maxThreads] 段。同一位續玩多輪只會出現一筆（最新一輪含完整逐字稿）。
  List<PracticeSession> recentSessions() {
    return _newestPerThread(_box.values).take(maxThreads).toList();
  }

  /// 把多個 session 收斂成「每段對話最新一輪」，依時間新到舊。
  List<PracticeSession> _newestPerThread(Iterable<PracticeSession> sessions) {
    final sorted = sessions.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final seen = <String>{};
    final result = <PracticeSession>[];
    for (final s in sorted) {
      if (seen.add(threadKeyOf(s))) result.add(s);
    }
    return result;
  }

  PracticeSession? getById(String id) => _box.get(id);

  Future<void> delete(String id) => _box.delete(id);

  /// 同一位的跨輪識別。舊場無 [visiblePracticeThreadId] → 以 [id] 自成一段。
  static String threadKeyOf(PracticeSession s) =>
      s.visiblePracticeThreadId ?? s.id;

  /// 刪掉某段對話（visible thread）的所有輪次。只刪最新一場會讓舊輪又浮出來，
  /// 故一律連同同 threadKey 的全部 local session 一起刪。
  Future<void> deleteVisibleThread(String threadKey) async {
    final ids = _box.values
        .where((s) => threadKeyOf(s) == threadKey)
        .map((s) => s.id)
        .toList();
    await _box.deleteAll(ids);
  }

  /// 以「段對話」為單位修剪：保留最近 [maxThreads] 段；被淘汰的段，連同其
  /// 所有輪次一起刪。同一位續玩 3 輪只佔 1 段名額，不會擠掉其他段。
  Future<void> _trim() async {
    final newest = _newestPerThread(_box.values);
    if (newest.length <= maxThreads) return;
    final keepThreads = newest.take(maxThreads).map(threadKeyOf).toSet();
    final stale = _box.values
        .where((s) => !keepThreads.contains(threadKeyOf(s)))
        .map((s) => s.id)
        .toList();
    await _box.deleteAll(stale);
  }
}
