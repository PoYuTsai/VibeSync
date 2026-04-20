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

  static const _stageLabels = ['打開', '前提', '評估', '敘事', '收尾'];

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

  String _shortLabel(GameStage stage) {
    switch (stage) {
      case GameStage.opening:
        return '打開';
      case GameStage.premise:
        return '前提';
      case GameStage.qualification:
        return '評估';
      case GameStage.narrative:
        return '敘事';
      case GameStage.close:
        return '收尾';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.glassWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Text(
                'GAME 階段',
                style: AppTypography.titleMedium.copyWith(
                  color: AppColors.glassTextPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.ctaStart.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '目前・${_shortLabel(currentStage)}',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.ctaStart,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Progress circles with connecting lines
          _buildStageProgress(),
          const SizedBox(height: 8),
          // Labels below circles
          Row(
            children: GameStage.values.map((stage) {
              return Expanded(
                child: Text(
                  _shortLabel(stage),
                  textAlign: TextAlign.center,
                  style: AppTypography.caption.copyWith(
                    fontSize: 10,
                    color: stage.index <= currentStage.index
                        ? AppColors.glassTextPrimary
                        : AppColors.glassTextHint.withValues(alpha: 0.5),
                    fontWeight: stage == currentStage
                        ? FontWeight.w700
                        : FontWeight.normal,
                  ),
                ),
              );
            }).toList(),
          ),
          // Next step description
          if (nextStep != null) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.ctaStart.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lightbulb_outline,
                    size: 16,
                    color: AppColors.ctaStart,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      nextStep!,
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.glassTextPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStageProgress() {
    final stages = GameStage.values;
    const circleSize = 28.0;
    const currentCircleSize = 32.0;
    const coralColor = AppColors.ctaStart;
    final greyColor = AppColors.glassBorder;

    return LayoutBuilder(
      builder: (context, constraints) {
        return Row(
          children: List.generate(stages.length * 2 - 1, (i) {
            // Even indices = circles, odd indices = lines
            if (i.isEven) {
              final stageIndex = i ~/ 2;
              final stage = stages[stageIndex];
              final isCompleted = stage.index < currentStage.index;
              final isCurrent = stage == currentStage;
              final isActive = isCompleted || isCurrent;
              final size = isCurrent ? currentCircleSize : circleSize;

              return Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive ? coralColor : Colors.transparent,
                  border: isActive
                      ? null
                      : Border.all(color: greyColor, width: 1.5),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${stageIndex + 1}',
                  style: TextStyle(
                    fontSize: isCurrent ? 14 : 12,
                    fontWeight: FontWeight.w700,
                    color: isActive ? Colors.white : greyColor,
                  ),
                ),
              );
            } else {
              // Connecting line
              final leftStageIndex = i ~/ 2;
              final isLineActive = leftStageIndex < currentStage.index;

              return Expanded(
                child: Container(
                  height: 2,
                  color: isLineActive ? coralColor : greyColor,
                ),
              );
            }
          }),
        );
      },
    );
  }
}
