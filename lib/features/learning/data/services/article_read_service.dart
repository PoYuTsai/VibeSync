import 'package:hive_ce/hive_ce.dart';
import '../../../../core/services/storage_service.dart';

class ArticleReadService {
  static const _dailyReadCountKey = 'article_daily_read_count';
  static const _dailyReadDateKey = 'article_daily_read_date';
  static const int freeUserDailyLimit = 3;

  Box get _box => StorageService.usageBox;

  /// Get today's read count
  int getTodayReadCount() {
    _resetIfNewDay();
    return _box.get(_dailyReadCountKey, defaultValue: 0) as int;
  }

  /// Check if free user can read more articles today
  bool canRead() {
    _resetIfNewDay();
    final count = _box.get(_dailyReadCountKey, defaultValue: 0) as int;
    return count < freeUserDailyLimit;
  }

  /// Record a read
  void recordRead() {
    _resetIfNewDay();
    final count = _box.get(_dailyReadCountKey, defaultValue: 0) as int;
    _box.put(_dailyReadCountKey, count + 1);
  }

  /// Get remaining reads for today
  int get remainingReads {
    _resetIfNewDay();
    final count = _box.get(_dailyReadCountKey, defaultValue: 0) as int;
    return (freeUserDailyLimit - count).clamp(0, freeUserDailyLimit);
  }

  /// Reset counter if it's a new day
  void _resetIfNewDay() {
    final lastDate = _box.get(_dailyReadDateKey, defaultValue: '') as String;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (lastDate != today) {
      _box.put(_dailyReadCountKey, 0);
      _box.put(_dailyReadDateKey, today);
    }
  }
}
