// lib/features/report/domain/entities/report_models.dart

/// 熱度趨勢數據點
class HeatTrendPoint {
  final DateTime date;
  final int score;
  final String conversationName;

  const HeatTrendPoint({
    required this.date,
    required this.score,
    required this.conversationName,
  });
}

/// 將任一投入度時間序列整理成可讀的「近期趨勢」。
///
/// 報告只畫最近 [maxPoints] 次，避免長期資料把手機圖表擠成噪音；delta 是
/// 最近一次相對前一次，而不是混用全體對話的前後半平均。
class HeatTrendSummary {
  final List<HeatTrendPoint> points;
  final double averageScore;
  final double scoreDelta;

  const HeatTrendSummary({
    required this.points,
    required this.averageScore,
    required this.scoreDelta,
  });

  factory HeatTrendSummary.fromPoints(
    List<HeatTrendPoint> source, {
    int maxPoints = 7,
  }) {
    assert(maxPoints > 0);
    final sorted = List<HeatTrendPoint>.from(source)
      ..sort((a, b) => a.date.compareTo(b.date));
    final recent = sorted.length > maxPoints
        ? sorted.sublist(sorted.length - maxPoints)
        : sorted;
    final immutable = List<HeatTrendPoint>.unmodifiable(recent);
    if (immutable.isEmpty) {
      return const HeatTrendSummary(
        points: [],
        averageScore: 0,
        scoreDelta: 0,
      );
    }
    final average = immutable.fold<int>(0, (sum, point) => sum + point.score) /
        immutable.length;
    final delta = immutable.length < 2
        ? 0.0
        : (immutable.last.score - immutable[immutable.length - 2].score)
            .toDouble();
    return HeatTrendSummary(
      points: immutable,
      averageScore: average,
      scoreDelta: delta,
    );
  }

  int get sampleCount => points.length;
  int? get latestScore => points.isEmpty ? null : points.last.score;
}

/// 對話比較項目
class ConversationComparison {
  final String name;
  final int score;

  const ConversationComparison({
    required this.name,
    required this.score,
  });
}

/// 階段分佈項目
class StageDistribution {
  final String stageName;
  final int count;

  const StageDistribution({
    required this.stageName,
    required this.count,
  });
}

/// 完整報告數據
class ReportData {
  final List<HeatTrendPoint> trendPoints;
  final double averageScore;
  final double scoreDelta;
  final List<ConversationComparison> comparisons;
  final List<StageDistribution> stageDistributions;
  final int totalConversations;

  const ReportData({
    required this.trendPoints,
    required this.averageScore,
    required this.scoreDelta,
    required this.comparisons,
    required this.stageDistributions,
    required this.totalConversations,
  });
}

/// 案2：報告頁對象選擇器項目（來自 analyze 歷史事件的 distinct conversationId）。
class AnalysisSubject {
  final String conversationId;
  final String name;
  final DateTime lastEventAt;

  const AnalysisSubject({
    required this.conversationId,
    required this.name,
    required this.lastEventAt,
  });
}
