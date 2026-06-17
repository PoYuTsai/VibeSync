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
            '對話比較',
            style: AppTypography.titleMedium.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          if (comparisons.isEmpty)
            _buildEmptyState()
          else
            _buildBars(),
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

    return Row(
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              final barWidth = constraints.maxWidth * fraction;
              return Align(
                alignment: Alignment.centerLeft,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOutCubic,
                  width: barWidth.clamp(4.0, constraints.maxWidth),
                  height: 20,
                  decoration: BoxDecoration(
                    color: barColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              );
            },
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
    );
  }
}
