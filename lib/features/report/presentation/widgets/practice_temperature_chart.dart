import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
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
    return BrandSurfaceCard(
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
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.primaryLight.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.fitness_center_rounded,
                size: 20,
                color: AppColors.primaryLight.withValues(alpha: 0.90),
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

    return SizedBox(
      height: 160,
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
    );
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
