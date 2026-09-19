// lib/features/report/domain/entities/report_models.dart

/// 熱度趨勢數據點。
///
/// [eventId] 是來源歷史事件的 id：同一時刻的多筆資料靠它做穩定排序與
/// 「所選點」身分；測試／預覽資料可為 null（改以輸入位置當第二排序鍵）。
class HeatTrendPoint {
  final DateTime date;
  final int score;
  final String conversationName;
  final String? eventId;

  const HeatTrendPoint({
    required this.date,
    required this.score,
    required this.conversationName,
    this.eventId,
  });
}

/// 報告頁所有折線資料共用的穩定排序：先依原始時間（微秒精度）升序，同時刻
/// 再依 [HeatTrendPoint.eventId]，兩者都缺時退回輸入位置。Dart `List.sort`
/// 不保證同值元素順序，所以第二、第三鍵是必要的，不是保險。不改動來源清單。
List<HeatTrendPoint> sortHeatTrendPoints(List<HeatTrendPoint> source) {
  final indexed = [
    for (var i = 0; i < source.length; i++) (index: i, point: source[i]),
  ];
  indexed.sort((a, b) {
    final byDate = a.point.date.compareTo(b.point.date);
    if (byDate != 0) return byDate;
    final idA = a.point.eventId;
    final idB = b.point.eventId;
    if (idA != null && idB != null) {
      final byId = idA.compareTo(idB);
      if (byId != 0) return byId;
    }
    return a.index.compareTo(b.index);
  });
  return [for (final entry in indexed) entry.point];
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
    final sorted = sortHeatTrendPoints(source);
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

/// 報告頁對象選擇器項目。新事件以 partnerId 聚合；舊事件會先透過
/// conversationId 對照 partnerId，無法對照時才保留 conversation scope。
class AnalysisSubject {
  final String subjectId;
  final String name;
  final DateTime lastEventAt;

  const AnalysisSubject({
    required this.subjectId,
    required this.name,
    required this.lastEventAt,
  });
}
