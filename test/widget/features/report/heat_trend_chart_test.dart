import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/report/domain/entities/report_models.dart';
import 'package:vibesync/features/report/presentation/widgets/heat_trend_chart.dart';

Future<void> _pump(
  WidgetTester tester,
  List<HeatTrendPoint> points, {
  String? subjectId = 's1',
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: SingleChildScrollView(
          child: HeatTrendChart(
            trendPoints: points,
            subjectId: subjectId,
            contextLabel: 'A',
          ),
        ),
      ),
    ),
  ));
  // reduced motion 必須完全靜止，pumpAndSettle 要能收斂。
  await tester.pumpAndSettle();
}

HeatTrendPoint _p(DateTime date, int score, {String? id}) => HeatTrendPoint(
      date: date,
      score: score,
      conversationName: 'A',
      eventId: id,
    );

void main() {
  testWidgets('標題與說明限定為每次互動的文字訊號；零筆不顯示平均或差值', (tester) async {
    await _pump(tester, const []);

    expect(find.text('每次互動投入度'), findsOneWidget);
    expect(
      find.text('只反映這次互動中的文字訊號，不代表關係進度。'),
      findsOneWidget,
    );
    expect(find.textContaining('次平均'), findsNothing);
    expect(find.textContaining('較上次'), findsNothing);
    expect(find.text('尚無這位對象的分析紀錄'), findsOneWidget);
  });

  testWidgets('紀錄順序軸：6/2、6/1、6/5 → 排序後 x = 0, 1, 2', (tester) async {
    await _pump(tester, [
      _p(DateTime(2026, 6, 2), 60),
      _p(DateTime(2026, 6, 1), 50),
      _p(DateTime(2026, 6, 5), 80),
    ]);

    final chart = tester.widget<LineChart>(find.byType(LineChart));
    final bar = chart.data.lineBarsData.single;
    expect(bar.spots.map((s) => s.x), [0.0, 1.0, 2.0]); // 等距，不反映真實間隔
    expect(bar.spots.map((s) => s.y), [50.0, 60.0, 80.0]); // 仍按日期升序
    expect(bar.isCurved, isFalse);
    expect(bar.belowBarData.show, isFalse);
    expect(chart.data.maxY, 90);
    expect(chart.data.gridData.horizontalInterval, 30);
    expect(
      find.byKey(const ValueKey('engagement-trend-signal')),
      findsNothing,
    );
  });

  testWidgets('平均、較上次、筆數由 chart 自己從同一份點列算', (tester) async {
    await _pump(tester, [
      _p(DateTime(2026, 6, 1), 30),
      _p(DateTime(2026, 6, 2), 60),
      _p(DateTime(2026, 6, 3), 90),
    ]);

    expect(find.text('這 3 次平均 60 / 90'), findsOneWidget);
    expect(find.text('較上次 +30'), findsOneWidget);
    expect(find.text('最近 3 筆分析'), findsOneWidget);
    final chart = tester.widget<LineChart>(find.byType(LineChart));
    final avg = chart.data.extraLinesData.horizontalLines.single;
    expect(avg.y, 60);
    expect(avg.label.show, isFalse); // 圖內不放標籤，避免壓到資料點
    expect(
      find.text('虛線是這 3 次平均。按分析先後排列，點一下查看那次資料。'),
      findsOneWidget,
    );
  });

  testWidgets('分析分數 100、50 → 可見上限 90、50；平均 70、較上次 −40', (tester) async {
    await _pump(tester, [
      _p(DateTime(2026, 6, 1), 100),
      _p(DateTime(2026, 6, 2), 50),
    ]);

    final chart = tester.widget<LineChart>(find.byType(LineChart));
    expect(chart.data.lineBarsData.single.spots.map((s) => s.y), [90.0, 50.0]);
    expect(find.text('這 2 次平均 70 / 90'), findsOneWidget);
    expect(find.text('較上次 −40'), findsOneWidget);
  });

  testWidgets('底部標籤是真日期 M/dd，同一天只印一次', (tester) async {
    await _pump(tester, [
      _p(DateTime(2026, 6, 1, 9), 50),
      _p(DateTime(2026, 6, 1, 10), 55),
      _p(DateTime(2026, 6, 5), 80),
    ]);

    expect(find.text('6/01'), findsOneWidget);
    expect(find.text('6/05'), findsOneWidget);
  });

  testWidgets('選取資料預設最新一筆；切換對象後改選新對象最新', (tester) async {
    await _pump(tester, [
      _p(DateTime(2026, 6, 1, 9, 0), 50, id: 'a1'),
      _p(DateTime(2026, 6, 5, 21, 15), 80, id: 'a2'),
    ]);
    expect(find.text('本圖第 2 筆 · 6/05 21:15'), findsOneWidget);
    expect(find.text('投入度 80 / 90'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('report-chart-prev')));
    await tester.pumpAndSettle();
    expect(find.text('本圖第 1 筆 · 6/01 09:00'), findsOneWidget);

    await _pump(
      tester,
      [
        _p(DateTime(2026, 7, 1, 8, 0), 40, id: 'b1'),
        _p(DateTime(2026, 7, 2, 8, 0), 66, id: 'b2'),
        _p(DateTime(2026, 7, 3, 8, 0), 70, id: 'b3'),
      ],
      subjectId: 's2',
    );
    expect(find.text('本圖第 3 筆 · 7/03 08:00'), findsOneWidget);
    expect(find.text('投入度 70 / 90'), findsOneWidget);
  });

  testWidgets('單點 → 顯示那筆投入度與時間，不寫起點、不顯示較上次', (tester) async {
    await _pump(tester, [_p(DateTime(2026, 6, 1, 19, 20), 62)]);

    expect(find.byType(LineChart), findsNothing);
    expect(find.text('投入度 62 · 6/01 19:20'), findsOneWidget);
    expect(find.text('再分析 1 次就能形成趨勢'), findsOneWidget);
    expect(find.textContaining('起點'), findsNothing);
    expect(find.textContaining('較上次'), findsNothing);
    expect(find.text('這 1 次平均 62 / 90'), findsOneWidget);
  });
}
