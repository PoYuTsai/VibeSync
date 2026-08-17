import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 在既有趨勢線上疊一層往前流動的高對比虛線。
///
/// [cycles] 為 null 時無限循環；給定圈數時只在進場流 N 圈，
/// 最後一圈逐漸淡出後完全停止（資料線本體不受影響）。
/// 系統開啟 reduced motion 或所在頁面的 TickerMode 關閉時完全靜止。
class TrendFlowOverlay extends StatefulWidget {
  const TrendFlowOverlay({
    super.key,
    required this.points,
    required this.padding,
    required this.color,
    required this.glowColor,
    required this.flowDuration,
    required this.child,
    this.painterKey,
    this.cycles,
    this.coreAlpha = 0.68,
    this.glowAlpha = 0.14,
    this.dashLength = 12,
    this.gapLength = 8,
  })  : assert(coreAlpha >= 0 && coreAlpha <= 1),
        assert(glowAlpha >= 0 && glowAlpha <= 1),
        assert(cycles == null || cycles > 0),
        assert(dashLength > 0),
        assert(gapLength > 0);

  final List<Offset> points;
  final EdgeInsets padding;
  final Color color;
  final Color glowColor;
  final Duration flowDuration;
  final Widget child;
  final Key? painterKey;

  /// 流動圈數；null＝無限循環。
  final int? cycles;
  final double coreAlpha;
  final double glowAlpha;
  final double dashLength;
  final double gapLength;

  @override
  State<TrendFlowOverlay> createState() => _TrendFlowOverlayState();
}

class _TrendFlowOverlayState extends State<TrendFlowOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _totalDuration,
  );

  bool? _motionEnabled;

  /// 一次性模式把 N 圈攤在同一條 0→1 時間軸上，painter 再拆相位。
  Duration get _totalDuration => widget.flowDuration * (widget.cycles ?? 1);

  void _play() {
    if (widget.cycles == null) {
      _controller.repeat();
    } else {
      _controller.forward(from: 0);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final enabled = TickerMode.valuesOf(context).enabled && !reduceMotion;
    if (_motionEnabled == enabled) return;
    _motionEnabled = enabled;

    if (enabled) {
      _play();
    } else {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void didUpdateWidget(covariant TrendFlowOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.flowDuration != widget.flowDuration ||
        oldWidget.cycles != widget.cycles) {
      _controller.duration = _totalDuration;
    }
    if (!_samePoints(oldWidget.points, widget.points) &&
        _motionEnabled == true) {
      _play();
    }
  }

  bool _samePoints(List<Offset> before, List<Offset> after) {
    if (before.length != after.length) return false;
    for (var index = 0; index < before.length; index++) {
      if (before[index] != after[index]) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                key: widget.painterKey,
                painter: _TrendFlowPainter(
                  animation: _controller,
                  points: widget.points,
                  padding: widget.padding,
                  color: widget.color,
                  glowColor: widget.glowColor,
                  cycles: widget.cycles,
                  coreAlpha: widget.coreAlpha,
                  glowAlpha: widget.glowAlpha,
                  dashLength: widget.dashLength,
                  gapLength: widget.gapLength,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TrendFlowPainter extends CustomPainter {
  _TrendFlowPainter({
    required this.animation,
    required this.points,
    required this.padding,
    required this.color,
    required this.glowColor,
    required this.cycles,
    required this.coreAlpha,
    required this.glowAlpha,
    required this.dashLength,
    required this.gapLength,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final List<Offset> points;
  final EdgeInsets padding;
  final Color color;
  final Color glowColor;
  final int? cycles;
  final double coreAlpha;
  final double glowAlpha;
  final double dashLength;
  final double gapLength;

  @override
  void paint(Canvas canvas, Size size) {
    final raw = animation.value;
    if (points.length < 2 || raw <= 0 || raw >= 1 || size.isEmpty) return;

    // 一次性模式：0→1 時間軸攤了 N 圈，這裡拆出單圈相位；
    // 最後一圈把透明度線性收到 0，結束時 raw>=1 直接不畫。
    final loops = cycles;
    final double phaseFraction;
    final double fade;
    if (loops == null) {
      phaseFraction = raw;
      fade = 1;
    } else {
      final overall = raw * loops;
      phaseFraction = overall % 1;
      final fadeStart = loops - 1.0;
      fade = overall <= fadeStart ? 1 : (1 - (overall - fadeStart)).clamp(0, 1);
      if (fade <= 0) return;
    }

    final plot = Rect.fromLTRB(
      padding.left,
      padding.top,
      math.max(padding.left, size.width - padding.right),
      math.max(padding.top, size.height - padding.bottom),
    );
    if (plot.isEmpty) return;

    final mapped = [
      for (final point in points)
        Offset(
          plot.left + (point.dx.clamp(0, 1) * plot.width),
          plot.bottom - (point.dy.clamp(0, 1) * plot.height),
        ),
    ];
    final path = _smoothPath(mapped);
    final metrics = path.computeMetrics().toList(growable: false);
    if (metrics.isEmpty || metrics.first.length <= 0) return;

    final metric = metrics.first;
    final patternLength = dashLength + gapLength;
    final phase = phaseFraction * patternLength;
    final dashedPath = Path();
    var distance = -patternLength + phase;
    while (distance < metric.length) {
      final start = math.max(0.0, distance);
      final end = math.min(metric.length, distance + dashLength);
      if (end > start) {
        dashedPath.addPath(metric.extractPath(start, end), Offset.zero);
      }
      distance += patternLength;
    }

    canvas.save();
    canvas.clipRect(plot.inflate(7));
    canvas.drawPath(
      dashedPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = glowColor.withValues(alpha: glowAlpha * fade)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawPath(
      dashedPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.25
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color.withValues(alpha: coreAlpha * fade),
    );
    canvas.restore();
  }

  Path _smoothPath(List<Offset> values) {
    final path = Path()..moveTo(values.first.dx, values.first.dy);
    if (values.length == 2) {
      return path..lineTo(values.last.dx, values.last.dy);
    }

    const tension = 0.56;
    for (var index = 0; index < values.length - 1; index++) {
      final previous = index == 0 ? values[index] : values[index - 1];
      final start = values[index];
      final end = values[index + 1];
      final next =
          index + 2 < values.length ? values[index + 2] : values[index + 1];
      final control1 = start + ((end - previous) * (tension / 6));
      final control2 = end - ((next - start) * (tension / 6));
      path.cubicTo(
        control1.dx,
        control1.dy,
        control2.dx,
        control2.dy,
        end.dx,
        end.dy,
      );
    }
    return path;
  }

  @override
  bool shouldRepaint(covariant _TrendFlowPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.padding != padding ||
        oldDelegate.color != color ||
        oldDelegate.glowColor != glowColor ||
        oldDelegate.cycles != cycles ||
        oldDelegate.coreAlpha != coreAlpha ||
        oldDelegate.glowAlpha != glowAlpha ||
        oldDelegate.dashLength != dashLength ||
        oldDelegate.gapLength != gapLength;
  }
}
