// lib/features/report/presentation/widgets/report_line_chart_axes.dart
//
// 報告折線圖共用的「紀錄順序軸」：第 i 筆的 x = i，等距排列，不是真實時間。
// 練習與分析都是一筆一事件；用真實時間當 x 會把同一天多筆擠成垂直線
// （2026-09-17 dogfood 截圖）。相鄰兩點可能隔 5 分鐘也可能隔 10 天，線的
// 斜率不代表速度。
//
// 責任只有三件：序數座標、合法 index 判斷、日期標籤配置。它接收已整理好的
// 2–7 筆（視窗與排序由 HeatTrendSummary 負責），不碰 provider。
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

class ReportLineAxes {
  ReportLineAxes({required List<DateTime> dates})
      : _localDates = List<DateTime>.unmodifiable(
          dates.map((date) => date.toLocal()),
        );

  /// 顯示用本地時間（排序用原始絕對時間，由呼叫端先排好）。
  final List<DateTime> _localDates;

  int get count => _localDates.length;
  double get minX => -0.5;
  double get maxX => count - 0.5;

  /// 底部日期標籤與 fl_chart 的 interval 都是 1；只對已選的 index 回文字。
  double get bottomInterval => 1;

  /// 資料是否跨年：影響日期格式是否帶年份。
  bool get spansMultipleYears {
    if (_localDates.isEmpty) return false;
    final firstYear = _localDates.first.year;
    return _localDates.any((date) => date.year != firstYear);
  }

  List<FlSpot> spots(List<int> scores) {
    assert(scores.length == count);
    return [
      for (var i = 0; i < scores.length; i++)
        FlSpot(i.toDouble(), scores[i].toDouble()),
    ];
  }

  /// fl_chart 傳給 `getTitlesWidget` 的 value 可能含邊界值（-0.5、N-0.5）或
  /// 插值；只有非常接近整數且在 0..N-1 內才視為資料點。
  int? indexForAxisValue(double value) {
    final rounded = value.round();
    if ((value - rounded).abs() > 1e-6) return null;
    if (rounded < 0 || rounded >= count) return null;
    return rounded;
  }

  DateTime localDateAt(int index) => _localDates[index];

  /// 底部標籤：同年 `M/dd`，跨年 `yy/M/dd`。
  String bottomDateText(int index) {
    final format = spansMultipleYears ? 'yy/M/dd' : 'M/dd';
    return DateFormat(format).format(_localDates[index]);
  }

  /// 選取資料區：同年 `M/dd HH:mm`，跨年 `yyyy/M/dd HH:mm`。
  String detailDateText(int index) {
    final format = spansMultipleYears ? 'yyyy/M/dd HH:mm' : 'M/dd HH:mm';
    return DateFormat(format).format(_localDates[index]);
  }

  /// 整段資料的日期範圍（底部連最早／最新都放不下時的替代文字）。
  String dateRangeText() {
    if (_localDates.isEmpty) return '';
    final first = bottomDateText(0);
    final last = bottomDateText(count - 1);
    return first == last ? first : '$first – $last';
  }

  /// 日期標籤候選：依本地 year/month/day 分組，各組第一個點；最後一組改用
  /// 最後一個點，方便顯示最新日期。全部同一天只留第一點。
  List<int> labelCandidates() {
    if (count == 0) return const [];
    final candidates = <int>[];
    var groupStart = 0;
    for (var i = 1; i <= count; i++) {
      final isNewGroup = i == count || !_sameLocalDay(i - 1, i);
      if (!isNewGroup) continue;
      final isLastGroup = i == count;
      candidates.add(isLastGroup && candidates.isNotEmpty ? i - 1 : groupStart);
      groupStart = i;
    }
    return candidates;
  }

  /// 依實際 plot 寬度挑出不重疊的底部標籤 index。
  ///
  /// [measureWidth] 回傳該文字在目前字級下的 logical px 寬度。規則：
  /// 1. 標籤置中於對應 x；超出左右邊界時移入 plot。
  /// 2. 最早、最新優先；兩者本身就放不下時回空清單（呼叫端改顯示
  ///    [dateRangeText]）。
  /// 3. 其他候選按時間加入，與已保留者至少相隔 [minGap]，總數 ≤ [maxLabels]。
  List<int> selectLabelIndices({
    required double plotWidth,
    required double Function(String text) measureWidth,
    double minGap = 8,
    int maxLabels = 5,
  }) {
    final candidates = labelCandidates();
    if (candidates.isEmpty || plotWidth <= 0) return const [];

    final slotWidth = plotWidth / count;
    ({double left, double right, double rawWidth}) rectFor(int index) {
      final width = measureWidth(bottomDateText(index));
      final center = slotWidth * (index + 0.5);
      var left = center - width / 2;
      var right = center + width / 2;
      if (left < 0) {
        right -= left;
        left = 0;
      }
      if (right > plotWidth) {
        left -= right - plotWidth;
        right = plotWidth;
      }
      return (
        left: math.max(0, left),
        right: math.min(plotWidth, right),
        rawWidth: width,
      );
    }

    bool fits(({double left, double right, double rawWidth}) rect,
        List<({double left, double right, double rawWidth})> kept) {
      // 必須在 clamp 前判斷原始標籤寬度；否則超寬文字被裁進 plot 後，
      // rect.right - rect.left 會看起來剛好等於 plotWidth 而誤判可放。
      if (rect.rawWidth > plotWidth) return false;
      for (final other in kept) {
        final gap = math.max(other.left - rect.right, rect.left - other.right);
        if (gap < minGap) return false;
      }
      return true;
    }

    final selected = <int>[];
    final keptRects = <({double left, double right, double rawWidth})>[];

    final earliest = candidates.first;
    final latest = candidates.last;
    final earliestRect = rectFor(earliest);
    if (!fits(earliestRect, keptRects)) return const [];
    selected.add(earliest);
    keptRects.add(earliestRect);
    if (latest != earliest) {
      final latestRect = rectFor(latest);
      if (!fits(latestRect, keptRects)) return const [];
      selected.add(latest);
      keptRects.add(latestRect);
    }

    for (final index in candidates) {
      if (selected.length >= maxLabels) break;
      if (index == earliest || index == latest) continue;
      final rect = rectFor(index);
      if (!fits(rect, keptRects)) continue;
      selected.add(index);
      keptRects.add(rect);
    }
    selected.sort();
    return selected;
  }

  bool _sameLocalDay(int a, int b) {
    final da = _localDates[a];
    final db = _localDates[b];
    return da.year == db.year && da.month == db.month && da.day == db.day;
  }
}
