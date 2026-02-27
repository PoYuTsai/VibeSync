// lib/features/analysis/presentation/widgets/psychology_card.dart
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/analysis_result.dart';

/// Card showing psychology analysis (subtext, shit test, qualification signal)
class PsychologyCard extends StatelessWidget {
  final PsychologyAnalysis psychology;

  const PsychologyCard({super.key, required this.psychology});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Text('🧠', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Text('淺溝通解讀', style: AppTypography.titleMedium),
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

          // Shit test alert
          if (psychology.shitTestDetected) ...[
            const SizedBox(height: 12),
            _ShitTestAlert(
              type: psychology.shitTestType,
              suggestion: psychology.shitTestSuggestion,
            ),
          ],

          // Qualification signal
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
        border: Border.all(color: AppColors.warning.withAlpha(77)), // ~0.3 opacity
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
                '偵測到廢測',
                style: AppTypography.titleSmall.copyWith(color: AppColors.warning),
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
        border: Border.all(color: AppColors.success.withAlpha(77)), // ~0.3 opacity
      ),
      child: Row(
        children: [
          const Icon(Icons.favorite, size: 18, color: AppColors.success),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '她在向你證明自己 (Qualification Signal)',
              style: AppTypography.bodySmall.copyWith(color: AppColors.success),
            ),
          ),
        ],
      ),
    );
  }
}
