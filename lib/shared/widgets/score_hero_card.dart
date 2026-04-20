// lib/shared/widgets/score_hero_card.dart
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../features/analysis/domain/entities/enthusiasm_level.dart';
import 'warm_theme_widgets.dart';

class ScoreHeroCard extends StatelessWidget {
  final int score;
  final int? previousScore;

  const ScoreHeroCard({
    super.key,
    required this.score,
    this.previousScore,
  });

  @override
  Widget build(BuildContext context) {
    final level = EnthusiasmLevel.fromScore(score);
    final delta = previousScore != null ? score - previousScore! : null;

    return GlassmorphicContainer(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          // Circular score ring
          SizedBox(
            width: 80,
            height: 80,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 80,
                  height: 80,
                  child: CircularProgressIndicator(
                    value: score / 100,
                    strokeWidth: 6,
                    backgroundColor: level.color.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation(level.color),
                    strokeCap: StrokeCap.round,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$score',
                      style: AppTypography.headlineLarge.copyWith(
                        color: AppColors.glassTextPrimary,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        height: 1.1,
                      ),
                    ),
                    Text(
                      level.label,
                      style: AppTypography.caption.copyWith(
                        color: level.color,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          // Right side: description
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '對話健康分數',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.ctaStart,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _descriptionForLevel(level),
                  style: AppTypography.titleMedium.copyWith(
                    color: AppColors.glassTextPrimary,
                  ),
                ),
                if (delta != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    delta >= 0
                        ? '較上次 +$delta，建議趁熱推進'
                        : '較上次 $delta，需要調整策略',
                    style: AppTypography.caption.copyWith(
                      color: delta >= 0 ? AppColors.success : AppColors.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _descriptionForLevel(EnthusiasmLevel level) {
    switch (level) {
      case EnthusiasmLevel.cold:
        return '對話偏冷，需要換個方式';
      case EnthusiasmLevel.warm:
        return '溫和互動中，可以加點張力';
      case EnthusiasmLevel.hot:
        return '熱情互動中，持續保持節奏 \u{1F44D}';
      case EnthusiasmLevel.veryHot:
        return '超高熱度！趁熱推進見面 \u{1F525}';
    }
  }
}
