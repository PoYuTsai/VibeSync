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
/// 的開場→升溫能力，跨對象看斜率才是成長曲線）。<2 點顯示引導文案。
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
      glowRadius: 8,
      strength: 0.20,
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
            summary.points.length < 2
                ? _buildEmptyState()
                : _buildChart(context, summary),
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
              child: _LiquidTrendGlow(
                key: const ValueKey('practice-growth-empty-glow'),
                points: const [
                  Offset(0.06, 0.18),
                  Offset(0.26, 0.48),
                  Offset(0.45, 0.35),
                  Offset(0.68, 0.72),
                  Offset(0.94, 0.82),
                ],
                showPath: true,
                padding: const EdgeInsets.all(4),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                  ),
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
    final dateFormat = DateFormat('M/dd');
    final bottomInterval = maxX <= 4 ? 1.0 : (maxX / 4).ceilToDouble();
    final normalizedPoints = [
      for (final spot in spots) Offset(spot.x / maxX, spot.y / 100),
    ];

    return SizedBox(
      height: 160,
      child: _LiquidTrendGlow(
        key: const ValueKey('practice-growth-trend-glow'),
        points: normalizedPoints,
        padding: const EdgeInsets.fromLTRB(34, 8, 8, 30),
        child: LineChart(
          LineChartData(
            minX: 0,
            maxX: maxX,
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

/// 在成長線上移動的小型流光訊號。只重繪 overlay，底下的 fl_chart 不會跟著
/// 每幀 rebuild；reduced motion / TickerMode 關閉時停在靜態位置。
class _LiquidTrendGlow extends StatefulWidget {
  const _LiquidTrendGlow({
    super.key,
    required this.points,
    required this.child,
    required this.padding,
    this.showPath = false,
  });

  final List<Offset> points;
  final Widget child;
  final EdgeInsets padding;
  final bool showPath;

  @override
  State<_LiquidTrendGlow> createState() => _LiquidTrendGlowState();
}

class _LiquidTrendGlowState extends State<_LiquidTrendGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 5200),
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
        ..value = 0.68;
    }
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
                  animation: _controller,
                  points: widget.points,
                  padding: widget.padding,
                  showPath: widget.showPath,
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
    required this.showPath,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final List<Offset> points;
  final EdgeInsets padding;
  final bool showPath;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2 || size.isEmpty) return;

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
    final path = Path()..moveTo(mapped.first.dx, mapped.first.dy);
    for (final point in mapped.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }

    if (showPath) {
      final pathShader = const LinearGradient(
        colors: [
          AppColors.ctaStart,
          AppColors.brandBlush,
          Color(0xFFFFD2B8),
        ],
      ).createShader(plot);
      final glowPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..shader = pathShader
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
      final linePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..shader = pathShader;
      canvas
        ..drawPath(path, glowPaint)
        ..drawPath(path, linePaint);
    }

    final scaled = animation.value * (mapped.length - 1);
    final index = scaled.floor().clamp(0, mapped.length - 2);
    final localProgress = scaled - index;
    final position = Offset.lerp(
      mapped[index],
      mapped[index + 1],
      localProgress,
    )!;
    final pulse = 0.86 + (math.sin(animation.value * math.pi * 2) * 0.14);

    canvas.drawCircle(
      position,
      7 * pulse,
      Paint()
        ..color = AppColors.brandBlush.withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    canvas.drawCircle(
      position,
      2.8,
      Paint()..color = const Color(0xFFFFD2B8),
    );
  }

  @override
  bool shouldRepaint(covariant _LiquidTrendGlowPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.padding != padding ||
        oldDelegate.showPath != showPath;
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
