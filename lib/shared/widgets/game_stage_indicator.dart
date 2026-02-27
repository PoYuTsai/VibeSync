// lib/shared/widgets/game_stage_indicator.dart
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../features/analysis/domain/entities/game_stage.dart';

class GameStageIndicator extends StatelessWidget {
  final GameStage currentStage;
  final GameStageStatus status;
  final String? nextStep;

  const GameStageIndicator({
    super.key,
    required this.currentStage,
    this.status = GameStageStatus.normal,
    this.nextStep,
  });

  Color _getStatusColor() {
    switch (status) {
      case GameStageStatus.normal:
        return AppColors.success;
      case GameStageStatus.stuckFriend:
        return AppColors.warning;
      case GameStageStatus.canAdvance:
        return AppColors.primary;
      case GameStageStatus.shouldRetreat:
        return AppColors.error;
    }
  }

  @override
  Widget build(BuildContext context) {
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
              Text(
                'GAME 階段',
                style: AppTypography.caption,
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getStatusColor().withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  status.label,
                  style: AppTypography.caption.copyWith(
                    color: _getStatusColor(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                currentStage.emoji,
                style: const TextStyle(fontSize: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      currentStage.label,
                      style: AppTypography.headlineMedium,
                    ),
                    Text(
                      currentStage.description,
                      style: AppTypography.caption,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (nextStep != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.lightbulb_outline,
                    size: 16,
                    color: AppColors.warning,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      nextStep!,
                      style: AppTypography.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          _buildStageProgress(),
        ],
      ),
    );
  }

  Widget _buildStageProgress() {
    return Row(
      children: GameStage.values.map((stage) {
        final isActive = stage.index <= currentStage.index;
        final isCurrent = stage == currentStage;

        return Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            child: Column(
              children: [
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppColors.primary
                        : AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  stage.emoji,
                  style: TextStyle(
                    fontSize: isCurrent ? 16 : 12,
                    color: isActive
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
