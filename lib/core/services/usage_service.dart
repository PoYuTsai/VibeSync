// lib/core/services/usage_service.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_constants.dart';
import 'storage_service.dart';

/// User's current usage data
class UsageData {
  final int monthlyUsed;
  final int monthlyLimit;
  final int dailyUsed;
  final int dailyLimit;
  final DateTime dailyResetAt;
  final String tier;

  const UsageData({
    required this.monthlyUsed,
    required this.monthlyLimit,
    required this.dailyUsed,
    required this.dailyLimit,
    required this.dailyResetAt,
    this.tier = 'free',
  });

  /// Check if user can perform analysis
  bool get canAnalyze => monthlyUsed < monthlyLimit && dailyUsed < dailyLimit;

  /// Remaining monthly messages
  int get monthlyRemaining => (monthlyLimit - monthlyUsed).clamp(0, monthlyLimit);

  /// Remaining daily messages
  int get dailyRemaining => (dailyLimit - dailyUsed).clamp(0, dailyLimit);

  /// Monthly usage percentage (0.0 - 1.0)
  double get monthlyPercentage =>
      monthlyLimit > 0 ? (monthlyUsed / monthlyLimit).clamp(0.0, 1.0) : 0.0;

  /// Daily usage percentage (0.0 - 1.0)
  double get dailyPercentage =>
      dailyLimit > 0 ? (dailyUsed / dailyLimit).clamp(0.0, 1.0) : 0.0;

  /// Check if can afford specific message count
  bool canAfford(int messageCount) {
    return monthlyRemaining >= messageCount && dailyRemaining >= messageCount;
  }

  /// Create copy with updated values
  UsageData copyWith({
    int? monthlyUsed,
    int? dailyUsed,
    DateTime? dailyResetAt,
  }) {
    return UsageData(
      monthlyUsed: monthlyUsed ?? this.monthlyUsed,
      monthlyLimit: monthlyLimit,
      dailyUsed: dailyUsed ?? this.dailyUsed,
      dailyLimit: dailyLimit,
      dailyResetAt: dailyResetAt ?? this.dailyResetAt,
      tier: tier,
    );
  }

  /// Default free tier usage
  factory UsageData.free() {
    return UsageData(
      monthlyUsed: 0,
      monthlyLimit: AppConstants.freeMonthlyLimit,
      dailyUsed: 0,
      dailyLimit: AppConstants.freeDailyLimit,
      dailyResetAt: _getNextMidnight(),
      tier: 'free',
    );
  }

  static DateTime _getNextMidnight() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day + 1);
  }
}

/// Service for tracking and managing usage
class UsageService {
  static const _monthlyUsedKey = 'monthly_used';
  static const _dailyUsedKey = 'daily_used';
  static const _dailyResetAtKey = 'daily_reset_at';
  static const _monthlyResetAtKey = 'monthly_reset_at';

  /// Get current usage data (local cache)
  UsageData getLocalUsage() {
    final box = StorageService.usageBox;
    final now = DateTime.now();

    // Check if daily reset needed
    final dailyResetAtStr = box.get(_dailyResetAtKey) as String?;
    DateTime dailyResetAt;
    int dailyUsed;

    if (dailyResetAtStr != null) {
      dailyResetAt = DateTime.parse(dailyResetAtStr);
      if (now.isAfter(dailyResetAt)) {
        // Reset daily usage
        dailyUsed = 0;
        dailyResetAt = _getNextMidnight();
        box.put(_dailyUsedKey, 0);
        box.put(_dailyResetAtKey, dailyResetAt.toIso8601String());
      } else {
        dailyUsed = box.get(_dailyUsedKey) as int? ?? 0;
      }
    } else {
      dailyUsed = 0;
      dailyResetAt = _getNextMidnight();
      box.put(_dailyResetAtKey, dailyResetAt.toIso8601String());
    }

    // Check if monthly reset needed
    final monthlyResetAtStr = box.get(_monthlyResetAtKey) as String?;
    int monthlyUsed;

    if (monthlyResetAtStr != null) {
      final monthlyResetAt = DateTime.parse(monthlyResetAtStr);
      if (now.month != monthlyResetAt.month || now.year != monthlyResetAt.year) {
        // Reset monthly usage
        monthlyUsed = 0;
        box.put(_monthlyUsedKey, 0);
        box.put(_monthlyResetAtKey, now.toIso8601String());
      } else {
        monthlyUsed = box.get(_monthlyUsedKey) as int? ?? 0;
      }
    } else {
      monthlyUsed = 0;
      box.put(_monthlyResetAtKey, now.toIso8601String());
    }

    // TODO: Get actual tier from subscription service
    return UsageData(
      monthlyUsed: monthlyUsed,
      monthlyLimit: AppConstants.freeMonthlyLimit,
      dailyUsed: dailyUsed,
      dailyLimit: AppConstants.freeDailyLimit,
      dailyResetAt: dailyResetAt,
      tier: 'free',
    );
  }

  /// Check if user can afford analysis and deduct usage
  bool checkAndDeduct(int messageCount) {
    final usage = getLocalUsage();
    if (!usage.canAfford(messageCount)) return false;

    // Update local usage
    final box = StorageService.usageBox;
    box.put(_monthlyUsedKey, usage.monthlyUsed + messageCount);
    box.put(_dailyUsedKey, usage.dailyUsed + messageCount);

    return true;
  }

  /// Add usage (called after successful analysis)
  void addUsage(int messageCount) {
    final box = StorageService.usageBox;
    final currentMonthly = box.get(_monthlyUsedKey) as int? ?? 0;
    final currentDaily = box.get(_dailyUsedKey) as int? ?? 0;

    box.put(_monthlyUsedKey, currentMonthly + messageCount);
    box.put(_dailyUsedKey, currentDaily + messageCount);
  }

  /// Reset all usage (for testing)
  void resetUsage() {
    final box = StorageService.usageBox;
    box.put(_monthlyUsedKey, 0);
    box.put(_dailyUsedKey, 0);
  }

  static DateTime _getNextMidnight() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day + 1);
  }
}

/// Provider for UsageService
final usageServiceProvider = Provider<UsageService>((ref) => UsageService());

/// Provider for current usage data
final usageDataProvider = Provider<UsageData>((ref) {
  final service = ref.watch(usageServiceProvider);
  return service.getLocalUsage();
});
