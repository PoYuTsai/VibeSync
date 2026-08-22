// lib/shared/widgets/game_stage_indicator.dart
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../features/analysis/domain/entities/game_stage.dart';

/// 目前互動重點（對象卡互動階段閉環）：五個點只凸顯本次 stage，
/// 不是完成式進度條——premise／qualification／narrative 可反覆切換，
/// close 之後也可以回到其他互動任務，較早的點不得畫成已完成成就。
class GameStageIndicator extends StatelessWidget {
  final GameStage currentStage;
  final GameStageStatus status;
  final String? nextStep;

  /// 伴侶（已是伴侶）的 opening 可見語意固定為「重新連線」，
  /// 不是退回陌生人；由呼叫端依認識情境傳入。
  final bool reconnectWording;

  const GameStageIndicator({
    super.key,
    required this.currentStage,
    this.status = GameStageStatus.normal,
    this.nextStep,
    this.reconnectWording = false,
  });

  String _shortLabel(GameStage stage) {
    switch (stage) {
      case GameStage.opening:
        return reconnectWording ? '重新連線' : '破冰';
      case GameStage.premise:
        return '升溫';
      case GameStage.qualification:
        return '深入';
      case GameStage.narrative:
        return '連結';
      case GameStage.close:
        return '邀約';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.glassWhite,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Text(
                '目前互動重點',
                style: AppTypography.titleMedium.copyWith(
                  color: AppColors.glassTextPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.ctaStart.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
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
          const SizedBox(height: 24),
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
                    fontSize: 12,
                    color: stage == currentStage
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
          // 階段內節奏狀態（維持節奏／互動偏平／可以推進／放慢一點）。
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                Icons.speed_rounded,
                size: 14,
                color: AppColors.glassTextSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                '節奏：${status.label}',
                style: AppTypography.caption.copyWith(
                  color: AppColors.glassTextSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          // Next step description
          if (nextStep != null) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.ctaStart.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(18),
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
              // 只凸顯本次 stage：較早的點不塗成已完成。
              final isCurrent = stage == currentStage;
              final size = isCurrent ? currentCircleSize : circleSize;

              return Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isCurrent ? coralColor : Colors.transparent,
                  border: isCurrent
                      ? null
                      : Border.all(color: greyColor, width: 1.5),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${stageIndex + 1}',
                  style: TextStyle(
                    fontSize: isCurrent ? 14 : 12,
                    fontWeight: FontWeight.w700,
                    color: isCurrent ? Colors.white : greyColor,
                  ),
                ),
              );
            } else {
              // 連接線一律中性：線段不承載「已完成」語意。
              return Expanded(
                child: Container(
                  height: 2,
                  color: greyColor,
                ),
              );
            }
          }),
        );
      },
    );
  }
}
