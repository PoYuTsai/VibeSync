import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/report/domain/entities/report_models.dart';

HeatTrendPoint _point(int day, int score) => HeatTrendPoint(
      date: DateTime(2026, 7, day),
      score: score,
      conversationName: '小雲',
    );

void main() {
  test('近期摘要只取最新七次，平均與 delta 都使用同一組資料', () {
    final source = [
      _point(8, 88),
      _point(1, 10),
      _point(7, 70),
      _point(2, 20),
      _point(6, 60),
      _point(3, 30),
      _point(5, 50),
      _point(4, 40),
    ];

    final summary = HeatTrendSummary.fromPoints(source);

    expect(summary.points.map((point) => point.score),
        [20, 30, 40, 50, 60, 70, 88]);
    expect(summary.averageScore, closeTo(51.1428, 0.001));
    expect(summary.scoreDelta, 18); // 最近一次相對前一次，不是全體前後半。
    expect(summary.latestScore, 88);
    expect(source.first.score, 88); // 不改動呼叫端原清單。
  });

  test('零筆與單筆都有穩定摘要，不捏造趨勢', () {
    expect(HeatTrendSummary.fromPoints(const []).latestScore, isNull);

    final summary = HeatTrendSummary.fromPoints([_point(1, 64)]);
    expect(summary.averageScore, 64);
    expect(summary.scoreDelta, 0);
    expect(summary.sampleCount, 1);
  });

  test('同 timestamp 不同 id：打亂輸入也得到相同 id 順序、不丟筆', () {
    final t = DateTime(2026, 7, 1, 9, 0, 0);
    HeatTrendPoint withId(String id, int score) => HeatTrendPoint(
          date: t,
          score: score,
          conversationName: '',
          eventId: id,
        );
    final a = HeatTrendSummary.fromPoints([
      withId('c', 3),
      withId('a', 1),
      withId('b', 2),
    ]);
    final b = HeatTrendSummary.fromPoints([
      withId('b', 2),
      withId('c', 3),
      withId('a', 1),
    ]);
    expect(a.points.map((p) => p.eventId), ['a', 'b', 'c']);
    expect(b.points.map((p) => p.eventId), ['a', 'b', 'c']);
    expect(a.points.length, 3);
  });

  test('沒有 id 的同時刻資料以輸入位置為序，單次處理穩定', () {
    final t = DateTime(2026, 7, 1);
    final source = [
      HeatTrendPoint(date: t, score: 1, conversationName: ''),
      HeatTrendPoint(date: t, score: 2, conversationName: ''),
      HeatTrendPoint(date: t, score: 3, conversationName: ''),
    ];
    expect(sortHeatTrendPoints(source).map((p) => p.score), [1, 2, 3]);
    expect(sortHeatTrendPoints(source).map((p) => p.score), [1, 2, 3]);
  });

  test('微秒精度排序：同分鐘不同秒不合併、不重排', () {
    final base = DateTime(2026, 7, 1, 9, 0, 1);
    final source = [
      HeatTrendPoint(
        date: base.add(const Duration(seconds: 2)),
        score: 3,
        conversationName: '',
      ),
      HeatTrendPoint(date: base, score: 1, conversationName: ''),
      HeatTrendPoint(
        date: base.add(const Duration(seconds: 1)),
        score: 2,
        conversationName: '',
      ),
    ];
    expect(sortHeatTrendPoints(source).map((p) => p.score), [1, 2, 3]);
  });
}
