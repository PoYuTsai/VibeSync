import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';

/// 學習 tab 最上方入口：AI 實戰練習室。
class PracticeRoomEntryCard extends StatelessWidget {
  const PracticeRoomEntryCard({super.key});

  @override
  Widget build(BuildContext context) {
    return BrandSurfaceCard(
      elevated: true,
      padding: const EdgeInsets.all(16),
      onTap: () => context.push('/practice-chat'),
      child: Row(
        children: [
          const BrandIconBadge(icon: Icons.forum_outlined, size: 44, iconSize: 24),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'AI 實戰練習室',
                      style: AppTypography.titleMedium.copyWith(
                        color: AppColors.onBackgroundPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.ctaStart.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'NEW',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.ctaStart,
                          fontWeight: FontWeight.w700,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '跟模擬對象直接聊天，練你的真實反應。',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.onBackgroundSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right,
            color: AppColors.onBackgroundSecondary,
          ),
        ],
      ),
    );
  }
}
