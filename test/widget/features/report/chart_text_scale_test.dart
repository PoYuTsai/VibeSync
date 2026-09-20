// test/widget/features/report/chart_text_scale_test.dart
//
// 大字級溢出迴歸（2026-08 dogfood 疊字系列）：
// 1) 全域字級 clamp 上限 1.4（app.dart clampAppTextScale），縮小方向不動。
// 2) 兩張報告圖表的空態／單點態是固定高容器裝文案，必須在 clamp 上限
//    （1.4）＋最窄機身（320）下不溢出、不疊到卡片上方的註解行。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vibesync/app/app.dart';
import 'package:vibesync/features/report/domain/entities/report_models.dart';
import 'package:vibesync/features/report/presentation/widgets/heat_trend_chart.dart';
import 'package:vibesync/features/report/presentation/widgets/practice_temperature_chart.dart';

void main() {
  testWidgets('clampAppTextScale：3.1x 壓到 1.4、0.9x 不動', (t) async {
    late TextScaler clamped;
    late TextScaler small;
    await t.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(3.1)),
        child: Builder(
          builder: (context) => clampAppTextScale(
            context,
            Builder(builder: (inner) {
              clamped = MediaQuery.textScalerOf(inner);
              return const SizedBox.shrink();
            }),
          ),
        ),
      ),
    );
    expect(clamped.scale(10), moreOrLessEquals(14));

    await t.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(0.9)),
        child: Builder(
          builder: (context) => clampAppTextScale(
            context,
            Builder(builder: (inner) {
              small = MediaQuery.textScalerOf(inner);
              return const SizedBox.shrink();
            }),
          ),
        ),
      ),
    );
    expect(small.scale(10), moreOrLessEquals(9));
  });

  Future<void> pumpChart(WidgetTester t, Widget chart) async {
    t.view.physicalSize = const Size(320, 800);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 800),
            textScaler: TextScaler.linear(1.4),
          ),
          child: Scaffold(body: Center(child: chart)),
        ),
      ),
    );
    await t.pump(const Duration(seconds: 1));
  }

  // 疊字斷言：空態/單點文案不得與卡片上方的註解行相交。
  // 溢出本身（RenderFlex overflow）widget test 會直接丟例外紅掉。
  testWidgets('互動熱度圖空態 @1.4x/320 不疊字', (t) async {
    await pumpChart(
      t,
      const HeatTrendChart(
        trendPoints: [],
        emptyMessage: '完成第一次分析後，這裡會畫出互動熱度的變化。',
      ),
    );
    final caption = t.getRect(find.text('只反映這次互動中的文字訊號，不代表關係進度。'));
    final empty = t.getRect(find.text('完成第一次分析後，這裡會畫出互動熱度的變化。'));
    expect(empty.overlaps(caption), isFalse);
  });

  testWidgets('互動熱度圖單點態 @1.4x/320 不溢出', (t) async {
    await pumpChart(
      t,
      HeatTrendChart(
        trendPoints: [
          HeatTrendPoint(
            date: DateTime(2026, 8, 1),
            score: 72,
            conversationName: '小雲',
          ),
        ],
      ),
    );
    expect(t.takeException(), isNull);
  });

  testWidgets('練習溫度圖空態 @1.4x/320 不疊字', (t) async {
    await pumpChart(t, const PracticeTemperatureChart(points: []));
    final caption = t.getRect(find.text('每個點是一輪練習的結束溫度，不等於能力評分。'));
    final empty =
        t.getRect(find.text('完成有溫度計的練習並取得拆解卡後，這裡會留下紀錄。'));
    expect(empty.overlaps(caption), isFalse);
  });

  testWidgets('練習溫度圖單點態 @1.4x/320 不溢出', (t) async {
    await pumpChart(
      t,
      PracticeTemperatureChart(
        points: [
          HeatTrendPoint(
            date: DateTime(2026, 8, 1),
            score: 72,
            conversationName: '練習',
          ),
        ],
      ),
    );
    expect(t.takeException(), isNull);
  });

  List<HeatTrendPoint> sevenDays(String name) => [
        for (var day = 1; day <= 7; day++)
          HeatTrendPoint(
            date: DateTime(2026, 8, day, 9 + day),
            score: 20 + day * 9,
            conversationName: name,
            eventId: 'e$day',
          ),
      ];

  testWidgets('練習溫度圖多點態＋選取資料 @1.4x/320 不溢出', (t) async {
    await pumpChart(t, PracticeTemperatureChart(points: sevenDays('練習')));
    expect(t.takeException(), isNull);
    expect(find.byKey(const ValueKey('report-chart-detail')), findsOneWidget);
  });

  testWidgets('互動熱度圖多點態＋長對象名 @1.4x/320 不溢出', (t) async {
    await pumpChart(
      t,
      HeatTrendChart(
        trendPoints: sevenDays('這是一個非常非常長的對象顯示名稱測試'),
        contextLabel: '這是一個非常非常長的對象顯示名稱測試',
      ),
    );
    expect(t.takeException(), isNull);
    expect(find.byKey(const ValueKey('report-chart-detail')), findsOneWidget);
  });
}
