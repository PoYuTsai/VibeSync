// lib/features/report/presentation/widgets/conversation_comparison_chart.dart

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../features/analysis/domain/entities/enthusiasm_level.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../domain/entities/report_models.dart';

/// Horizontal bar chart comparing conversation heat scores.
///
/// Shows up to 5 conversations sorted from highest to lowest score.
/// Each bar is colored by heat level (cold/warm/hot/veryHot). 2026-06-17
/// BrandKit migration: wrapped in a dark [BrandSurfaceCard] (was the light
/// GlassmorphicContainer); name labels recolored white for dark legibility.
class ConversationComparisonChart extends StatelessWidget {
  final List<ConversationComparison> comparisons;

  const ConversationComparisonChart({
    super.key,
    required this.comparisons,
  });

  @override
  Widget build(BuildContext context) {
    return BrandSurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '最近一次投入度比較',
            style: AppTypography.titleMedium.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '每個對象只取最新一筆；長條越長，代表這次文字投入訊號越多。',
            style: AppTypography.caption.copyWith(
              color: AppColors.onBackgroundSecondary.withValues(alpha: 0.78),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          if (comparisons.isEmpty) _buildEmptyState() else _buildBars(),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(
          '尚無數據',
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.onBackgroundSecondary.withValues(alpha: 0.70),
          ),
        ),
      ),
    );
  }

  Widget _buildBars() {
    // Sort descending by score, take top 5
    final sorted = List<ConversationComparison>.from(comparisons)
      ..sort((a, b) => b.score.compareTo(a.score));
    final display = sorted.take(5).toList();

    return Column(
      children: [
        for (int i = 0; i < display.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _ConversationBar(comparison: display[i]),
        ],
      ],
    );
  }
}

class _ConversationBar extends StatelessWidget {
  final ConversationComparison comparison;

  const _ConversationBar({required this.comparison});

  @override
  Widget build(BuildContext context) {
    final score = comparison.score.clamp(0, 100);
    final barColor = EnthusiasmLevel.fromScore(score).color;
    final fraction = score / 100.0;
    final animationDuration =
        MediaQuery.maybeOf(context)?.disableAnimations == true
            ? Duration.zero
            : const Duration(milliseconds: 520);

    return Semantics(
      label: '${comparison.name}，最新投入度 $score 分',
      child: Row(
        children: [
          // Conversation name (fixed width, left-aligned)
          SizedBox(
            width: 72,
            child: Text(
              comparison.name,
              style: AppTypography.bodySmall.copyWith(
                color: Colors.white.withValues(alpha: 0.92),
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          const SizedBox(width: 8),
          // Animated bar
          Expanded(
            child: SizedBox(
              height: 18,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  AnimatedFractionallySizedBox(
                    duration: animationDuration,
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.centerLeft,
                    widthFactor: fraction.clamp(0.04, 1.0).toDouble(),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: barColor,
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: [
                          BoxShadow(
                            color: barColor.withValues(alpha: 0.22),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Score number (fixed width, right-aligned)
          SizedBox(
            width: 32,
            child: Text(
              '$score',
              textAlign: TextAlign.right,
              style: AppTypography.bodySmall.copyWith(
                color: barColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
