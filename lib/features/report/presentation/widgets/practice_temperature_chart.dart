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
    return BrandSurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '練習溫度成長',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.onBackgroundSecondary.withValues(alpha: 0.78),
            ),
          ),
          const SizedBox(height: 16),
          points.length < 2 ? _buildEmptyState() : _buildChart(),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return SizedBox(
      height: 140,
      child: Center(
        child: Text(
          '多完成幾場新手模式練習，這裡會畫出你的升溫能力成長曲線',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: AppColors.onBackgroundSecondary.withValues(alpha: 0.70),
          ),
        ),
      ),
    );
  }

  Widget _buildChart() {
    final sorted = List<HeatTrendPoint>.from(points)
      ..sort((a, b) => a.date.compareTo(b.date));
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
              color: AppColors.ctaStart,
              barWidth: 2.5,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, bar, index) =>
                    FlDotCirclePainter(
                  radius: 4,
                  color: Colors.white,
                  strokeWidth: 2,
                  strokeColor: AppColors.ctaStart,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                color: AppColors.ctaStart.withValues(alpha: 0.1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
