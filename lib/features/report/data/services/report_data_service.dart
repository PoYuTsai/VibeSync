// lib/features/report/data/services/report_data_service.dart

import '../../../conversation/domain/entities/conversation.dart';
import '../../../analysis/domain/entities/game_stage.dart';
import '../../domain/entities/report_models.dart';

class ReportDataService {
  /// GAME 階段短標籤對照
  static const _stageShortLabels = {
    GameStage.opening: '打開',
    GameStage.premise: '前提',
    GameStage.qualification: '評估',
    GameStage.narrative: '敘事',
    GameStage.close: '收尾',
  };

  /// 從對話列表產生完整報告數據
  ReportData generateReport(List<Conversation> conversations) {
    // 1. 篩選有熱度分數的對話，按 updatedAt 排序
    final scored = conversations
        .where((c) => c.lastEnthusiasmScore != null)
        .toList()
      ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));

    // 2. 取最近 7 筆作為趨勢數據
    final recentScored =
        scored.length > 7 ? scored.sublist(scored.length - 7) : scored;
    final trendPoints = recentScored
        .map((c) => HeatTrendPoint(
              date: c.updatedAt,
              score: c.lastEnthusiasmScore!,
              conversationName: c.name,
            ))
        .toList();

    // 3. 計算平均分數
    final averageScore = scored.isEmpty
        ? 0.0
        : scored.map((c) => c.lastEnthusiasmScore!).reduce((a, b) => a + b) /
            scored.length;

    // 4. 計算分數趨勢 (較新一半平均 - 較舊一半平均)
    double scoreDelta = 0.0;
    if (scored.length >= 2) {
      final mid = scored.length ~/ 2;
      final olderHalf = scored.sublist(0, mid);
      final newerHalf = scored.sublist(mid);
      final olderAvg =
          olderHalf.map((c) => c.lastEnthusiasmScore!).reduce((a, b) => a + b) /
              olderHalf.length;
      final newerAvg =
          newerHalf.map((c) => c.lastEnthusiasmScore!).reduce((a, b) => a + b) /
              newerHalf.length;
      scoreDelta = newerAvg - olderAvg;
    }

    // 5. 對話比較 (依分數降序)
    final comparisons = scored
        .map((c) => ConversationComparison(
              name: c.name,
              score: c.lastEnthusiasmScore!,
            ))
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    // 6. 階段分佈 (使用 GameStage.fromString 取得短標籤)
    final stageCounts = <String, int>{};
    for (final c in conversations) {
      final stage = GameStage.fromString(c.currentGameStage ?? 'opening');
      final label = _stageShortLabels[stage] ?? '打開';
      stageCounts[label] = (stageCounts[label] ?? 0) + 1;
    }
    final stageDistributions = stageCounts.entries
        .where((e) => e.value > 0)
        .map((e) => StageDistribution(stageName: e.key, count: e.value))
        .toList();

    return ReportData(
      trendPoints: trendPoints,
      averageScore: averageScore,
      scoreDelta: scoreDelta,
      comparisons: comparisons,
      stageDistributions: stageDistributions,
      totalConversations: conversations.length,
    );
  }
}
