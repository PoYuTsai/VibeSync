import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// 外框光暈的視覺風格。
enum LiquidMotionStyle {
  /// 整圈緩慢流動的蜜桃粉暖光（原始風格，氛圍向）。
  flow,

  /// 兩道亮橘→蜜桃的光束沿邊框對角追跑、拖出漸層尾巴，
  /// 其餘邊框近乎透明——高對比、一眼可見的「torch」焦點風格。
  beam,
}

/// 官網 Liquid Hero 在 App 內的輕量視覺語彙：慢速蜜桃粉流光、局部暖色高光，
/// 以及不影響點擊與語意樹的外框光暈。
///
/// 這個元件只重繪自己的邊框，不會重建 [child]。當系統開啟 reduced motion，
/// 或所在 subtree 的 [TickerMode] 關閉時，會停在靜態漸層。
class LiquidMotionFrame extends StatefulWidget {
  const LiquidMotionFrame({
    super.key,
    required this.child,
    this.shape = BoxShape.rectangle,
    this.style = LiquidMotionStyle.flow,
    this.borderRadius = 24,
    this.borderWidth = 2,
    this.glowRadius = 12,
    this.strength = 1,
    this.phaseOffset = 0,
    this.duration = const Duration(milliseconds: 7200),
  })  : assert(borderRadius >= 0),
        assert(borderWidth > 0),
        assert(glowRadius >= 0),
        assert(strength >= 0 && strength <= 1);

  final Widget child;
  final BoxShape shape;
  final LiquidMotionStyle style;
  final double borderRadius;
  final double borderWidth;
  final double glowRadius;
  final double strength;

  /// 0–1 的週期偏移，讓列表中的多個外框不會完全同步。
  final double phaseOffset;
  final Duration duration;

  @override
  State<LiquidMotionFrame> createState() => _LiquidMotionFrameState();
}

