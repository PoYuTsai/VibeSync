// lib/features/report/presentation/widgets/heat_trend_chart.dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../domain/entities/report_models.dart';

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

  const HeatTrendChart({
    super.key,
    required this.trendPoints,
    required this.averageScore,
    required this.scoreDelta,
  });

  @override
  Widget build(BuildContext context) {
    return BrandSurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 16),
          trendPoints.isEmpty ? _buildEmptyState() : _buildChart(),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Header
  // ---------------------------------------------------------------------------

  Widget _buildHeader() {
    final now = DateTime.now();
    final monthLabel = '${now.month} \u6708'; // e.g. "4 月"

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left: label + average + delta
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '\u71B1\u5EA6\u8DA8\u52E2', // 熱度趨勢
                style: TextStyle(
                  fontSize: 12,
                  color:
                      AppColors.onBackgroundSecondary.withValues(alpha: 0.78),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '\u5E73\u5747 ${averageScore.round()}', // 平均 XX
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildDeltaBadge(),
                ],
              ),
            ],
          ),
        ),

        // Right: month pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.ctaStart,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            monthLabel,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDeltaBadge() {
    if (scoreDelta == 0) {
      return Text(
        '\u2014 0',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.onBackgroundSecondary.withValues(alpha: 0.78),
        ),
      );
    }

    final isPositive = scoreDelta > 0;
    final arrow = isPositive ? '\u2191' : '\u2193'; // ↑ or ↓
    final sign = isPositive ? '+' : '';
    final color = isPositive ? AppColors.success : AppColors.error;

    return Text(
      '$arrow $sign${scoreDelta.round()}',
      style: TextStyle(
        fontSize: 14,
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
      height: 180,
      child: Center(
        child: Text(
          '\u5C1A\u7121\u6578\u64DA', // 尚無數據
          style: TextStyle(
            fontSize: 14,
            color: AppColors.onBackgroundSecondary.withValues(alpha: 0.70),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Chart
  // ---------------------------------------------------------------------------

  Widget _buildChart() {
    final sorted = List<HeatTrendPoint>.from(trendPoints)
      ..sort((a, b) => a.date.compareTo(b.date));

    final firstDate = sorted.first.date;
    // x＝距首點天數（分鐘精度轉天，同日多點不撞 x）。
    double xOf(DateTime date) =>
        date.difference(firstDate).inMinutes / (24 * 60.0);

    final spots = [
      for (final point in sorted) FlSpot(xOf(point.date), point.score.toDouble()),
    ];
    // 全部同一時刻（maxX=0）時 fl_chart 需要 minX<maxX，退 1 天刻度。
    final maxX = spots.last.x <= 0 ? 1.0 : spots.last.x;

    return SizedBox(
      height: 180,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: maxX,
          minY: 0,
          maxY: 100,
          clipData: const FlClipData.all(),
          gridData: _gridData(),
          titlesData: _titlesData(firstDate, maxX),
          borderData: FlBorderData(show: false),
          lineBarsData: [_lineBarData(spots)],
          lineTouchData: _touchData(sorted),
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
          return FlDotCirclePainter(
            radius: 4,
            color: Colors.white,
            strokeWidth: 2,
            strokeColor: AppColors.ctaStart,
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
                fontSize: 10,
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
                  fontSize: 10,
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
            return LineTooltipItem(
              '${spot.y.toInt()}\n$name',
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
