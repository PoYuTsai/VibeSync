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
                  '對方這次的投入度',
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
                const SizedBox(height: 4),
                Text(
                  '只反映這次互動中的文字訊號，不代表關係進度。',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.glassTextSecondary,
                    height: 1.3,
                  ),
                ),
                if (delta != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    delta >= 0 ? '較上次 +$delta，只比較兩次互動' : '較上次 $delta，只比較兩次互動',
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
        return '這次投入訊號偏少';
      case EnthusiasmLevel.warm:
        return '這次有一定回應';
      case EnthusiasmLevel.hot:
        return '這次投入訊號明顯';
      case EnthusiasmLevel.veryHot:
        return '這次投入訊號很多';
    }
  }
}
