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
  bool? _reduceMotion;

  @override
  void initState() {
    super.initState();

    // 更明顯的動畫效果。repeat 在 didChangeDependencies 依 reduced-motion 閘門啟動。
    _controller1 = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    );

    _controller2 = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    );

    _controller3 = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_reduceMotion == reduceMotion) return;
    _reduceMotion = reduceMotion;
    for (final controller in [_controller1, _controller2, _controller3]) {
      if (reduceMotion) {
        // value 0.5 → sin(π)=0：光球停在位移/縮放中點，靜態置中。
        controller
          ..stop()
          ..value = 0.5;
      } else {
        controller.repeat(reverse: true);
      }
    }
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
                  top: -110,
                  right: -90,
                  child: _AnimatedBokehOrb(
                    controller: _controller1,
                    color: AppColors.bokehPink,
                    size: 260,
                    blur: 60,
                    opacity: 0.18,
                    floatRange: 18,
                    floatAngle: math.pi / 4, // 45度方向浮動
                  ),
                ),
                Positioned(
                  bottom: -80,
                  left: -100,
                  child: _AnimatedBokehOrb(
                    controller: _controller2,
                    color: AppColors.bokehCoral,
                    size: 280,
                    blur: 60,
                    opacity: 0.14,
                    floatRange: 14,
                    floatAngle: -math.pi / 3, // -60度方向浮動
                  ),
                ),
                Positioned(
                  top: screenHeight * 0.45,
                  right: -120,
                  child: _AnimatedBokehOrb(
                    controller: _controller3,
                    color: AppColors.bokehYellow,
                    size: 240,
                    blur: 60,
                    opacity: 0.08,
                    floatRange: 12,
                    floatAngle: math.pi / 6, // 30度方向浮動
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
  final double floatRange; // 浮動範圍
  final double floatAngle; // 浮動方向

  const _AnimatedBokehOrb({
    required this.controller,
    required this.color,
    required this.size,
    required this.blur,
    this.opacity = 0.6,
    this.floatRange = 20,
    this.floatAngle = 0,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        // 呼吸縮放 (更明顯: 18%)
        final scale = 1.0 + (0.18 * math.sin(controller.value * math.pi * 2));

        // 浮動位移
        final floatProgress = math.sin(controller.value * math.pi * 2);
        final dx = math.cos(floatAngle) * floatRange * floatProgress;
        final dy = math.sin(floatAngle) * floatRange * floatProgress;

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
