import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/core/theme/app_colors.dart';
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

HeatTrendPoint _p(DateTime date, int score, {String? id}) => HeatTrendPoint(
      date: date,
      score: score,
      conversationName: '',
      eventId: id,
    );

void main() {
  testWidgets('≥2 點 → 紀錄順序軸：x = 0, 1；直線；無流光、無填色', (tester) async {
    await _pump(tester, [
      _p(DateTime(2026, 6, 1), 28),
      _p(DateTime(2026, 6, 4), 45),
    ]);

    expect(find.text('練習溫度紀錄'), findsOneWidget);
    expect(find.text('最近 2 筆紀錄'), findsOneWidget);
    expect(find.textContaining('較上次'), findsNothing);
    final chart = tester.widget<LineChart>(find.byType(LineChart));
    final bar = chart.data.lineBarsData.single;
    expect(bar.spots.map((s) => s.x), [0.0, 1.0]);
    expect(bar.spots.map((s) => s.y), [28.0, 45.0]);
    expect(bar.isCurved, isFalse);
    expect(bar.belowBarData.show, isFalse);
    expect(chart.data.clipData, const FlClipData.none());
    expect(find.byType(LiquidMotionFrame), findsOneWidget);
    expect(
      find.byKey(const ValueKey('practice-growth-trend-glow')),
      findsNothing,
    );
  });

  testWidgets('同一天四筆 95/50/30/8 → 四個等距點，日期只印一次', (tester) async {
    final day = DateTime(2026, 9, 8);
    await _pump(tester, [
      _p(day.add(const Duration(hours: 9)), 95, id: 'a'),
      _p(day.add(const Duration(hours: 10)), 50, id: 'b'),
      _p(day.add(const Duration(hours: 11)), 30, id: 'c'),
      _p(day.add(const Duration(hours: 12)), 8, id: 'd'),
    ]);

    final chart = tester.widget<LineChart>(find.byType(LineChart));
    expect(
      chart.data.lineBarsData.single.spots.map((s) => s.x),
      [0.0, 1.0, 2.0, 3.0],
    );
    expect(find.text('9/08'), findsOneWidget);
    // 最新 8 → 主數字，沒有「退步」判斷。
    expect(find.text('最近結束溫度 8 / 100'), findsOneWidget);
    expect(find.textContaining('較上次'), findsNothing);
  });

  testWidgets('五段溫度帶：連續無空隙、邊界 0/20/40/60/80/100', (tester) async {
    await _pump(tester, [
      _p(DateTime(2026, 6, 1), 28),
      _p(DateTime(2026, 6, 4), 45),
    ]);

    final chart = tester.widget<LineChart>(find.byType(LineChart));
    final bands = chart.data.rangeAnnotations.horizontalRangeAnnotations;
    expect(bands.length, 5);
    expect(bands.map((b) => b.y1), [0.0, 20.0, 40.0, 60.0, 80.0]);
    expect(bands.map((b) => b.y2), [20.0, 40.0, 60.0, 80.0, 100.0]);
    for (var i = 1; i < bands.length; i++) {
      expect(bands[i].y1, bands[i - 1].y2); // 無 20–21 空隙
    }
    // 色票沿用溫度計 band 色（alpha 另計）。
    expect(bands[0].color!.withValues(alpha: 1), AppColors.frozen);
    expect(bands[4].color!.withValues(alpha: 1), AppColors.hot);
    expect(chart.data.gridData.horizontalInterval, 20);
    expect(chart.data.maxY, 100);
  });

  testWidgets('選取資料：預設最新一筆，上一筆／下一筆與點擊都能切換', (tester) async {
    await _pump(tester, [
      _p(DateTime(2026, 6, 1, 9, 5), 28, id: 'e1'),
      _p(DateTime(2026, 6, 4, 20, 30), 45, id: 'e2'),
      _p(DateTime(2026, 6, 9, 8, 0), 88, id: 'e3'),
    ]);

    expect(find.text('本圖第 3 筆 · 6/09 08:00'), findsOneWidget);
    expect(find.text('結束溫度 88 / 100 · 很熱絡'), findsOneWidget);
    expect(find.text('按紀錄先後排列，點一下查看那次資料。'), findsOneWidget);

    final next = find.byKey(const ValueKey('report-chart-next'));
    final prev = find.byKey(const ValueKey('report-chart-prev'));
    expect(tester.widget<IconButton>(next).onPressed, isNull); // 邊界停用

    await tester.tap(prev);
    await tester.pumpAndSettle();
    expect(find.text('本圖第 2 筆 · 6/04 20:30'), findsOneWidget);
    expect(find.text('結束溫度 45 / 100 · 普通'), findsOneWidget);

    await tester.tap(prev);
    await tester.pumpAndSettle();
    expect(find.text('本圖第 1 筆 · 6/01 09:05'), findsOneWidget);
    expect(find.text('結束溫度 28 / 100 · 偏冷'), findsOneWidget);
    expect(tester.widget<IconButton>(prev).onPressed, isNull);

    // 點擊圖上最後一欄（x=2 佔 plot 右三分之一；只算水平距離）。
    final chartRect = tester.getRect(find.byType(LineChart));
    await tester.tapAt(Offset(
      chartRect.left + chartRect.width * 0.85,
      chartRect.top + chartRect.height * 0.5,
    ));
    await tester.pumpAndSettle();
    expect(find.text('本圖第 3 筆 · 6/09 08:00'), findsOneWidget);
  });

  testWidgets('視窗新增一筆：所選 id 仍在就跟著；離開視窗選最新', (tester) async {
    final base = [
      for (var i = 0; i < 7; i++)
        _p(DateTime(2026, 6, 1 + i), 30 + i, id: 'e$i'),
    ];
    await _pump(tester, base);
    await tester.tap(find.byKey(const ValueKey('report-chart-prev')));
    await tester.pumpAndSettle();
    expect(find.text('本圖第 6 筆 · 6/06 00:00'), findsOneWidget);

    // 新增第 8 筆：視窗變 e1..e7，所選 e5 仍在，位置變第 5 筆。
    await _pump(tester, [...base, _p(DateTime(2026, 6, 8), 50, id: 'e7')]);
    expect(find.text('本圖第 5 筆 · 6/06 00:00'), findsOneWidget);

    // 再加到 13 筆：視窗 e6..e12，e5 被擠出 → 選最新。
    await _pump(tester, [
      ...base,
      for (var i = 7; i < 13; i++)
        _p(DateTime(2026, 6, 1 + i), 50, id: 'e$i'),
    ]);
    expect(find.text('本圖第 7 筆 · 6/13 00:00'), findsOneWidget);
  });

  testWidgets('單點 → 顯示結束溫度、時間與本輪條件，不畫線', (tester) async {
    await _pump(tester, [
      HeatTrendPoint(
        date: DateTime(2026, 6, 1, 19, 20),
        score: 28,
        conversationName: '',
        eventId: 'practice:single',
        practiceContext: const PracticeRecordContext(
          difficulty: 'normal',
          mode: 'beginner',
          roundIndex: 2,
          aiReplyCount: 8,
        ),
      ),
    ]);

    expect(find.byType(LineChart), findsNothing);
    expect(find.text('結束溫度 28 · 6/01 19:20'), findsOneWidget);
    expect(find.text('新手 · 一般 · 第 2 輪 · 她回覆 8 次'), findsOneWidget);
    expect(find.text('再留下 1 筆紀錄，就能一起查看兩次的差別。'), findsOneWidget);
    expect(find.textContaining('起點'), findsNothing);
    expect(
      find.byKey(const ValueKey('practice-growth-single-point')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('practice-growth-empty-state')),
      findsNothing,
    );
  });

  testWidgets('空清單 → 引導文案含新手與 Game', (tester) async {
    await _pump(tester, const []);
    expect(find.byType(LineChart), findsNothing);
    expect(
      find.byKey(const ValueKey('practice-growth-empty-state')),
      findsOneWidget,
    );
    expect(
      find.text('完成有溫度計的練習並取得拆解卡後，這裡會留下紀錄。'),
      findsOneWidget,
    );
    expect(find.text('包含新手與 Game 模式。'), findsOneWidget);
    expect(find.textContaining('最近結束溫度'), findsNothing);
  });

  group('選取資料第三行：練習條件', () {
    testWidgets('新事件 → 模式 · 難度 · 輪次 · 她回覆 N 次', (tester) async {
      await _pump(tester, [
        _p(DateTime(2026, 9, 18, 9), 30, id: 'a'),
        HeatTrendPoint(
          date: DateTime(2026, 9, 19, 19, 20),
          score: 61,
          conversationName: '',
          eventId: 'practice:s9',
          practiceContext: const PracticeRecordContext(
            difficulty: 'normal',
            mode: 'beginner',
            roundIndex: 2,
            aiReplyCount: 8,
          ),
        ),
      ]);

      expect(find.text('新手 · 一般 · 第 2 輪 · 她回覆 8 次'), findsOneWidget);
    });

    testWidgets('部分未知 → 只列已知，不補預設值', (tester) async {
      await _pump(tester, [
        _p(DateTime(2026, 9, 18, 9), 30, id: 'a'),
        HeatTrendPoint(
          date: DateTime(2026, 9, 19, 19, 20),
          score: 61,
          conversationName: '',
          eventId: 'practice:s9',
          practiceContext: const PracticeRecordContext(
            mode: 'game',
            roundIndex: 1,
          ),
        ),
      ]);

      expect(find.text('Game · 第 1 輪'), findsOneWidget);
      expect(find.textContaining('一般'), findsNothing);
      expect(find.textContaining('回覆'), findsNothing);
    });

    testWidgets('舊事件全無條件 → 明說沒有保存', (tester) async {
      await _pump(tester, [
        _p(DateTime(2026, 9, 18, 9), 30, id: 'a'),
        _p(DateTime(2026, 9, 19, 19, 20), 61, id: 'b'),
      ]);

      expect(find.text('這筆舊紀錄沒有保存練習條件'), findsOneWidget);
    });
  });
}
