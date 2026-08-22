import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_typography.dart';

/// 「正在重新產生完整分析」進度橫幅（升級後刷新回覆選項時顯示）。
class PremiumRefreshBanner extends StatelessWidget {
  const PremiumRefreshBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.ctaStart.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.ctaStart.withValues(alpha: 0.28),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '正在重新產生完整分析，完成後會更新新版回覆選項。',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.ctaStart,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 冰點放棄建議橫幅（shouldGiveUp）。
class GiveUpAdviceBanner extends StatelessWidget {
  const GiveUpAdviceBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(TablerIcons.alert_triangle,
              size: 20, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '這段互動目前不建議再投入，先保護自己的時間與情緒成本。',
              style: AppTypography.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// 一致性提醒橫幅。
class ReminderBanner extends StatelessWidget {
  const ReminderBanner({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(TablerIcons.message_circle,
              size: 18, color: AppColors.info),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: AppTypography.bodyMedium.copyWith(
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
