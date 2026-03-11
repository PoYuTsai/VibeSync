// lib/shared/widgets/gradient_background.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// 溫暖漸層背景 + 動態光球效果
class GradientBackground extends StatefulWidget {
  final Widget child;

  const GradientBackground({
    super.key,
    required this.child,
  });

  @override
  State<GradientBackground> createState() => _GradientBackgroundState();
}

class _GradientBackgroundState extends State<GradientBackground>
    with TickerProviderStateMixin {
  late final AnimationController _controller1;
  late final AnimationController _controller2;
  late final AnimationController _controller3;

  @override
  void initState() {
    super.initState();

    // 緩慢動畫，減少 CPU 負擔
    _controller1 = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat(reverse: true);

    _controller2 = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    )..repeat(reverse: true);

    _controller3 = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller1.dispose();
    _controller2.dispose();
    _controller3.dispose();
    super.dispose();
  }

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
          // 光球層 - 用 RepaintBoundary 隔離
          RepaintBoundary(
            child: Stack(
              children: [
                Positioned(
                  top: -30,
                  right: -20,
                  child: _AnimatedBokehOrb(
                    controller: _controller1,
                    color: AppColors.bokehPink,
                    size: 180,
                    blur: 70,
                    opacity: 0.7,
                  ),
                ),
                Positioned(
                  bottom: 80,
                  left: -30,
                  child: _AnimatedBokehOrb(
                    controller: _controller2,
                    color: AppColors.bokehCoral,
                    size: 160,
                    blur: 55,
                    opacity: 0.65,
                  ),
                ),
                Positioned(
                  top: screenHeight * 0.45,
                  right: -10,
                  child: _AnimatedBokehOrb(
                    controller: _controller3,
                    color: AppColors.bokehYellow,
                    size: 140,
                    blur: 50,
                    opacity: 0.6,
                  ),
                ),
              ],
            ),
          ),
          // 主內容
          widget.child,
        ],
      ),
    );
  }
}

/// 動態光球元件
class _AnimatedBokehOrb extends StatelessWidget {
  final AnimationController controller;
  final Color color;
  final double size;
  final double blur;
  final double opacity;

  const _AnimatedBokehOrb({
    required this.controller,
    required this.color,
    required this.size,
    required this.blur,
    this.opacity = 0.6,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        // 緩慢呼吸縮放
        final scale = 1.0 + (0.08 * math.sin(controller.value * math.pi * 2));
        return Transform.scale(
          scale: scale,
          child: child,
        );
      },
      child: Container(
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
      ),
    );
  }
}
