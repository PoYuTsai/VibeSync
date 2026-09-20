// lib/features/report/presentation/widgets/heat_trend_chart.dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../../analysis/domain/entities/enthusiasm_level.dart';
import '../../domain/entities/report_models.dart';
import 'report_line_chart_axes.dart';
import 'report_ordinal_line_chart.dart';

/// 單一對象的「每次互動投入度」折線圖。
///
/// 平均、較上次差值、筆數全部由本 widget 從 [trendPoints] 自己算（同一份
/// 最近七筆視窗），呼叫端不再傳入可能與點列不一致的統計值。x 是紀錄順序
/// 軸，不是真實時間。dark BrandKit 卡面沿用 2026-06-17 遷移。
class HeatTrendChart extends StatelessWidget {
  final List<HeatTrendPoint> trendPoints;

  /// 對象身分；切換時所選點直接改為新對象最新一筆。不以顯示名稱當身分。
  final String? subjectId;
  final String? contextLabel;
  final String emptyMessage;

  const HeatTrendChart({
    super.key,
    required this.trendPoints,
    this.subjectId,
    this.contextLabel,
    this.emptyMessage = '尚無這位對象的分析紀錄',
  });

  @override
  Widget build(BuildContext context) {
    // 先套可見上限 90 再算摘要：平均、較上次、圖點來自同一份已 clamp 的視窗。
    final summary = HeatTrendSummary.fromPoints([
      for (final point in trendPoints)
        HeatTrendPoint(
          date: point.date,
          score: clampVisibleInvestmentScore(point.score),
          conversationName: point.conversationName,
          eventId: point.eventId,
          practiceContext: point.practiceContext,
        ),
    ]);
    return BrandSurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(summary),
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
          if (summary.points.isEmpty)
            _buildEmptyState()
          else if (summary.points.length == 1)
            _buildSinglePointState(context, summary.points.single)
          else
            _buildChart(summary),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Header
  // ---------------------------------------------------------------------------

  Widget _buildHeader(HeatTrendSummary summary) {
    final count = summary.sampleCount;

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
        // 零筆不顯示平均 0 或差值 0：「沒有資料」不能用 0 代替。
        if (count > 0) ...[
          const SizedBox(height: 6),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 8,
            runSpacing: 2,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '這 $count 次平均 ',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    TextSpan(
                      text: '${summary.averageScore.round()}',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    TextSpan(
                      text: ' / ${AppConstants.investmentVisibleMax}',
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
              if (count >= 2) _buildDeltaText(summary.scoreDelta),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '最近 $count 筆分析',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.onBackgroundSecondary.withValues(alpha: 0.62),
            ),
          ),
        ],
      ],
    );
  }

  /// 「較上次」只比較同一對象最後兩筆；中性色、只用正負號，不加成敗評語。
  Widget _buildDeltaText(double scoreDelta) {
    final rounded = scoreDelta.round();
    final sign = rounded > 0 ? '+' : (rounded < 0 ? '−' : '');
    return Text(
      '較上次 $sign${rounded.abs()}',
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: AppColors.onBackgroundSecondary.withValues(alpha: 0.82),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Empty / single
  // ---------------------------------------------------------------------------

  Widget _buildEmptyState() {
    // minHeight 而非鎖死高：大字級（clamp 上限 1.4）＋窄機身時文案比
    // 保留高度高，鎖死會溢出疊到卡片上方的註解行（dogfood 疊字系列）。
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 150),
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

  Widget _buildSinglePointState(BuildContext context, HeatTrendPoint point) {
    final visibleScore = point.score;
    final axes = ReportLineAxes(dates: [point.date]);
    // minHeight 而非鎖死高：理由同空態。
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 150),
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
              '投入度 $visibleScore · ${axes.detailDateText(0)}',
              textAlign: TextAlign.center,
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

  Widget _buildChart(HeatTrendSummary summary) {
    final maxY = AppConstants.investmentVisibleMax.toDouble();
    final count = summary.sampleCount;
    return ReportOrdinalLineChart(
      key: const ValueKey('engagement-ordinal-chart'),
      points: summary.points,
      maxY: maxY,
      // 滿分 90 的尺度：0、30、60、90 對齊投入度分段邊界。
      yInterval: 30,
      lineColor: AppColors.ctaStart,
      dotColorOf: (_) => AppColors.ctaStart,
      selectionScope: subjectId,
      // 平均線的說明放圖註而不是圖內：圖內標籤會壓到靠近平均的資料點。
      note: '虛線是這 $count 次平均。按分析先後排列，點一下查看那次資料。',
      extraLinesData: ExtraLinesData(
        horizontalLines: [
          HorizontalLine(
            // 虛線用未捨入的平均；主數字用 round()，差距不超過半分。
            y: summary.averageScore.clamp(0, maxY).toDouble(),
            color: Colors.white.withValues(alpha: 0.22),
            strokeWidth: 1,
            dashArray: [4, 5],
          ),
        ],
      ),
      detailLinesOf: (point, index, axes) => [
        '投入度 ${point.score} / ${AppConstants.investmentVisibleMax}',
      ],
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
