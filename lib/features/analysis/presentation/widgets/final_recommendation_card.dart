// lib/features/analysis/presentation/widgets/final_recommendation_card.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../domain/entities/analysis_result.dart';

/// Card showing AI's final recommendation with coach-style reasoning.
class FinalRecommendationCard extends StatelessWidget {
  final FinalRecommendation recommendation;

  const FinalRecommendationCard({super.key, required this.recommendation});

  @override
  Widget build(BuildContext context) {
    return BrandSurfaceCard(
      borderRadius: 18,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with pick badge
          Row(
            children: [
              const Text('⭐', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Text('AI 推薦回覆', style: AppTypography.titleLarge),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.ctaStart,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  recommendation.pick,
                  style: AppTypography.caption.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Recommended content
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.brandInk.withValues(alpha: 0.40),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              recommendation.content,
              style: AppTypography.bodyLarge.copyWith(
                height: 1.6,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Why this recommendation
          _InfoRow(
            icon: '📝',
            title: '為什麼推薦',
            content: recommendation.reason,
          ),
          const SizedBox(height: 10),

          // Interaction basis
          _InfoRow(
            icon: '🧠',
            title: '為什麼這樣接',
            content: recommendation.psychology,
          ),
          const SizedBox(height: 16),

          // Copy button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _copyToClipboard(context),
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('複製推薦回覆'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.ctaStart,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _copyToClipboard(BuildContext context) {
    Clipboard.setData(ClipboardData(text: recommendation.content));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已複製到剪貼簿'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String icon;
  final String title;
  final String content;

  const _InfoRow({
    required this.icon,
    required this.title,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(icon, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.onBackgroundSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                content,
                style: AppTypography.bodySmall.copyWith(
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
