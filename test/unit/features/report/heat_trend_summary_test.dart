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
}
