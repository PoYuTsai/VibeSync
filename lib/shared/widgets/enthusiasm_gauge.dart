// lib/shared/widgets/enthusiasm_gauge.dart
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../features/analysis/domain/entities/enthusiasm_level.dart';

class EnthusiasmGauge extends StatelessWidget {
  final int score;

  const EnthusiasmGauge({super.key, required this.score});

  @override
  Widget build(BuildContext context) {
    final level = EnthusiasmLevel.fromScore(score);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(level.emoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 8),
              Text(
                '$score/100',
                style: AppTypography.headlineMedium,
              ),
              const SizedBox(width: 8),
              Text(
                level.label,
                style: AppTypography.bodyLarge.copyWith(color: level.color),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: score / 100,
              backgroundColor: AppColors.surfaceVariant,
              valueColor: AlwaysStoppedAnimation(level.color),
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }
}
