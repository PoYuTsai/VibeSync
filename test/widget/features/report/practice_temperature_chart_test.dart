import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/report/domain/entities/report_models.dart';
import 'package:vibesync/features/report/presentation/widgets/practice_temperature_chart.dart';

Future<void> _pump(WidgetTester tester, List<HeatTrendPoint> points) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: PracticeTemperatureChart(points: points),
      ),
    ),
  ));
  await tester.pumpAndSettle(); // 鐵則：動畫必收斂
}

void main() {
  testWidgets('≥2 點 → 畫線圖、x 用距首點天數', (tester) async {
    await _pump(tester, [
      HeatTrendPoint(date: DateTime(2026, 6, 1), score: 28, conversationName: ''),
      HeatTrendPoint(date: DateTime(2026, 6, 4), score: 45, conversationName: ''),
    ]);

    expect(find.text('練習溫度成長'), findsOneWidget);
    final chart = tester.widget<LineChart>(find.byType(LineChart));
    expect(
      chart.data.lineBarsData.single.spots.map((s) => s.x),
      [0.0, 3.0],
    );
  });

  testWidgets('<2 點 → 引導文案、不畫圖', (tester) async {
    await _pump(tester, [
      HeatTrendPoint(date: DateTime(2026, 6, 1), score: 28, conversationName: ''),
    ]);

    expect(find.byType(LineChart), findsNothing);
    expect(
      find.text('多完成幾場新手模式練習，這裡會畫出你的升溫能力成長曲線'),
      findsOneWidget,
    );
  });

  testWidgets('空清單 → 引導文案', (tester) async {
    await _pump(tester, const []);
    expect(find.byType(LineChart), findsNothing);
  });
}
