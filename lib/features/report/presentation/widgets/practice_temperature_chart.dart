import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../../../shared/widgets/brand/liquid_motion_frame.dart';
import '../../domain/entities/report_models.dart';

/// 案2：練習溫度成長曲線——practice 歷史事件的 temperatureScore 對
/// createdAt 的全域時間序列（刻意不分對象混排：練習溫度量的是玩家本人
/// 的開場→升溫能力，跨對象看斜率才是成長曲線）。0/1 點分開呈現，
/// 不用示意動畫冒充真實趨勢。
class PracticeTemperatureChart extends StatelessWidget {
  final List<HeatTrendPoint> points;

  const PracticeTemperatureChart({super.key, required this.points});

  @override
  Widget build(BuildContext context) {
    final summary = HeatTrendSummary.fromPoints(points);
    return LiquidMotionFrame(
      key: const ValueKey('practice-growth-liquid-frame'),
      borderRadius: 24,
      borderWidth: 1,
      glowRadius: 6,
      strength: 0.12,
      phaseOffset: 0.37,
      duration: const Duration(milliseconds: 9600),
      child: BrandSurfaceCard(
        borderColor: Colors.transparent,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(summary),
            const SizedBox(height: 8),
            Text(
              '只整理練習室表現，不混入真實對話。',
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: AppColors.onBackgroundSecondary.withValues(alpha: 0.72),
              ),
            ),
            const SizedBox(height: 16),
            if (summary.points.isEmpty)
              _buildEmptyState()
            else if (summary.points.length == 1)
              _buildSinglePointState(summary.points.single)
            else
              _buildChart(context, summary),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(HeatTrendSummary summary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '練習溫度成長',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.onBackgroundSecondary.withValues(alpha: 0.78),
              ),
            ),
            const Spacer(),
            if (summary.sampleCount > 0)
              Text(
                summary.sampleCount >= 7
                    ? '最近 7 場'
                    : '${summary.sampleCount} 場練習',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.primaryLight.withValues(alpha: 0.88),
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
        if (summary.latestScore != null) ...[
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '最新 ${summary.latestScore}',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              if (summary.sampleCount >= 2) ...[
                const SizedBox(width: 8),
                _PracticeDelta(delta: summary.scoreDelta),
              ],
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildEmptyState() {
    return SizedBox(
      height: 130,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 42,
              height: 42,
              child: DecoratedBox(
                key: const ValueKey('practice-growth-empty-state'),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.fitness_center_rounded,
                  size: 20,
                  color: AppColors.primaryLight.withValues(alpha: 0.82),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '多完成幾場新手模式練習，這裡會畫出你的升溫能力成長曲線',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.onBackgroundSecondary.withValues(alpha: 0.70),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSinglePointState(HeatTrendPoint point) {
    return SizedBox(
      height: 130,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              key: const ValueKey('practice-growth-single-point'),
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryLight.withValues(alpha: 0.18),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 13),
            Text(
              '起點 ${point.score} · ${DateFormat('M/dd').format(point.date)}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              '再完成 1 場新手模式練習，就能形成成長曲線',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.onBackgroundSecondary.withValues(alpha: 0.70),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChart(BuildContext context, HeatTrendSummary summary) {
    final sorted = summary.points;
    final firstDate = sorted.first.date;
    double xOf(DateTime date) =>
        date.difference(firstDate).inMinutes / (24 * 60.0);
    final spots = [
      for (final point in sorted)
        FlSpot(xOf(point.date), point.score.toDouble()),
    ];
    final maxX = spots.last.x <= 0 ? 1.0 : spots.last.x;
    final xPadding = maxX * 0.04;
    final plotMinX = -xPadding;
    final plotMaxX = maxX + xPadding;
    final dateFormat = DateFormat('M/dd');
    final bottomInterval = maxX <= 4 ? 1.0 : (maxX / 4).ceilToDouble();
    final normalizedPoints = [
      for (final spot in spots)
        Offset(
          (spot.x - plotMinX) / (plotMaxX - plotMinX),
          spot.y / 100,
        ),
    ];

    return SizedBox(
      height: 160,
      child: _LiquidTrendGlow(
        key: const ValueKey('practice-growth-trend-glow'),
        points: normalizedPoints,
        padding: const EdgeInsets.fromLTRB(34, 8, 8, 30),
        child: LineChart(
          LineChartData(
            minX: plotMinX,
            maxX: plotMaxX,
            minY: 0,
            maxY: 100,
            clipData: const FlClipData.all(),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: 25,
              getDrawingHorizontalLine: (value) => FlLine(
                color: Colors.white.withValues(alpha: 0.10),
                strokeWidth: 0.8,
              ),
            ),
            titlesData: FlTitlesData(
              topTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 32,
                  interval: 25,
                  getTitlesWidget: (value, meta) {
                    if (value % 25 != 0) return const SizedBox.shrink();
                    return Text(
                      value.toInt().toString(),
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.onBackgroundSecondary
                            .withValues(alpha: 0.70),
                      ),
                    );
                  },
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  interval: bottomInterval,
                  getTitlesWidget: (value, meta) {
                    if (value < 0 || value > maxX) {
                      return const SizedBox.shrink();
                    }
                    final date = firstDate
                        .add(Duration(minutes: (value * 24 * 60).round()));
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        dateFormat.format(date),
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.onBackgroundSecondary
                              .withValues(alpha: 0.70),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            borderData: FlBorderData(show: false),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                curveSmoothness: 0.3,
                color: AppColors.primaryLight,
                barWidth: 2.5,
                isStrokeCapRound: true,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (spot, percent, bar, index) =>
                      FlDotCirclePainter(
                    radius: 4,
                    color: index == spots.length - 1
                        ? AppColors.primaryLight
                        : Colors.white,
                    strokeWidth: 2,
                    strokeColor: index == spots.length - 1
                        ? Colors.white
                        : AppColors.primaryLight,
                  ),
                ),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.primaryLight.withValues(alpha: 0.20),
                      AppColors.primaryLight.withValues(alpha: 0.01),
                    ],
                  ),
                ),
              ),
            ],
            lineTouchData: LineTouchData(
              handleBuiltInTouches: true,
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) =>
                    AppColors.brandInk.withValues(alpha: 0.94),
                tooltipRoundedRadius: 8,
                getTooltipItems: (spots) => spots.map((spot) {
                  final point = sorted[spot.spotIndex];
                  return LineTooltipItem(
                    '${spot.y.toInt()}\n${DateFormat('M/dd').format(point.date)}',
                    const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          duration: MediaQuery.maybeOf(context)?.disableAnimations == true
              ? Duration.zero
              : const Duration(milliseconds: 480),
          curve: Curves.easeOutCubic,
        ),
      ),
    );
  }
}

/// 在成長線上移動的小型抵達訊號。每 8 秒只動 2.6 秒，其餘時間完全靜止；
/// 只重繪 overlay，底下的 fl_chart 不會跟著每幀 rebuild。
class _LiquidTrendGlow extends StatefulWidget {
  const _LiquidTrendGlow({
    super.key,
    required this.points,
    required this.child,
    required this.padding,
  });

  final List<Offset> points;
  final Widget child;
  final EdgeInsets padding;

  @override
  State<_LiquidTrendGlow> createState() => _LiquidTrendGlowState();
}

class _LiquidTrendGlowState extends State<_LiquidTrendGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 8000),
  );
  late final Animation<double> _activePhase = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, 0.325),
  );
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
      _controller.repeat();
    } else {
      _controller
        ..stop()
        ..value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant _LiquidTrendGlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_samePoints(oldWidget.points, widget.points)) return;
    if (_motionEnabled == true) {
      _controller.repeat();
    } else {
      _controller.value = 1;
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
                painter: _LiquidTrendGlowPainter(
                  animation: _activePhase,
                  points: widget.points,
                  padding: widget.padding,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LiquidTrendGlowPainter extends CustomPainter {
  _LiquidTrendGlowPainter({
    required this.animation,
    required this.points,
    required this.padding,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final List<Offset> points;
  final EdgeInsets padding;

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
    final pathProgress = const Interval(
      0,
      0.78,
      curve: Curves.easeInOutCubic,
    ).transform(raw);
    final fade = 1 -
        const Interval(
          0.78,
          1,
          curve: Curves.easeOutCubic,
        ).transform(raw);
    final position = _positionAt(mapped, pathProgress);
    final tailStart = _positionAt(
      mapped,
      math.max(0, pathProgress - 0.10),
    );
    final arrival = ((raw - 0.62) / 0.24).clamp(0.0, 1.0).toDouble();
    final pulse = 0.90 + (math.sin(arrival * math.pi) * 0.18);

    canvas.drawLine(
      tailStart,
      position,
      Paint()
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..color = AppColors.primaryLight.withValues(alpha: 0.11 * fade)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawLine(
      tailStart,
      position,
      Paint()
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFD7CEFF).withValues(alpha: 0.40 * fade),
    );
    canvas.drawCircle(
      position,
      7 * pulse,
      Paint()
        ..color = AppColors.primaryLight.withValues(alpha: 0.18 * fade)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(
      position,
      2.8,
      Paint()..color = const Color(0xFFD7CEFF).withValues(alpha: fade),
    );
  }

  Offset _positionAt(List<Offset> points, double progress) {
    final scaled = progress.clamp(0.0, 1.0).toDouble() * (points.length - 1);
    final index = scaled.floor().clamp(0, points.length - 2);
    final localProgress = scaled - index;
    return Offset.lerp(points[index], points[index + 1], localProgress)!;
  }

  @override
  bool shouldRepaint(covariant _LiquidTrendGlowPainter oldDelegate) {
    return oldDelegate.points != points || oldDelegate.padding != padding;
  }
}

class _PracticeDelta extends StatelessWidget {
  const _PracticeDelta({required this.delta});

  final double delta;

  @override
  Widget build(BuildContext context) {
    final rounded = delta.round();
    final color = rounded > 0
        ? AppColors.success
        : rounded < 0
            ? AppColors.error
            : AppColors.onBackgroundSecondary;
    final sign = rounded > 0 ? '+' : '';
    return Text(
      '較上次 $sign$rounded',
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: color,
      ),
    );
  }
}
