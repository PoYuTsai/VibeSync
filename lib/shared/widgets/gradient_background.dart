// lib/shared/widgets/gradient_background.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// 溫暖漸層背景 + 動態光球效果 (Phase 3)
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

    // 不同速度的動畫控制器，讓光球運動更自然
    _controller1 = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);

    _controller2 = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat(reverse: true);

    _controller3 = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
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
          // 光球 1 - 右上粉紅
          Positioned(
            top: -50,
            right: -30,
            child: _AnimatedBokehOrb(
              controller: _controller1,
              color: AppColors.bokehPink,
              size: 150,
              blur: 80,
              floatRange: 20,
              breatheScale: 0.15,
            ),
          ),
          // 光球 2 - 左下珊瑚
          Positioned(
            bottom: 100,
            left: -40,
            child: _AnimatedBokehOrb(
              controller: _controller2,
              color: AppColors.bokehCoral,
              size: 120,
              blur: 60,
              floatRange: 25,
              breatheScale: 0.12,
              floatAngle: math.pi / 3, // 不同方向
            ),
          ),
          // 光球 3 - 中右黃色
          Positioned(
            top: screenHeight * 0.4,
            right: -20,
            child: _AnimatedBokehOrb(
              controller: _controller3,
              color: AppColors.bokehYellow,
              size: 100,
              blur: 50,
              floatRange: 15,
              breatheScale: 0.1,
              floatAngle: -math.pi / 4, // 又一個不同方向
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
  final double floatRange; // 浮動範圍（像素）
  final double breatheScale; // 呼吸縮放比例 (0.1 = 10%)
  final double floatAngle; // 浮動方向角度

  const _AnimatedBokehOrb({
    required this.controller,
    required this.color,
    required this.size,
    required this.blur,
    this.floatRange = 20,
    this.breatheScale = 0.1,
    this.floatAngle = 0,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        // 計算浮動位移
        final floatProgress = math.sin(controller.value * math.pi * 2);
        final dx = math.cos(floatAngle) * floatRange * floatProgress;
        final dy = math.sin(floatAngle) * floatRange * floatProgress;

        // 計算呼吸縮放
        final breatheProgress = math.sin(controller.value * math.pi * 2 + math.pi / 2);
        final scale = 1.0 + (breatheScale * breatheProgress);

        return Transform.translate(
          offset: Offset(dx, dy),
          child: Transform.scale(
            scale: scale,
            child: child,
          ),
        );
      },
      child: Container(
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
      ),
    );
  }
}
