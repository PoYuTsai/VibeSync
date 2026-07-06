// lib/features/report/data/services/report_data_service.dart

import 'dart:convert';

import '../../../analysis_history/domain/entities/analysis_history_event.dart';
import '../../../conversation/domain/entities/conversation.dart';
import '../../../analysis/domain/entities/game_stage.dart';
import '../../domain/entities/report_models.dart';

class ReportDataService {
  /// 對話階段短標籤對照
  static const _stageShortLabels = {
    GameStage.opening: '破冰',
    GameStage.premise: '升溫',
    GameStage.qualification: '深入',
    GameStage.narrative: '連結',
    GameStage.close: '邀約',
  };

  /// 從對話列表產生完整報告數據
  ReportData generateReport(List<Conversation> conversations) {
    // 1. 篩選有熱度分數的對話，按 updatedAt 排序
    final scored = conversations.where(_hasCurrentAnalysisScore).toList()
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

    // 5. 對話比較 (同名合併，取最新分數，依分數降序)
    // scored 已按 updatedAt 升序排列，後面的覆蓋前面的 = 最新分數
    final mergedMap = <String, ConversationComparison>{};
    for (final c in scored) {
      mergedMap[c.name.trim()] = ConversationComparison(
        name: c.name.trim(),
        score: c.lastEnthusiasmScore!,
      );
    }
    final comparisons = mergedMap.values.toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    // 6. 階段分佈 (使用 GameStage.fromString 取得短標籤)
    final stageCounts = <String, int>{};
    for (final c in scored) {
      final stage = _stageForConversation(c);
      if (stage == null) continue;
      final label = _stageShortLabels[stage] ?? '破冰';
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
      totalConversations: scored.length,
    );
  }

  bool _hasCurrentAnalysisScore(Conversation conversation) {
    if (conversation.lastEnthusiasmScore == null) {
      return false;
    }

    final analyzedCount = conversation.lastAnalyzedMessageCount;
    return analyzedCount == null ||
        analyzedCount == conversation.messages.length;
  }

  GameStage? _stageForConversation(Conversation conversation) {
    final directStage = conversation.currentGameStage?.trim();
    if (directStage != null && directStage.isNotEmpty) {
      return GameStage.fromString(directStage);
    }

    final snapshotJson = conversation.lastAnalysisSnapshotJson;
    if (snapshotJson == null || snapshotJson.trim().isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(snapshotJson);
      if (decoded is! Map) return null;

      final gameStage = decoded['gameStage'];
      if (gameStage is! Map) return null;

      final current = gameStage['current'];
      if (current is! String || current.trim().isEmpty) return null;

      return GameStage.fromString(current.trim());
    } catch (_) {
      return null;
    }
  }

  /// 案2：對象清單——distinct conversationId（取最新 subjectName 快照），
  /// 按最近事件時間 desc（報告頁 chip 列預設選第一個＝最近分析過的對象）。
  List<AnalysisSubject> analysisSubjects(List<AnalysisHistoryEvent> events) {
    final latestByConversation = <String, AnalysisHistoryEvent>{};
    for (final event in events) {
      if (event.kind != AnalysisHistoryKind.analyze) continue;
      final id = AnalysisHistoryEvent.normalizeScope(event.conversationId);
      if (id == null) continue;
      final existing = latestByConversation[id];
      if (existing == null || event.createdAt.isAfter(existing.createdAt)) {
        latestByConversation[id] = event;
      }
    }
    return latestByConversation.entries
        .map((entry) => AnalysisSubject(
              conversationId: entry.key,
              name: entry.value.subjectName ?? '未命名對象',
              lastEventAt: entry.value.createdAt,
            ))
        .toList()
      ..sort((a, b) => b.lastEventAt.compareTo(a.lastEventAt));
  }

  /// 案2：單對象熱度時間序列（createdAt 升序；enthusiasmScore null 跳過）。
  List<HeatTrendPoint> subjectTrendPoints(
    List<AnalysisHistoryEvent> events,
    String conversationId,
  ) {
    final id = AnalysisHistoryEvent.normalizeScope(conversationId);
    if (id == null) return const [];
    return events
        .where((event) =>
            event.kind == AnalysisHistoryKind.analyze &&
            AnalysisHistoryEvent.normalizeScope(event.conversationId) == id &&
            event.enthusiasmScore != null)
        .map((event) => HeatTrendPoint(
              date: event.createdAt,
              score: event.enthusiasmScore!,
              conversationName: event.subjectName ?? '',
            ))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  /// 案2：練習溫度全域時間序列——刻意不分對象混排（練習溫度量的是玩家
  /// 本人的開場→升溫能力，跨對象看斜率才是成長曲線）。temperatureScore
  /// null（非新手模式）跳過。familiarityScore 不畫第二條線（YAGNI）。
  List<HeatTrendPoint> practiceTemperaturePoints(
    List<AnalysisHistoryEvent> events,
  ) {
    return events
        .where((event) =>
            event.kind == AnalysisHistoryKind.practice &&
            event.temperatureScore != null)
        .map((event) => HeatTrendPoint(
              date: event.createdAt,
              score: event.temperatureScore!,
              conversationName: '',
            ))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }
}
