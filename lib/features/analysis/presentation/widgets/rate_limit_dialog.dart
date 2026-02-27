// lib/features/analysis/presentation/widgets/rate_limit_dialog.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

enum RateLimitType { minute, daily, monthly }

class RateLimitDialog extends StatelessWidget {
  final RateLimitType type;
  final int? retryAfter;

  const RateLimitDialog({
    super.key,
    required this.type,
    this.retryAfter,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_getEmoji(), style: const TextStyle(fontSize: 48)),
          const SizedBox(height: 16),
          Text(_getTitle(), style: AppTypography.headlineMedium),
          const SizedBox(height: 8),
          Text(
            _getMessage(),
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        if (type == RateLimitType.minute)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(retryAfter != null ? '$retryAfter 秒後重試' : '知道了'),
          )
        else ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.push('/paywall');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('升級方案'),
          ),
        ],
      ],
    );
  }

  String _getEmoji() {
    switch (type) {
      case RateLimitType.minute:
        return '⏱️';
      case RateLimitType.daily:
        return '📅';
      case RateLimitType.monthly:
        return '📊';
    }
  }

  String _getTitle() {
    switch (type) {
      case RateLimitType.minute:
        return '請稍後再試';
      case RateLimitType.daily:
        return '今日額度已用完';
      case RateLimitType.monthly:
        return '本月額度已用完';
    }
  }

  String _getMessage() {
    switch (type) {
      case RateLimitType.minute:
        return '為了確保服務品質，請稍等一下再繼續分析';
      case RateLimitType.daily:
        return '今天的分析次數已達上限，明天會重置喔！\n升級方案可獲得更多每日額度';
      case RateLimitType.monthly:
        return '本月的分析次數已達上限\n升級方案或加購訊息包可繼續使用';
    }
  }
}

void showRateLimitDialog(
  BuildContext context,
  RateLimitType type, {
  int? retryAfter,
}) {
  showDialog(
    context: context,
    builder: (context) => RateLimitDialog(type: type, retryAfter: retryAfter),
  );
}

extension RateLimitTypeExtension on String {
  RateLimitType? toRateLimitType() {
    switch (this) {
      case 'minute_limit':
        return RateLimitType.minute;
      case 'daily_limit':
        return RateLimitType.daily;
      case 'monthly_limit':
        return RateLimitType.monthly;
      default:
        return null;
    }
  }
}
