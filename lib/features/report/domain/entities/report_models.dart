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
