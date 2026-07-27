import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/report/domain/entities/report_models.dart';
import 'package:vibesync/features/report/presentation/widgets/practice_temperature_chart.dart';
import 'package:vibesync/shared/widgets/brand/liquid_motion_frame.dart';

Future<void> _pump(WidgetTester tester, List<HeatTrendPoint> points) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: SingleChildScrollView(
          child: PracticeTemperatureChart(points: points),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle(); // 鐵則：動畫必收斂
}

void main() {
  testWidgets('≥2 點 → 畫線圖、x 用距首點天數', (tester) async {
    await _pump(tester, [
      HeatTrendPoint(
          date: DateTime(2026, 6, 1), score: 28, conversationName: ''),
      HeatTrendPoint(
          date: DateTime(2026, 6, 4), score: 45, conversationName: ''),
    ]);

    expect(find.text('練習溫度成長'), findsOneWidget);
    final chart = tester.widget<LineChart>(find.byType(LineChart));
    expect(
      chart.data.lineBarsData.single.spots.map((s) => s.x),
      [0.0, 3.0],
    );
    expect(find.byType(LiquidMotionFrame), findsOneWidget);
    expect(
      find.byKey(const ValueKey('practice-growth-trend-glow')),
      findsOneWidget,
    );
  });

  testWidgets('單點 → 顯示真實起點、不播放假路徑', (tester) async {
    await _pump(tester, [
      HeatTrendPoint(
          date: DateTime(2026, 6, 1), score: 28, conversationName: ''),
    ]);

    expect(find.byType(LineChart), findsNothing);
    expect(
      find.text('起點 28 · 6/01'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('practice-growth-single-point')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('practice-growth-empty-state')),
      findsNothing,
    );
  });

  testWidgets('空清單 → 引導文案', (tester) async {
    await _pump(tester, const []);
    expect(find.byType(LineChart), findsNothing);
    expect(
      find.byKey(const ValueKey('practice-growth-empty-state')),
      findsOneWidget,
    );
  });
}
