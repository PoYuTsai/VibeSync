// lib/features/report/presentation/widgets/report_ordinal_line_chart.dart
//
// 兩張報告折線圖共用的本體：紀錄順序軸（ReportLineAxes）、直線、依分數上色
// 的點、圖下方的所選資料區（ReportChartDetail）。
//
// 設計拍板（2026-09-18 規格）：
// - x 是「第 i 筆」等距排列，不是真實時間；同一天多筆各佔一格。
// - `isCurved: false`：不用平滑曲線推測兩筆之間不存在的數值。
// - 不疊流光、不填色；資料線只畫資料。
// - `FlClipData.none()` + chart box 外留白：0 與滿分是合法點，端點圓圈
//   不能被削成半圓。
// - `duration: Duration.zero`：換對象或視窗移動時，舊點不能被插值成另一筆。
// - 所選狀態以 event id 為主；spotIndex 是當次衍生值。
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/report_models.dart';
import 'report_chart_detail.dart';
import 'report_line_chart_axes.dart';

typedef ReportDetailLinesBuilder = List<String> Function(
  HeatTrendPoint point,
  int index,
  ReportLineAxes axes,
);

class ReportOrdinalLineChart extends StatefulWidget {
  const ReportOrdinalLineChart({
    super.key,
    required this.points,
    required this.maxY,
    required this.yInterval,
    required this.lineColor,
    required this.dotColorOf,
    required this.detailLinesOf,
    this.rangeAnnotations,
    this.extraLinesData,
    this.selectionScope,
    this.note = '按紀錄先後排列，點一下查看那次資料。',
    this.chartHeight = 200,
  }) : assert(points.length >= 2);

  /// 已排序、已取視窗的 2–7 筆。
  final List<HeatTrendPoint> points;
  final double maxY;
  final double yInterval;
  final Color lineColor;
  final Color Function(HeatTrendPoint point) dotColorOf;
  final ReportDetailLinesBuilder detailLinesOf;
  final RangeAnnotations? rangeAnnotations;
  final ExtraLinesData? extraLinesData;

  /// 變動時（例如切換對象）直接改選最新一筆。
  final Object? selectionScope;
  final String note;
  final double chartHeight;

  @override
  State<ReportOrdinalLineChart> createState() => _ReportOrdinalLineChartState();
}

