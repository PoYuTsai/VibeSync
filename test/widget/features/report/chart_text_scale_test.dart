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
        averageScore: 0,
        scoreDelta: 0,
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
        averageScore: 72,
        scoreDelta: 0,
      ),
    );
    expect(t.takeException(), isNull);
  });

  testWidgets('練習升溫圖空態 @1.4x/320 不疊字', (t) async {
    await pumpChart(t, const PracticeTemperatureChart(points: []));
    final caption = t.getRect(find.text('只整理練習室表現，不混入真實對話。'));
    final empty =
        t.getRect(find.text('多完成幾場新手模式練習，這裡會畫出你的升溫能力成長曲線'));
    expect(empty.overlaps(caption), isFalse);
  });

  testWidgets('練習升溫圖單點態 @1.4x/320 不溢出', (t) async {
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
}
