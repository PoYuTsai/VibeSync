import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../domain/entities/new_topic_result.dart';

/// 一張新話題卡（計畫 §13.6）：縱向排版，不沿用 opener 220px 橫向固定高。
/// 複製只複製 openingLine——whyItWorks/nextMove 是教練講解，不是可貼文字。
class NewTopicIdeaCard extends StatelessWidget {
  const NewTopicIdeaCard({
    super.key,
    required this.idea,
    required this.isRecommended,
    required this.onCopyOpeningLine,
  });

  final NewTopicIdea idea;
  final bool isRecommended;
  final VoidCallback onCopyOpeningLine;

  @override
  Widget build(BuildContext context) {
    return BrandSurfaceCard(
      key: ValueKey('new-topic-idea-card-${idea.id}'),
      tone: BrandVisualTone.coach,
      borderColor: isRecommended
          ? AppColors.coachRecommendation.withValues(alpha: 0.58)
          : null,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  idea.direction,
                  style: AppTypography.titleMedium.copyWith(
                    color: AppColors.onBackgroundPrimary,
                  ),
                ),
              ),
              if (isRecommended)
                Container(
                  key: ValueKey('new-topic-recommendation-${idea.id}'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.coachRecommendation.withValues(
                      alpha: 0.16,
                    ),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: AppColors.coachRecommendation.withValues(
                        alpha: 0.64,
                      ),
                    ),
                  ),
                  child: Text(
                    'AI 推薦',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.coachRecommendation,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // 可直接傳的第一句
          Container(
            key: ValueKey('new-topic-opening-line-${idea.id}'),
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.coachBackgroundMid.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.coachAccent.withValues(alpha: 0.18),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '可直接傳',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.onBackgroundSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  idea.openingLine,
                  style: AppTypography.bodyMedium.copyWith(
                    color: Colors.white,
                    height: 1.5,
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: onCopyOpeningLine,
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('複製'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.ctaStart,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          _section('為什麼現在有效', idea.whyItWorks),
          const SizedBox(height: 10),
          _section('接下來怎麼延續', idea.nextMove),
        ],
      ),
    );
  }

  Widget _section(String title, String body) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.coachAccentBright.withValues(alpha: 0.92),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          body,
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.onBackgroundPrimary,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}
