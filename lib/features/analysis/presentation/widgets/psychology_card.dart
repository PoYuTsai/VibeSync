// lib/features/analysis/presentation/widgets/psychology_card.dart
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../domain/entities/analysis_result.dart';

/// Card showing psychology analysis (subtext, shit test, interest signal)
class PsychologyCard extends StatelessWidget {
  final PsychologyAnalysis psychology;

  const PsychologyCard({super.key, required this.psychology});

  @override
  Widget build(BuildContext context) {
    return BrandSurfaceCard(
      elevated: false,
      borderRadius: 18,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Text('🧠', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Text('她話裡的意思', style: AppTypography.titleMedium),
            ],
          ),
          const SizedBox(height: 12),

          // Subtext analysis
          Text(
            psychology.subtext,
            style: AppTypography.bodyMedium.copyWith(
              height: 1.5,
            ),
          ),

          // Interaction-test alert
          if (psychology.shitTestDetected) ...[
            const SizedBox(height: 12),
            _ShitTestAlert(
              type: psychology.shitTestType,
              suggestion: psychology.shitTestSuggestion,
            ),
          ],

          // Interest / investment signal
          if (psychology.qualificationSignal) ...[
            const SizedBox(height: 12),
            _QualificationSignal(),
          ],
        ],
      ),
    );
  }
}

class _ShitTestAlert extends StatelessWidget {
  final String? type;
  final String? suggestion;

  const _ShitTestAlert({this.type, this.suggestion});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withAlpha(25), // ~0.1 opacity
        borderRadius: BorderRadius.circular(8),
        border:
            Border.all(color: AppColors.warning.withAlpha(77)), // ~0.3 opacity
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                size: 18,
                color: AppColors.warning,
              ),
              const SizedBox(width: 8),
              Text(
                '互動測試訊號',
                style:
                    AppTypography.titleSmall.copyWith(color: AppColors.warning),
              ),
            ],
          ),
          if (type != null) ...[
            const SizedBox(height: 6),
            Text(
              '類型: $type',
              style: AppTypography.caption.copyWith(color: AppColors.warning),
            ),
          ],
          if (suggestion != null) ...[
            const SizedBox(height: 4),
            Text(
              '建議: $suggestion',
              style: AppTypography.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _QualificationSignal extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.success.withAlpha(25), // ~0.1 opacity
        borderRadius: BorderRadius.circular(8),
        border:
            Border.all(color: AppColors.success.withAlpha(77)), // ~0.3 opacity
      ),
      child: Row(
        children: [
          const Icon(Icons.favorite, size: 18, color: AppColors.success),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '她有主動投入訊號',
              style: AppTypography.bodySmall.copyWith(color: AppColors.success),
            ),
          ),
        ],
      ),
    );
  }
}
