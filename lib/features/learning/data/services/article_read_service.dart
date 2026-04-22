import 'package:hive_ce/hive_ce.dart';
import '../../../../core/services/storage_service.dart';

class ArticleReadService {
  static const _dailyReadCountKey = 'article_daily_read_count';
  static const _dailyReadDateKey = 'article_daily_read_date';
  static const _dailyReadArticleIdsKey = 'article_daily_read_article_ids';
  static const int freeUserDailyLimit = 3;

  Box get _box => StorageService.usageBox;

  int _readCount() {
    return _box.get(_dailyReadCountKey, defaultValue: 0) as int;
  }

  List<String> _readArticleIds() {
    final raw = _box.get(_dailyReadArticleIdsKey, defaultValue: <String>[]);
    if (raw is List) {
      return raw
          .whereType<String>()
          .where((id) => id.trim().isNotEmpty)
          .toSet()
          .toList();
    }
    return <String>[];
  }

  int _usedCount() {
    final count = _readCount();
    final uniqueCount = _readArticleIds().length;
    return count > uniqueCount ? count : uniqueCount;
  }

  /// Get today's read count
  int getTodayReadCount() {
    _resetIfNewDay();
    return _usedCount();
  }

  /// Check if free user can read more articles today
  bool canRead() {
    _resetIfNewDay();
    return _usedCount() < freeUserDailyLimit;
  }

  bool hasReadArticle(String articleId) {
    _resetIfNewDay();
    return _readArticleIds().contains(articleId);
  }

  bool canReadArticle(String articleId) {
    _resetIfNewDay();
    return hasReadArticle(articleId) || canRead();
  }

  /// Record a read
  void recordRead() {
    _resetIfNewDay();
    final count = _readCount();
    _box.put(_dailyReadCountKey, count + 1);
  }

  void recordReadArticle(String articleId) {
    _resetIfNewDay();
    final ids = _readArticleIds();
    if (ids.contains(articleId)) return;
    if (_usedCount() >= freeUserDailyLimit) return;

    ids.add(articleId);
    _box.put(_dailyReadArticleIdsKey, ids);
    _box.put(_dailyReadCountKey, ids.length);
  }

  /// Get remaining reads for today
  int get remainingReads {
    _resetIfNewDay();
    return (freeUserDailyLimit - _usedCount()).clamp(0, freeUserDailyLimit);
  }

  /// Reset counter if it's a new day
  void _resetIfNewDay() {
    final lastDate = _box.get(_dailyReadDateKey, defaultValue: '') as String;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (lastDate != today) {
      _box.put(_dailyReadCountKey, 0);
      _box.put(_dailyReadArticleIdsKey, <String>[]);
      _box.put(_dailyReadDateKey, today);
    }
  }
}