class _ReportOrdinalLineChartState extends State<ReportOrdinalLineChart> {
  /// 所選事件 id；來源沒有 id 時退回 index 追蹤。
  String? _selectedId;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _selectLatest();
  }

  @override
  void didUpdateWidget(covariant ReportOrdinalLineChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectionScope != widget.selectionScope) {
      _selectLatest();
      return;
    }
    // 視窗移動：所選 id 仍在就跟著它；離開視窗選最新。
    final id = _selectedId;
    if (id != null) {
      final found = widget.points.indexWhere((p) => p.eventId == id);
      if (found >= 0) {
        _selectedIndex = found;
        return;
      }
    } else if (_selectedIndex < widget.points.length &&
        _samePointList(oldWidget.points, widget.points)) {
      return;
    }
    _selectLatest();
  }

  bool _samePointList(List<HeatTrendPoint> a, List<HeatTrendPoint> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].date != b[i].date || a[i].score != b[i].score) return false;
    }
    return true;
  }

  void _selectLatest() {
    _selectedIndex = widget.points.length - 1;
    _selectedId = widget.points.last.eventId;
  }

  void _select(int index) {
    if (index < 0 || index >= widget.points.length) return;
    setState(() {
      _selectedIndex = index;
      _selectedId = widget.points[index].eventId;
    });
  }

  @override
  Widget build(BuildContext context) {
    final points = widget.points;
    final axes = ReportLineAxes(dates: [for (final p in points) p.date]);
    final spots = axes.spots([for (final p in points) p.score]);
    final textScaler = MediaQuery.textScalerOf(context);
    final tickStyle = TextStyle(
      fontSize: 12,
      color: AppColors.onBackgroundSecondary.withValues(alpha: 0.70),
    );

    double measureWidth(String text) => _measure(text, tickStyle, textScaler).width;
    double measureHeight(String text) => _measure(text, tickStyle, textScaler).height;

    // 左軸保留寬 = 最寬刻度實際寬 + 8；底軸保留高 = 標籤實際高 + 12。
    final widestTick = widget.maxY.toInt().toString();
    final leftReserved = measureWidth(widestTick) + 8;
    final bottomReserved = measureHeight('0/00') + 12;

    return LayoutBuilder(
      builder: (context, constraints) {
        // chart box 右側留 8 讓最後一點的圓圈完整。
        const rightInset = 8.0;
        final plotWidth = constraints.maxWidth - leftReserved - rightInset;
        final labelIndices = axes.selectLabelIndices(
          plotWidth: plotWidth,
          measureWidth: measureWidth,
        );
        final labelSet = labelIndices.toSet();
        final selected = points[_selectedIndex];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: widget.chartHeight,
              child: Padding(
                // 上緣留 8：滿分點的圓圈不被削。
                padding: const EdgeInsets.only(top: 8, right: rightInset),
                child: LineChart(
                  LineChartData(
                    minX: axes.minX,
                    maxX: axes.maxX,
                    minY: 0,
                    maxY: widget.maxY,
                    clipData: const FlClipData.none(),
                    rangeAnnotations:
                        widget.rangeAnnotations ?? const RangeAnnotations(),
                    extraLinesData:
                        widget.extraLinesData ?? const ExtraLinesData(),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: widget.yInterval,
                      getDrawingHorizontalLine: (value) => FlLine(
                        color: Colors.white.withValues(alpha: 0.10),
                        strokeWidth: 0.8,
                      ),
                    ),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: leftReserved,
                          interval: widget.yInterval,
                          getTitlesWidget: (value, meta) {
                            if (value % widget.yInterval != 0) {
                              return const SizedBox.shrink();
                            }
                            return Text(
                              value.toInt().toString(),
                              style: tickStyle,
                            );
                          },
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: bottomReserved,
                          interval: axes.bottomInterval,
                          getTitlesWidget: (value, meta) {
                            final index = axes.indexForAxisValue(value);
                            if (index == null || !labelSet.contains(index)) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                axes.bottomDateText(index),
                                style: tickStyle,
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
                        isCurved: false,
                        color: widget.lineColor,
                        barWidth: 2.5,
                        isStrokeCapRound: true,
                        belowBarData: BarAreaData(show: false),
                        dotData: FlDotData(
                          show: true,
                          getDotPainter: (spot, percent, bar, index) {
                            final point = points[index];
                            final isLatest = index == points.length - 1;
                            final isSelected = index == _selectedIndex;
                            final color = widget.dotColorOf(point);
                            return FlDotCirclePainter(
                              radius: isSelected ? 6 : (isLatest ? 5 : 3.5),
                              color: color,
                              // 所選：白色外圈；最新：白邊；其他：2px 底色環，
                              // 疊在色帶上仍分得開。
                              strokeWidth: isSelected ? 2.5 : (isLatest ? 2 : 2),
                              strokeColor: isSelected || isLatest
                                  ? Colors.white
                                  : AppColors.brandInk.withValues(alpha: 0.9),
                            );
                          },
                        ),
                      ),
                    ],
                    lineTouchData: LineTouchData(
                      enabled: true,
                      handleBuiltInTouches: false,
                      // fl_chart 折線圖預設只算水平距離：40 px 讓整個欄位都能
                      // 選中該筆，點擊區比 3.5–6 px 的圓點大得多。
                      touchSpotThreshold: 40,
                      touchCallback: (event, response) {
                        if (event is! FlTapUpEvent) return;
                        final hit = response?.lineBarSpots;
                        if (hit == null || hit.isEmpty) return;
                        final spot = hit.first;
                        if (spot.barIndex != 0) return;
                        _select(spot.spotIndex);
                      },
                    ),
                  ),
                  duration: Duration.zero,
                ),
              ),
            ),
            if (labelIndices.isEmpty) ...[
              const SizedBox(height: 4),
              Text(
                axes.dateRangeText(),
                style: tickStyle,
              ),
            ],
            const SizedBox(height: 8),
            Text(
              widget.note,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: AppColors.onBackgroundSecondary.withValues(alpha: 0.62),
              ),
            ),
            const SizedBox(height: 8),
            ReportChartDetail(
              index: _selectedIndex,
              count: points.length,
              lines: [
                '本圖第 ${_selectedIndex + 1} 筆 · '
                    '${axes.detailDateText(_selectedIndex)}',
                ...widget.detailLinesOf(selected, _selectedIndex, axes),
              ],
              accentColor: widget.lineColor,
              onPrevious:
                  _selectedIndex > 0 ? () => _select(_selectedIndex - 1) : null,
              onNext: _selectedIndex < points.length - 1
                  ? () => _select(_selectedIndex + 1)
                  : null,
            ),
          ],
        );
      },
    );
  }

  static Size _measure(String text, TextStyle style, TextScaler scaler) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final size = painter.size;
    painter.dispose();
    return size;
  }
}
