import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/report/presentation/widgets/report_line_chart_axes.dart';

void main() {
  group('序數座標', () {
    test('第 i 筆 x = i；範圍 -0.5 .. N-0.5', () {
      final axes = ReportLineAxes(dates: [
        DateTime(2026, 6, 1),
        DateTime(2026, 6, 1),
        DateTime(2026, 6, 2),
      ]);
      expect(axes.count, 3);
      expect(axes.minX, -0.5);
      expect(axes.maxX, 2.5);
      expect(axes.spots([10, 20, 30]).map((s) => s.x), [0.0, 1.0, 2.0]);
      expect(axes.spots([10, 20, 30]).map((s) => s.y), [10.0, 20.0, 30.0]);
    });

    test('indexForAxisValue：邊界值與非整數不生冒牌 index', () {
      final axes = ReportLineAxes(dates: [
        DateTime(2026, 6, 1),
        DateTime(2026, 6, 2),
        DateTime(2026, 6, 3),
      ]);
      expect(axes.indexForAxisValue(-0.5), isNull);
      expect(axes.indexForAxisValue(1.2), isNull);
      expect(axes.indexForAxisValue(2.5), isNull);
      expect(axes.indexForAxisValue(3), isNull);
      expect(axes.indexForAxisValue(0), 0);
      expect(axes.indexForAxisValue(2.0000000001), 2);
    });
  });

  group('日期候選', () {
    test('同一天多筆只有第一筆是候選', () {
      final axes = ReportLineAxes(dates: [
        DateTime(2026, 6, 1, 9, 0),
        DateTime(2026, 6, 1, 9, 5),
        DateTime(2026, 6, 1, 9, 10),
      ]);
      expect(axes.labelCandidates(), [0]);
    });

    test('跨日：各組第一筆，最後一組改用最後一筆', () {
      final axes = ReportLineAxes(dates: [
        DateTime(2026, 6, 1, 9),
        DateTime(2026, 6, 1, 10),
        DateTime(2026, 6, 3, 9),
        DateTime(2026, 6, 5, 9),
        DateTime(2026, 6, 5, 10),
      ]);
      expect(axes.labelCandidates(), [0, 2, 4]);
    });

    test('跨年：底部帶年份、資料區帶完整年份', () {
      final axes = ReportLineAxes(dates: [
        DateTime(2026, 12, 31, 23, 50),
        DateTime(2027, 1, 1, 0, 10),
      ]);
      expect(axes.spansMultipleYears, isTrue);
      expect(axes.bottomDateText(0), '26/12/31');
      expect(axes.bottomDateText(1), '27/1/01');
      expect(axes.detailDateText(1), '2027/1/01 00:10');
    });

    test('同年：底部 M/dd、資料區 M/dd HH:mm', () {
      final axes = ReportLineAxes(dates: [DateTime(2026, 9, 18, 19, 20)]);
      expect(axes.spansMultipleYears, isFalse);
      expect(axes.bottomDateText(0), '9/18');
      expect(axes.detailDateText(0), '9/18 19:20');
      expect(axes.dateRangeText(), '9/18');
    });
  });

  group('selectLabelIndices 防重疊', () {
    final sevenDays = ReportLineAxes(dates: [
      for (var day = 1; day <= 7; day++) DateTime(2026, 6, day),
    ]);

    test('寬度足夠 → 最早、最新優先，其餘按時間補到上限 5', () {
      final selected = sevenDays.selectLabelIndices(
        plotWidth: 700,
        measureWidth: (_) => 30,
      );
      expect(selected.length, 5);
      expect(selected.first, 0);
      expect(selected.last, 6);
      expect(selected, [0, 1, 2, 3, 6]);
    });

    test('寬度只夠兩端 → 只留最早與最新', () {
      final selected = sevenDays.selectLabelIndices(
        plotWidth: 100,
        measureWidth: (_) => 40,
      );
      expect(selected, [0, 6]);
    });

    test('連兩端都放不下 → 空清單，改用日期範圍文字', () {
      final selected = sevenDays.selectLabelIndices(
        plotWidth: 60,
        measureWidth: (_) => 40,
      );
      expect(selected, isEmpty);
      expect(sevenDays.dateRangeText(), '6/01 – 6/07');
    });


    test('單一候選原始寬度超過 plot → 不因 clamp 被誤判可放', () {
      final axes = ReportLineAxes(dates: [DateTime(2026, 6, 1)]);
      expect(
        axes.selectLabelIndices(
          plotWidth: 60,
          measureWidth: (_) => 100,
        ),
        isEmpty,
      );
      expect(axes.dateRangeText(), '6/01');
    });

    test('全部同一天 → 只有一個標籤', () {
      final axes = ReportLineAxes(dates: [
        DateTime(2026, 6, 1, 9),
        DateTime(2026, 6, 1, 10),
      ]);
      expect(
        axes.selectLabelIndices(plotWidth: 300, measureWidth: (_) => 30),
        [0],
      );
    });

    test('已保留的標籤之間至少相隔 minGap', () {
      final axes = ReportLineAxes(dates: [
        for (var day = 1; day <= 3; day++) DateTime(2026, 6, day),
      ]);
      // 3 格各 40 寬，標籤 30 寬：兩端各佔 [0,30]、[90,120]，中間
      // [45,75] 與兩端間距 15 ≥ 8 → 可放；minGap 20 → 不可放。
      expect(
        axes.selectLabelIndices(plotWidth: 120, measureWidth: (_) => 30),
        [0, 1, 2],
      );
      expect(
        axes.selectLabelIndices(
          plotWidth: 120,
          measureWidth: (_) => 30,
          minGap: 20,
        ),
        [0, 2],
      );
    });
  });
}
