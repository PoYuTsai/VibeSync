// lib/shared/widgets/enthusiasm_gauge.dart
import 'package:flutter/material.dart';
import '../../core/services/app_haptics.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_typography.dart';
import '../../features/analysis/domain/entities/enthusiasm_level.dart';

/// 熱度計。分數用 0→score 的 count-up 揭曉，每跳一格給節流後的細碎觸覺
/// （Duolingo 的「累積感」）；reduce-motion 直接停在終點、不連發 tick。
class EnthusiasmGauge extends StatefulWidget {
  final int score;

  const EnthusiasmGauge({super.key, required this.score});

  @override
  State<EnthusiasmGauge> createState() => _EnthusiasmGaugeState();
}

class _EnthusiasmGaugeState extends State<EnthusiasmGauge> {
  int _lastShown = 0;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final level = EnthusiasmLevel.fromScore(widget.score);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.glassWhite,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: widget.score.toDouble()),
        duration:
            reduceMotion ? Duration.zero : const Duration(milliseconds: 900),
        curve: AppMotion.easeOut,
        builder: (context, value, _) {
          final shown = value.round();
          if (shown != _lastShown) {
            _lastShown = shown;
            // 跟著數字跳動出聲；tick 自帶 70ms 節流，不會變嗡嗡。
            if (!reduceMotion) AppHaptics.tick();
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(level.icon, size: 24, color: level.color),
                  const SizedBox(width: 8),
                  Text(
                    '$shown/100',
                    style: AppTypography.headlineMedium
                        .copyWith(color: AppColors.glassTextPrimary),
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
                  value: value / 100,
                  backgroundColor: AppColors.glassBorder,
                  valueColor: AlwaysStoppedAnimation(level.color),
                  minHeight: 8,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
