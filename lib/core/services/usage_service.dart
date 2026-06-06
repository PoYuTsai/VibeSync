// lib/core/services/usage_service.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import '../constants/app_constants.dart';
import '../../features/subscription/domain/services/subscription_tier_helper.dart';
import 'storage_service.dart';
import 'supabase_service.dart';

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
  int get monthlyRemaining =>
      (monthlyLimit - monthlyUsed).clamp(0, monthlyLimit);

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
  static const _tierKey = 'subscription_tier';
  static const _monthlyLimitKey = 'subscription_monthly_limit';
  static const _dailyLimitKey = 'subscription_daily_limit';
  static const _userIdKey = 'usage_user_id';
  static const _lastKnownPaidTierKey = 'last_known_paid_tier';
  static const _lastKnownPaidMonthlyLimitKey = 'last_known_paid_monthly_limit';
  static const _lastKnownPaidDailyLimitKey = 'last_known_paid_daily_limit';
  static const _lastKnownPaidExpiresAtKey = 'last_known_paid_expires_at';
  static const _lastKnownPaidUserIdKey = 'last_known_paid_user_id';

  @visibleForTesting
  static String? debugCurrentUserIdOverride;

  static void syncSubscriptionSnapshot({
    required String tier,
    required int monthlyLimit,
    required int dailyLimit,
    int? monthlyUsed,
    int? dailyUsed,
    DateTime? paidExpiresAt,
    bool clearPaidSnapshot = false,
  }) {
    final box = StorageService.usageBox;
    final currentUserId = _currentUserId;
    final normalizedTier = SubscriptionTierHelper.normalizeTier(tier);
    if (currentUserId != null) {
      box.put(_userIdKey, currentUserId);
    }
    box.put(_tierKey, normalizedTier);
    box.put(_monthlyLimitKey, monthlyLimit);
    box.put(_dailyLimitKey, dailyLimit);
    if (monthlyUsed != null) {
      box.put(_monthlyUsedKey, monthlyUsed);
    }
    if (dailyUsed != null) {
      box.put(_dailyUsedKey, dailyUsed);
    }
    if (clearPaidSnapshot) {
      _clearLastKnownPaidSnapshot(box);
    } else if (normalizedTier != SubscriptionTierHelper.free) {
      _writeLastKnownPaidSnapshot(
        box,
        tier: normalizedTier,
        monthlyLimit: monthlyLimit,
        dailyLimit: dailyLimit,
        expiresAt: paidExpiresAt,
      );
    }
  }

  static Future<void> clearSnapshot() async {
    final box = StorageService.usageBox;
    await Future.wait([
      box.delete(_monthlyUsedKey),
      box.delete(_dailyUsedKey),
      box.delete(_dailyResetAtKey),
      box.delete(_monthlyResetAtKey),
      box.delete(_tierKey),
      box.delete(_monthlyLimitKey),
      box.delete(_dailyLimitKey),
      box.delete(_userIdKey),
      box.delete(_lastKnownPaidTierKey),
      box.delete(_lastKnownPaidMonthlyLimitKey),
      box.delete(_lastKnownPaidDailyLimitKey),
      box.delete(_lastKnownPaidExpiresAtKey),
      box.delete(_lastKnownPaidUserIdKey),
    ]);
  }

  static String? get _currentUserId =>
      debugCurrentUserIdOverride ?? SupabaseService.currentUser?.id;

  static void _resetSnapshotIfAccountChanged() {
    final currentUserId = _currentUserId;
    if (currentUserId == null) return;

    final box = StorageService.usageBox;
    final storedUserId = box.get(_userIdKey) as String?;
    if (storedUserId == null) {
      box.put(_userIdKey, currentUserId);
      return;
    }

    if (storedUserId == currentUserId) return;

    final now = DateTime.now();
    box.put(_userIdKey, currentUserId);
    box.put(_monthlyUsedKey, 0);
    box.put(_dailyUsedKey, 0);
    box.put(_monthlyResetAtKey, now.toIso8601String());
    box.put(_dailyResetAtKey, _getNextMidnight().toIso8601String());
    box.put(_tierKey, SubscriptionTierHelper.free);
    box.put(_monthlyLimitKey, AppConstants.freeMonthlyLimit);
    box.put(_dailyLimitKey, AppConstants.freeDailyLimit);
    _clearLastKnownPaidSnapshot(box);
  }

  static int _defaultMonthlyLimitForTier(String tier) {
    return SubscriptionTierHelper.limitsFor(tier).monthly;
  }

  static int _defaultDailyLimitForTier(String tier) {
    return SubscriptionTierHelper.limitsFor(tier).daily;
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  static void _writeLastKnownPaidSnapshot(
    Box box, {
    required String tier,
    required int monthlyLimit,
    required int dailyLimit,
    DateTime? expiresAt,
  }) {
    final currentUserId = _currentUserId;
    if (currentUserId == null || currentUserId.isEmpty) {
      return;
    }

    final normalizedTier = SubscriptionTierHelper.normalizeTier(tier);
    final now = DateTime.now().toUtc();
    final normalizedExpiresAt = expiresAt?.toUtc();
    if (normalizedExpiresAt == null || !normalizedExpiresAt.isAfter(now)) {
      final existingUserId = box.get(_lastKnownPaidUserIdKey) as String?;
      final existingTier = SubscriptionTierHelper.normalizeTier(
        box.get(_lastKnownPaidTierKey) as String?,
      );
      final existingExpiresAt = _parseDateTime(
        box.get(_lastKnownPaidExpiresAtKey),
      );
      final existingSnapshotStillValid = existingUserId == currentUserId &&
          existingTier != SubscriptionTierHelper.free &&
          existingExpiresAt != null &&
          existingExpiresAt.toUtc().isAfter(now);

      if (!existingSnapshotStillValid) {
        _clearLastKnownPaidSnapshot(box);
      }
      return;
    }

    box.put(_lastKnownPaidUserIdKey, currentUserId);
    box.put(_lastKnownPaidTierKey, normalizedTier);
    box.put(_lastKnownPaidMonthlyLimitKey, monthlyLimit);
    box.put(_lastKnownPaidDailyLimitKey, dailyLimit);
    box.put(_lastKnownPaidExpiresAtKey, normalizedExpiresAt.toIso8601String());
  }

  static void _clearLastKnownPaidSnapshot(Box box) {
    box.delete(_lastKnownPaidTierKey);
    box.delete(_lastKnownPaidMonthlyLimitKey);
    box.delete(_lastKnownPaidDailyLimitKey);
    box.delete(_lastKnownPaidExpiresAtKey);
    box.delete(_lastKnownPaidUserIdKey);
  }

  static _LastKnownPaidSnapshot? _readLastKnownPaidSnapshot(
    Box box, {
    required DateTime now,
  }) {
    final currentUserId = _currentUserId;
    if (currentUserId == null || currentUserId.isEmpty) {
      return null;
    }

    final snapshotUserId = box.get(_lastKnownPaidUserIdKey) as String?;
    if (snapshotUserId != currentUserId) {
      return null;
    }

    final tier = SubscriptionTierHelper.normalizeTier(
      box.get(_lastKnownPaidTierKey) as String?,
    );
    if (tier == SubscriptionTierHelper.free) {
      return null;
    }

    final expiresAt = _parseDateTime(box.get(_lastKnownPaidExpiresAtKey));
    if (expiresAt == null || !expiresAt.toUtc().isAfter(now.toUtc())) {
      return null;
    }

    final limits = SubscriptionTierHelper.limitsFor(tier);
    return _LastKnownPaidSnapshot(
      tier: tier,
      monthlyLimit:
          box.get(_lastKnownPaidMonthlyLimitKey) as int? ?? limits.monthly,
      dailyLimit: box.get(_lastKnownPaidDailyLimitKey) as int? ?? limits.daily,
    );
  }

  /// Get current usage data (local cache)
  UsageData getLocalUsage() {
    final box = StorageService.usageBox;
    _resetSnapshotIfAccountChanged();
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
      if (now.month != monthlyResetAt.month ||
          now.year != monthlyResetAt.year) {
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

    final storedTier = SubscriptionTierHelper.normalizeTier(
      box.get(_tierKey) as String?,
    );
    final paidSnapshot = _readLastKnownPaidSnapshot(box, now: now);
    final shouldRestorePaidSnapshot =
        storedTier == SubscriptionTierHelper.free && paidSnapshot != null;
    final tier = shouldRestorePaidSnapshot ? paidSnapshot.tier : storedTier;
    final monthlyLimit = shouldRestorePaidSnapshot
        ? paidSnapshot.monthlyLimit
        : box.get(_monthlyLimitKey) as int? ??
            _defaultMonthlyLimitForTier(tier);
    final dailyLimit = shouldRestorePaidSnapshot
        ? paidSnapshot.dailyLimit
        : box.get(_dailyLimitKey) as int? ?? _defaultDailyLimitForTier(tier);

    if (shouldRestorePaidSnapshot) {
      box.put(_tierKey, tier);
      box.put(_monthlyLimitKey, monthlyLimit);
      box.put(_dailyLimitKey, dailyLimit);
    }

    return UsageData(
      monthlyUsed: monthlyUsed,
      monthlyLimit: monthlyLimit,
      dailyUsed: dailyUsed,
      dailyLimit: dailyLimit,
      dailyResetAt: dailyResetAt,
      tier: tier,
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

class _LastKnownPaidSnapshot {
  const _LastKnownPaidSnapshot({
    required this.tier,
    required this.monthlyLimit,
    required this.dailyLimit,
  });

  final String tier;
  final int monthlyLimit;
  final int dailyLimit;
}
