import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../../../shared/widgets/brand/liquid_motion_frame.dart';
import '../../../practice_chat/domain/entities/practice_learning_mode.dart';
import '../../../practice_chat/domain/entities/practice_profile.dart';
import '../../../practice_chat/presentation/widgets/practice_temperature_style.dart';
import '../../domain/entities/report_models.dart';
import 'report_line_chart_axes.dart';
import 'report_ordinal_line_chart.dart';

/// 練習溫度紀錄：每筆是一輪練習（一個 practice session）收操時的結束溫度，
/// 依紀錄先後等距排列。刻意不叫「成長曲線」——難度、模式、聊天長度、續玩
/// 都會影響終溫，這裡只呈現紀錄，不推斷能力，也不做較上次的紅綠判斷。
/// 五段溫度帶背景沿用練習室溫度計的 band 邊界與色票。
class PracticeTemperatureChart extends StatelessWidget {
  final List<HeatTrendPoint> points;

  const PracticeTemperatureChart({super.key, required this.points});

  static const _bandAlpha = 0.06;

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
              '每個點是一輪練習的結束溫度，不等於能力評分。',
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
              _buildChart(summary),
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
              '練習溫度紀錄',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.onBackgroundSecondary.withValues(alpha: 0.78),
              ),
            ),
            const Spacer(),
            if (summary.sampleCount > 0)
              Text(
                '最近 ${summary.sampleCount} 筆紀錄',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.primaryLight.withValues(alpha: 0.88),
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
        if (summary.latestScore != null) ...[
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(
                  text: '最近結束溫度 ',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                TextSpan(
                  text: '${summary.latestScore}',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                TextSpan(
                  text: ' / 100',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onBackgroundSecondary
                        .withValues(alpha: 0.72),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildEmptyState() {
    // minHeight 而非鎖死高：大字級（clamp 上限 1.4）＋窄機身時文案比
    // 保留高度高，鎖死會溢出疊到卡片上方的註解行（dogfood 疊字系列）。
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 130),
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
                  borderRadius: BorderRadius.circular(18),
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
              '完成有溫度計的練習並取得拆解卡後，這裡會留下紀錄。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: AppColors.onBackgroundSecondary.withValues(alpha: 0.70),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '包含新手與 Game 模式。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.onBackgroundSecondary.withValues(alpha: 0.62),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSinglePointState(HeatTrendPoint point) {
    final axes = ReportLineAxes(dates: [point.date]);
    final color = practiceTemperatureColor(score: point.score);
    // minHeight 而非鎖死高：理由同空態。
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 130),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              key: const ValueKey('practice-growth-single-point'),
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.26),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '結束溫度 ${point.score} · ${axes.detailDateText(0)}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '再留下 1 筆紀錄，就能一起查看兩次的差別。',
              textAlign: TextAlign.center,
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

  Widget _buildChart(HeatTrendSummary summary) {
    return ReportOrdinalLineChart(
      key: const ValueKey('practice-temperature-ordinal-chart'),
      points: summary.points,
      maxY: 100,
      yInterval: 20,
      lineColor: AppColors.primaryLight,
      dotColorOf: (point) => practiceTemperatureColor(score: point.score),
      rangeAnnotations: temperatureBandAnnotations(),
      detailLinesOf: (point, index, axes) => [
        '結束溫度 ${point.score} / 100 · '
            '${practiceTemperatureBandLabel(score: point.score)}',
        practiceContextLine(point.practiceContext),
      ],
    );
  }

  /// 第三行：`新手 · 一般 · 第 2 輪 · 她回覆 8 次`。未知欄位直接省略，不補
  /// 預設值；全部未知（舊事件）明說沒有保存條件。
  static String practiceContextLine(PracticeRecordContext? context) {
    if (context == null || context.isEmpty) {
      return '這筆舊紀錄沒有保存練習條件';
    }
    final parts = <String>[
      if (context.mode != null)
        PracticeLearningMode.fromWire(context.mode).label,
      if (context.difficulty != null)
        practiceDifficultyLabel(context.difficulty!),
      if (context.roundIndex != null) '第 ${context.roundIndex} 輪',
      if (context.aiReplyCount != null) '她回覆 ${context.aiReplyCount} 次',
    ];
    return parts.join(' · ');
  }

  /// 五段溫度帶背景。分類是整數規則（0–20、21–40…），背景是連續座標
  /// （0–20、20–40…），兩者不混用，不留 20–21 的空隙。取色用各段中點分數。
  static RangeAnnotations temperatureBandAnnotations() {
    const bands = <(double, double, int)>[
      (0, 20, 10),
      (20, 40, 30),
      (40, 60, 50),
      (60, 80, 70),
      (80, 100, 90),
    ];
    return RangeAnnotations(
      horizontalRangeAnnotations: [
        for (final (y1, y2, sample) in bands)
          HorizontalRangeAnnotation(
            y1: y1,
            y2: y2,
            color: practiceTemperatureColor(score: sample)
                .withValues(alpha: _bandAlpha),
          ),
      ],
    );
  }
}
