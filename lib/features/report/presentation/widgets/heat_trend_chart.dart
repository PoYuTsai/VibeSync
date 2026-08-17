// lib/features/report/presentation/widgets/heat_trend_chart.dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_motion.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../domain/entities/report_models.dart';
import 'trend_flow_overlay.dart';

/// Heat score trend line chart widget.
///
/// Displays a line chart of heat scores over recent analyses, wrapped in a dark
/// [BrandSurfaceCard] (2026-06-17 BrandKit migration; was the light
/// GlassmorphicContainer). Axis labels / grid / tooltip recolored for dark
/// legibility while the orange ctaStart line accent is kept.
class HeatTrendChart extends StatelessWidget {
  final List<HeatTrendPoint> trendPoints;
  final double averageScore;
  final double scoreDelta;
  final String emptyMessage;
  final String? contextLabel;
  final int? sampleCount;

  const HeatTrendChart({
    super.key,
    required this.trendPoints,
    required this.averageScore,
    required this.scoreDelta,
    this.emptyMessage = '尚無數據',
    this.contextLabel,
    this.sampleCount,
  });

  @override
  Widget build(BuildContext context) {
    return BrandSurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 8),
          Text(
            '只反映這次互動中的文字訊號，不代表關係進度。',
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: AppColors.onBackgroundSecondary.withValues(alpha: 0.78),
            ),
          ),
          const SizedBox(height: 16),
          if (trendPoints.isEmpty)
            _buildEmptyState()
          else if (trendPoints.length == 1)
            _buildSinglePointState(context)
          else
            _buildChart(context),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Header
  // ---------------------------------------------------------------------------

  Widget _buildHeader() {
    final count = sampleCount ?? trendPoints.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '每次互動投入度',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.onBackgroundSecondary.withValues(alpha: 0.78),
              ),
            ),
            const Spacer(),
            if (contextLabel != null && contextLabel!.trim().isNotEmpty)
              Container(
                constraints: const BoxConstraints(maxWidth: 150),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.ctaStart.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: AppColors.ctaStart.withValues(alpha: 0.22),
                  ),
                ),
                child: Text(
                  contextLabel!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ctaStart,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        if (sampleCount != null && count == 0)
          const Text(
            '等待趨勢資料',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${sampleCount == null ? '全部平均' : '近期平均'} ${averageScore.round()}',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              if (sampleCount == null || count >= 2) _buildDeltaBadge(),
            ],
          ),
        if (count > 0) ...[
          const SizedBox(height: 4),
          Text(
            count >= 7 ? '顯示最近 7 次分析' : '已累積 $count 次分析',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.onBackgroundSecondary.withValues(alpha: 0.62),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDeltaBadge() {
    if (scoreDelta == 0) {
      return Text(
        '前後 0',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppColors.onBackgroundSecondary.withValues(alpha: 0.78),
        ),
      );
    }

    final isPositive = scoreDelta > 0;
    final sign = isPositive ? '+' : '';
    final color = isPositive ? AppColors.success : AppColors.error;

    return Text(
      '前後 $sign${scoreDelta.round()}',
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: color,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Empty state
  // ---------------------------------------------------------------------------

  Widget _buildEmptyState() {
    return SizedBox(
      height: 150,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.ctaStart.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(
                Icons.show_chart_rounded,
                color: AppColors.ctaStart.withValues(alpha: 0.88),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              emptyMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: AppColors.onBackgroundSecondary.withValues(alpha: 0.70),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSinglePointState(BuildContext context) {
    final point = trendPoints.single;
    final date = DateFormat('M/dd').format(point.date);
    return SizedBox(
      height: 150,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _OneShotPointRipple(
              key: ValueKey(
                'engagement-single-${point.date.microsecondsSinceEpoch}',
              ),
              color: AppColors.ctaStart,
              motionEnabled: TickerMode.valuesOf(context).enabled &&
                  MediaQuery.maybeOf(context)?.disableAnimations != true,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: AppColors.ctaStart,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '起點 ${point.score} · $date',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '再分析 1 次就能形成趨勢',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.onBackgroundSecondary.withValues(alpha: 0.70),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Chart
  // ---------------------------------------------------------------------------

  Widget _buildChart(BuildContext context) {
    final sorted = List<HeatTrendPoint>.from(trendPoints)
      ..sort((a, b) => a.date.compareTo(b.date));

    final firstDate = sorted.first.date;
    // x＝距首點天數（分鐘精度轉天，同日多點不撞 x）。
    double xOf(DateTime date) =>
        date.difference(firstDate).inMinutes / (24 * 60.0);

    final spots = [
      for (final point in sorted)
        FlSpot(xOf(point.date), point.score.toDouble()),
    ];
    // 全部同一時刻（maxX=0）時 fl_chart 需要 minX<maxX，退 1 天刻度。
    final maxX = spots.last.x <= 0 ? 1.0 : spots.last.x;
    final xPadding = maxX * 0.04;
    final plotMinX = -xPadding;
    final plotMaxX = maxX + xPadding;

    final normalizedPoints = [
      for (final spot in spots)
        Offset(
          (spot.x - plotMinX) / (plotMaxX - plotMinX),
          spot.y / 100,
        ),
    ];
    return SizedBox(
      height: 180,
      child: TrendFlowOverlay(
        points: normalizedPoints,
        padding: const EdgeInsets.fromLTRB(32, 4, 4, 31),
        color: const Color(0xFFFFD2B8),
        glowColor: AppColors.ctaStart,
        flowDuration: const Duration(milliseconds: 900),
        // 進場流 2 圈後淡出停住：讀資料的圖不留永久裝飾動態。
        cycles: 2,
        coreAlpha: 0.82,
        glowAlpha: 0.15,
        dashLength: 12,
        gapLength: 8,
        painterKey: const ValueKey('engagement-trend-signal'),
        child: LineChart(
          LineChartData(
            minX: plotMinX,
            maxX: plotMaxX,
            minY: 0,
            maxY: 100,
            clipData: const FlClipData.all(),
            gridData: _gridData(),
            titlesData: _titlesData(firstDate, maxX),
            borderData: FlBorderData(show: false),
            lineBarsData: [_lineBarData(spots)],
            lineTouchData: _touchData(sorted),
            extraLinesData: ExtraLinesData(
              horizontalLines: [
                HorizontalLine(
                  y: averageScore.clamp(0, 100).toDouble(),
                  color: Colors.white.withValues(alpha: 0.22),
                  strokeWidth: 1,
                  dashArray: [4, 5],
                  label: HorizontalLineLabel(
                    show: true,
                    alignment: Alignment.topRight,
                    padding: const EdgeInsets.only(right: 4, bottom: 3),
                    style: TextStyle(
                      color: AppColors.onBackgroundSecondary
                          .withValues(alpha: 0.58),
                      fontSize: 12,
                    ),
                    labelResolver: (_) => '平均',
                  ),
                ),
              ],
            ),
          ),
          duration: MediaQuery.maybeOf(context)?.disableAnimations == true
              ? Duration.zero
              : AppMotion.chartReveal,
          curve: Curves.easeOutCubic,
        ),
      ),
    );
  }

  LineChartBarData _lineBarData(List<FlSpot> spots) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      curveSmoothness: 0.3,
      color: AppColors.ctaStart,
      barWidth: 2.5,
      isStrokeCapRound: true,
      dotData: FlDotData(
        show: true,
        getDotPainter: (spot, percent, bar, index) {
          final isLatest = index == spots.length - 1;
          return FlDotCirclePainter(
            radius: isLatest ? 5 : 3.5,
            color: isLatest ? AppColors.ctaStart : Colors.white,
            strokeWidth: 2,
            strokeColor: isLatest ? Colors.white : AppColors.ctaStart,
          );
        },
      ),
      belowBarData: BarAreaData(
        show: true,
        color: AppColors.ctaStart.withValues(alpha: 0.1),
      ),
    );
  }

  FlGridData _gridData() {
    return FlGridData(
      show: true,
      drawVerticalLine: false,
      horizontalInterval: 25,
      getDrawingHorizontalLine: (value) {
        return FlLine(
          color: Colors.white.withValues(alpha: 0.10),
          strokeWidth: 0.8,
        );
      },
    );
  }

  FlTitlesData _titlesData(DateTime firstDate, double maxX) {
    final dateFormat = DateFormat('M/dd');
    // 最多 ~5 個日期標籤，避免重疊。
    final bottomInterval = maxX <= 4 ? 1.0 : (maxX / 4).ceilToDouble();

    return FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 32,
          interval: 25,
          getTitlesWidget: (value, meta) {
            // Only show 0, 25, 50, 75, 100
            if (value % 25 != 0) return const SizedBox.shrink();
            return Text(
              value.toInt().toString(),
              style: TextStyle(
                fontSize: 12,
                color: AppColors.onBackgroundSecondary.withValues(alpha: 0.70),
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
            if (value < 0 || value > maxX) return const SizedBox.shrink();
            final date =
                firstDate.add(Duration(minutes: (value * 24 * 60).round()));
            return Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                dateFormat.format(date),
                style: TextStyle(
                  fontSize: 12,
                  color:
                      AppColors.onBackgroundSecondary.withValues(alpha: 0.70),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  LineTouchData _touchData(List<HeatTrendPoint> sorted) {
    return LineTouchData(
      touchTooltipData: LineTouchTooltipData(
        getTooltipColor: (_) => AppColors.brandInk.withValues(alpha: 0.94),
        tooltipRoundedRadius: 8,
        getTooltipItems: (touchedSpots) {
          return touchedSpots.map((spot) {
            final idx = spot.spotIndex;
            final point = idx < sorted.length ? sorted[idx] : null;
            final name = point?.conversationName ?? '';
            final date =
                point == null ? '' : DateFormat('M/dd').format(point.date);
            final suffix = name.trim().isEmpty ? date : '$name · $date';
            return LineTooltipItem(
              '${spot.y.toInt()}\n$suffix',
              const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            );
          }).toList();
        },
      ),
      handleBuiltInTouches: true,
    );
  }
}

class _OneShotPointRipple extends StatefulWidget {
  const _OneShotPointRipple({
    super.key,
    required this.color,
    required this.motionEnabled,
    required this.child,
  });

  final Color color;
  final bool motionEnabled;
  final Widget child;

  @override
  State<_OneShotPointRipple> createState() => _OneShotPointRippleState();
}

class _OneShotPointRippleState extends State<_OneShotPointRipple>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 820),
  );

  @override
  void initState() {
    super.initState();
    if (widget.motionEnabled) _controller.forward();
  }

  @override
  void didUpdateWidget(covariant _OneShotPointRipple oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.motionEnabled) {
      _controller
        ..stop()
        ..value = 1;
    } else if (!oldWidget.motionEnabled) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final progress = Curves.easeOutCubic.transform(_controller.value);
              return Container(
                width: 16 + (22 * progress),
                height: 16 + (22 * progress),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: widget.color.withValues(
                      alpha: 0.28 * (1 - progress),
                    ),
                  ),
                ),
              );
            },
          ),
          widget.child,
        ],
      ),
    );
  }
}
