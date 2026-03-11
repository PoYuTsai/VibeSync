// lib/shared/widgets/gradient_background.dart
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// 溫暖漸層背景 + 靜態光球效果 (效能優化版)
class GradientBackground extends StatelessWidget {
  final Widget child;

  const GradientBackground({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

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
          // 靜態光球層 - 不需要動畫，效能最佳
          Positioned(
            top: -30,
            right: -20,
            child: _StaticBokehOrb(
              color: AppColors.bokehPink,
              size: 180,
              blur: 70,
              opacity: 0.7,
            ),
          ),
          Positioned(
            bottom: 80,
            left: -30,
            child: _StaticBokehOrb(
              color: AppColors.bokehCoral,
              size: 160,
              blur: 55,
              opacity: 0.65,
            ),
          ),
          Positioned(
            top: screenHeight * 0.45,
            right: -10,
            child: _StaticBokehOrb(
              color: AppColors.bokehYellow,
              size: 140,
              blur: 50,
              opacity: 0.6,
            ),
          ),
          // 主內容
          child,
        ],
      ),
    );
  }
}

/// 靜態光球元件 - 無動畫，效能最佳
class _StaticBokehOrb extends StatelessWidget {
  final Color color;
  final double size;
  final double blur;
  final double opacity;

  const _StaticBokehOrb({
    required this.color,
    required this.size,
    required this.blur,
    this.opacity = 0.6,
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
            color: color.withValues(alpha: opacity),
            blurRadius: blur,
            spreadRadius: blur / 2,
          ),
        ],
      ),
    );
  }
}
