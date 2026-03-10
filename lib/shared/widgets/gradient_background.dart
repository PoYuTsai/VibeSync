// lib/shared/widgets/gradient_background.dart
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// 溫暖漸層背景 + 靜態光球效果
class GradientBackground extends StatelessWidget {
  final Widget child;

  const GradientBackground({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.backgroundGradientStart,
            AppColors.backgroundGradientMid,
            AppColors.backgroundGradientEnd,
          ],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
      child: Stack(
        children: [
          // 光球 1 - 右上粉紅
          Positioned(
            top: -50,
            right: -30,
            child: _BokehOrb(
              color: AppColors.bokehPink,
              size: 150,
              blur: 80,
            ),
          ),
          // 光球 2 - 左下珊瑚
          Positioned(
            bottom: 100,
            left: -40,
            child: _BokehOrb(
              color: AppColors.bokehCoral,
              size: 120,
              blur: 60,
            ),
          ),
          // 光球 3 - 中右黃色
          Positioned(
            top: MediaQuery.of(context).size.height * 0.4,
            right: -20,
            child: _BokehOrb(
              color: AppColors.bokehYellow,
              size: 100,
              blur: 50,
            ),
          ),
          // 主內容
          child,
        ],
      ),
    );
  }
}

class _BokehOrb extends StatelessWidget {
  final Color color;
  final double size;
  final double blur;

  const _BokehOrb({
    required this.color,
    required this.size,
    required this.blur,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.6),
            blurRadius: blur,
            spreadRadius: blur / 2,
          ),
        ],
      ),
    );
  }
}