class _LiquidMotionFrameState extends State<LiquidMotionFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  bool? _motionEnabled;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant LiquidMotionFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
      if (_motionEnabled == true) {
        _controller.repeat();
      }
    }
  }

  void _syncMotion() {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final enabled = TickerMode.valuesOf(context).enabled && !reduceMotion;
    if (_motionEnabled == enabled) return;

    _motionEnabled = enabled;
    if (enabled) {
      _controller.repeat();
    } else {
      _controller
        ..stop()
        ..value = 0.18;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.strength == 0) return widget.child;

    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            child!,
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _LiquidMotionFramePainter(
                      progress: (_controller.value + widget.phaseOffset) % 1,
                      shape: widget.shape,
                      style: widget.style,
                      borderRadius: widget.borderRadius,
                      borderWidth: widget.borderWidth,
                      glowRadius: widget.glowRadius,
                      strength: widget.strength,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LiquidMotionFramePainter extends CustomPainter {
  const _LiquidMotionFramePainter({
    required this.progress,
    required this.shape,
    required this.style,
    required this.borderRadius,
    required this.borderWidth,
    required this.glowRadius,
    required this.strength,
  });

  final double progress;
  final BoxShape shape;
  final LiquidMotionStyle style;
  final double borderRadius;
  final double borderWidth;
  final double glowRadius;
  final double strength;

  // beam 光束的頭尾錨點（單一光束佔圓周的比例；第二道固定偏移 0.5）。
  static const double _beamTailStart = 0.08;
  static const double _beamHead = 0.25;
  static const double _beamFrontEdge = 0.26;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final rect = (Offset.zero & size).deflate(borderWidth / 2);
    final rotation = progress * math.pi * 2;

    if (style == LiquidMotionStyle.beam) {
      _paintBeam(canvas, rect, rotation);
      return;
    }

    _paintFlow(canvas, rect, rotation);
  }

  void _paintFlow(Canvas canvas, Rect rect, double rotation) {
    final pulse = 0.88 + (math.sin(rotation) * 0.12);

    final glowGradient = SweepGradient(
      transform: GradientRotation(rotation),
      colors: [
        AppColors.ctaStart.withValues(alpha: 0.05),
        AppColors.brandBlush.withValues(alpha: 0.20 * pulse),
        const Color(0xFFFFD2B8).withValues(alpha: 0.26),
        AppColors.ctaStart.withValues(alpha: 0.10),
        AppColors.bokehYellow.withValues(alpha: 0.18 * pulse),
        AppColors.ctaStart.withValues(alpha: 0.05),
      ],
      stops: const [0, 0.18, 0.31, 0.54, 0.78, 1],
    );
    final strokeGradient = SweepGradient(
      transform: GradientRotation(rotation),
      colors: [
        AppColors.ctaStart.withValues(alpha: 0.34),
        AppColors.brandBlush.withValues(alpha: 0.94),
        const Color(0xFFFFD2B8).withValues(alpha: 0.96),
        AppColors.ctaStart.withValues(alpha: 0.58),
        AppColors.bokehYellow.withValues(alpha: 0.82),
        AppColors.ctaStart.withValues(alpha: 0.34),
      ],
      stops: const [0, 0.18, 0.31, 0.54, 0.78, 1],
    );

    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth + 1.6
      ..shader = glowGradient.createShader(rect)
      ..colorFilter = ColorFilter.mode(
        Colors.white.withValues(alpha: strength),
        BlendMode.modulate,
      )
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowRadius);
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth
      ..strokeCap = StrokeCap.round
      ..shader = strokeGradient.createShader(rect)
      ..colorFilter = ColorFilter.mode(
        Colors.white.withValues(alpha: strength),
        BlendMode.modulate,
      );

    if (shape == BoxShape.circle) {
      canvas
        ..drawOval(rect, glowPaint)
        ..drawOval(rect, strokePaint);
      return;
    }

    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(math.max(0, borderRadius - borderWidth / 2)),
    );
    canvas
      ..drawRRect(rrect, glowPaint)
      ..drawRRect(rrect, strokePaint);
  }

  /// 雙光束：頭亮尾淡、前緣銳利收掉，讓大部分邊框保持透明拉出對比。
  void _paintBeam(Canvas canvas, Rect rect, double rotation) {
    SweepGradient beamGradient({required double headAlpha}) {
      Color tail(double a) => AppColors.ctaStart.withValues(alpha: a);
      final head = const Color(0xFFFFD2B8).withValues(alpha: headAlpha * 0.94);
      final core = const Color(0xFFFFF1E4).withValues(alpha: headAlpha);
      const t = Colors.transparent;
      return SweepGradient(
        transform: GradientRotation(rotation),
        colors: [
          t,
          tail(0),
          head,
          core,
          t,
          tail(0),
          head,
          core,
          t,
          t,
        ],
        stops: const [
          0,
          _beamTailStart,
          _beamHead - 0.015,
          _beamHead,
          _beamFrontEdge,
          0.5 + _beamTailStart,
          0.5 + _beamHead - 0.015,
          0.5 + _beamHead,
          0.5 + _beamFrontEdge,
          1,
        ],
      );
    }

    ColorFilter strengthFilter() => ColorFilter.mode(
          Colors.white.withValues(alpha: strength),
          BlendMode.modulate,
        );

    // 底環微光：暗示光束的軌道，避免透明段看起來像邊框斷掉。
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth
      ..color = AppColors.ctaStart.withValues(alpha: 0.10 * strength);
    // 外溢光暈：比描邊寬一圈再整段模糊，讓光束「照亮」卡片外側。
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth + 9
      ..shader = beamGradient(headAlpha: 0.62).createShader(rect)
      ..colorFilter = strengthFilter()
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowRadius);
    // 光束本體：貼著邊框的高亮描邊。
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth
      ..strokeCap = StrokeCap.round
      ..shader = beamGradient(headAlpha: 1).createShader(rect)
      ..colorFilter = strengthFilter();

    if (shape == BoxShape.circle) {
      canvas
        ..drawOval(rect, trackPaint)
        ..drawOval(rect, glowPaint)
        ..drawOval(rect, strokePaint);
      return;
    }

    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(math.max(0, borderRadius - borderWidth / 2)),
    );
    canvas
      ..drawRRect(rrect, trackPaint)
      ..drawRRect(rrect, glowPaint)
      ..drawRRect(rrect, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _LiquidMotionFramePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.shape != shape ||
        oldDelegate.style != style ||
        oldDelegate.borderRadius != borderRadius ||
        oldDelegate.borderWidth != borderWidth ||
        oldDelegate.glowRadius != glowRadius ||
        oldDelegate.strength != strength;
  }
}
