import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 在既有趨勢線上疊一段會流動的短亮帶。
///
/// 動畫完成後以 [Timer] 長時間停頓，不會在靜止期間持續逐幀重繪。
/// 系統開啟 reduced motion 或所在頁面的 TickerMode 關閉時完全靜止。
class TrendFlowOverlay extends StatefulWidget {
  const TrendFlowOverlay({
    super.key,
    required this.points,
    required this.padding,
    required this.color,
    required this.glowColor,
    required this.activeDuration,
    required this.pauseDuration,
    required this.child,
    this.painterKey,
    this.coreAlpha = 0.68,
    this.glowAlpha = 0.14,
    this.tailFraction = 0.18,
  })  : assert(coreAlpha >= 0 && coreAlpha <= 1),
        assert(glowAlpha >= 0 && glowAlpha <= 1),
        assert(tailFraction > 0 && tailFraction < 1);

  final List<Offset> points;
  final EdgeInsets padding;
  final Color color;
  final Color glowColor;
  final Duration activeDuration;
  final Duration pauseDuration;
  final Widget child;
  final Key? painterKey;
  final double coreAlpha;
  final double glowAlpha;
  final double tailFraction;

  @override
  State<TrendFlowOverlay> createState() => _TrendFlowOverlayState();
}

class _TrendFlowOverlayState extends State<TrendFlowOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.activeDuration,
  )..addStatusListener(_handleStatus);

  Timer? _pauseTimer;
  bool? _motionEnabled;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final enabled = TickerMode.valuesOf(context).enabled && !reduceMotion;
    if (_motionEnabled == enabled) return;
    _motionEnabled = enabled;

    if (enabled) {
      _playNow();
    } else {
      _pauseTimer?.cancel();
      _controller
        ..stop()
        ..value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant TrendFlowOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeDuration != widget.activeDuration) {
      _controller.duration = widget.activeDuration;
    }
    if (!_samePoints(oldWidget.points, widget.points) &&
        _motionEnabled == true) {
      _playNow();
    }
  }

  void _handleStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || _motionEnabled != true) return;
    _pauseTimer?.cancel();
    _pauseTimer = Timer(widget.pauseDuration, () {
      if (mounted && _motionEnabled == true) {
        _controller.forward(from: 0);
      }
    });
  }

  void _playNow() {
    _pauseTimer?.cancel();
    _controller.forward(from: 0);
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
    _pauseTimer?.cancel();
    _controller
      ..removeStatusListener(_handleStatus)
      ..dispose();
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
                  coreAlpha: widget.coreAlpha,
                  glowAlpha: widget.glowAlpha,
                  tailFraction: widget.tailFraction,
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
    required this.coreAlpha,
    required this.glowAlpha,
    required this.tailFraction,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final List<Offset> points;
  final EdgeInsets padding;
  final Color color;
  final Color glowColor;
  final double coreAlpha;
  final double glowAlpha;
  final double tailFraction;

  @override
  void paint(Canvas canvas, Size size) {
    final raw = animation.value;
    if (points.length < 2 || raw <= 0 || raw >= 1 || size.isEmpty) return;

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
    final progress = Curves.easeInOutCubic.transform(raw);
    final headDistance = metric.length * progress;
    final tailLength = metric.length * tailFraction;
    final tailStart = math.max(0.0, headDistance - tailLength);
    if (headDistance <= tailStart) return;

    final fullTail = metric.extractPath(tailStart, headDistance);
    final midTail = metric.extractPath(
      tailStart + ((headDistance - tailStart) * 0.42),
      headDistance,
    );
    final brightTip = metric.extractPath(
      tailStart + ((headDistance - tailStart) * 0.78),
      headDistance,
    );

    canvas.save();
    canvas.clipRect(plot.inflate(7));
    canvas.drawPath(
      fullTail,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = glowColor.withValues(alpha: glowAlpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawPath(
      midTail,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color.withValues(alpha: coreAlpha * 0.46),
    );
    canvas.drawPath(
      brightTip,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color.withValues(alpha: coreAlpha),
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
        oldDelegate.coreAlpha != coreAlpha ||
        oldDelegate.glowAlpha != glowAlpha ||
        oldDelegate.tailFraction != tailFraction;
  }
}
