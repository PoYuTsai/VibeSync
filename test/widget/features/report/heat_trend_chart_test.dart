import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/report/domain/entities/report_models.dart';
import 'package:vibesync/features/report/presentation/widgets/heat_trend_chart.dart';

Future<void> _pump(WidgetTester tester, List<HeatTrendPoint> points) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: HeatTrendChart(
          trendPoints: points,
          averageScore: 60,
          scoreDelta: 5,
        ),
      ),
    ),
  ));
  // 鐵則：動畫必收斂（LineChart 首繪無無限動畫，pumpAndSettle 必須過）。
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('標題與說明限定為每次互動的文字訊號', (tester) async {
    await _pump(tester, const []);

    expect(find.text('每次互動投入度'), findsOneWidget);
    expect(find.text('全部平均 60'), findsOneWidget);
    expect(find.text('前後 +5'), findsOneWidget);
    expect(
      find.text('只反映這次互動中的文字訊號，不代表關係進度。'),
      findsOneWidget,
    );
  });

  testWidgets('x 軸用距首點天數：6/1、6/2、6/5 → x = 0, 1, 4', (tester) async {
    await _pump(tester, [
      HeatTrendPoint(
          date: DateTime(2026, 6, 2), score: 60, conversationName: 'A'),
      HeatTrendPoint(
          date: DateTime(2026, 6, 1), score: 50, conversationName: 'A'),
      HeatTrendPoint(
          date: DateTime(2026, 6, 5), score: 80, conversationName: 'A'),
    ]);

    final chart = tester.widget<LineChart>(find.byType(LineChart));
    final spots = chart.data.lineBarsData.single.spots;
    expect(spots.map((s) => s.x), [0.0, 1.0, 4.0]); // 點距反映真實間隔
    expect(spots.map((s) => s.y), [50.0, 60.0, 80.0]); // 仍按日期升序
  });

  testWidgets('底部標籤是真日期 M/dd', (tester) async {
    await _pump(tester, [
      HeatTrendPoint(
          date: DateTime(2026, 6, 1), score: 50, conversationName: 'A'),
      HeatTrendPoint(
          date: DateTime(2026, 6, 5), score: 80, conversationName: 'A'),
    ]);

    expect(find.text('6/01'), findsOneWidget);
    expect(find.text('6/05'), findsOneWidget);
  });

  testWidgets('空清單 → 空狀態不畫圖', (tester) async {
    await _pump(tester, const []);
    expect(find.byType(LineChart), findsNothing);
    expect(find.text('尚無數據'), findsOneWidget);
  });
}
