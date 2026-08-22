// lib/features/report/data/services/report_data_service.dart

import '../../../analysis/domain/services/partner_stage_resolver.dart';
import '../../../analysis/domain/entities/enthusiasm_level.dart';
import '../../../analysis_history/domain/entities/analysis_history_event.dart';
import '../../../conversation/domain/entities/conversation.dart';
import '../../../partner/domain/entities/partner.dart';
import '../../../analysis/domain/entities/game_stage.dart';
import '../../domain/entities/report_models.dart';

class ReportDataService {
  static const _partnerStageResolver = PartnerStageResolver();

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
              score: clampVisibleInvestmentScore(c.lastEnthusiasmScore!),
              conversationName: c.name,
            ))
        .toList();

    // 3. 計算平均分數
    final averageScore = scored.isEmpty
        ? 0.0
        : scored
                .map((c) => clampVisibleInvestmentScore(c.lastEnthusiasmScore!))
                .reduce((a, b) => a + b) /
            scored.length;

    // 4. 計算分數趨勢 (較新一半平均 - 較舊一半平均)
    double scoreDelta = 0.0;
    if (scored.length >= 2) {
      final mid = scored.length ~/ 2;
      final olderHalf = scored.sublist(0, mid);
      final newerHalf = scored.sublist(mid);
      final olderAvg = olderHalf
              .map((c) => clampVisibleInvestmentScore(c.lastEnthusiasmScore!))
              .reduce((a, b) => a + b) /
          olderHalf.length;
      final newerAvg = newerHalf
              .map((c) => clampVisibleInvestmentScore(c.lastEnthusiasmScore!))
              .reduce((a, b) => a + b) /
          newerHalf.length;
      scoreDelta = newerAvg - olderAvg;
    }

    // 5. 對話比較 (同名合併，取最新分數，依分數降序)
    // scored 已按 updatedAt 升序排列，後面的覆蓋前面的 = 最新分數
    final mergedMap = <String, ConversationComparison>{};
    for (final c in scored) {
      mergedMap[c.name.trim()] = ConversationComparison(
        name: c.name.trim(),
        score: clampVisibleInvestmentScore(c.lastEnthusiasmScore!),
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

  GameStage? _stageForConversation(Conversation conversation) =>
      _partnerStageResolver.stageForConversation(conversation);

  /// 作戰板真相：一個對象的最新有效互動階段。
  ///
  /// 優先取該對象最新成功且帶合法 stage 的 analyze history event
  /// （依分析完成時間 createdAt 排序）；沒有有效事件證據時，才用該對象
  /// Conversation 的有效快照做 legacy fallback（updatedAt desc）。
  /// 回 null＝從未有有效階段＝作戰板顯示問號。
  GameStage? latestStageFor(
    String partnerId,
    List<AnalysisHistoryEvent> events,
    List<Conversation> conversations,
  ) {
    return _partnerStageResolver.latestStageFor(
      partnerId,
      events,
      conversations,
    );
  }

  /// 與 [latestStageFor] 相同來源，但一併保留「分析當下是否為伴侶重連」；
  /// UI 不得拿 Partner 今天的預設值改寫舊事件文案。
  PartnerStageResolution? latestStageResolutionFor(
    String partnerId,
    List<AnalysisHistoryEvent> events,
    List<Conversation> conversations,
  ) {
    return _partnerStageResolver.latestResolutionFor(
      partnerId,
      events,
      conversations,
    );
  }

  /// 對象清單。partnerId 是 canonical scope；舊事件沒有 partnerId 時，
  /// 透過 conversationId 對照現有 Conversation 後再聚合。
  List<AnalysisSubject> analysisSubjects(
    List<AnalysisHistoryEvent> events,
    List<Conversation> conversations,
    List<Partner> partners,
  ) {
    final conversationsById = {
      for (final conversation in conversations)
        conversation.id.trim(): conversation,
    };
    final latestBySubject = <String, AnalysisHistoryEvent>{};
    final partnerNames = {
      for (final partner in partners)
        if (partner.name.trim().isNotEmpty)
          partner.id.trim(): partner.name.trim(),
    };
    for (final event in events) {
      if (event.kind != AnalysisHistoryKind.analyze) continue;
      final id = _subjectIdFor(event, conversationsById);
      if (id == null) continue;
      final existing = latestBySubject[id];
      if (existing == null || event.createdAt.isAfter(existing.createdAt)) {
        latestBySubject[id] = event;
      }
    }
    return latestBySubject.entries
        .map((entry) => AnalysisSubject(
              subjectId: entry.key,
              name:
                  partnerNames[entry.key] ?? entry.value.subjectName ?? '未命名對象',
              lastEventAt: entry.value.createdAt,
            ))
        .toList()
      ..sort((a, b) => b.lastEventAt.compareTo(a.lastEventAt));
  }

  /// 單一對象投入度時間序列（createdAt 升序；null 分數跳過）。
  List<HeatTrendPoint> subjectTrendPoints(
    List<AnalysisHistoryEvent> events,
    String subjectId,
    List<Conversation> conversations,
  ) {
    final id = AnalysisHistoryEvent.normalizeScope(subjectId);
    if (id == null) return const [];
    final conversationsById = {
      for (final conversation in conversations)
        conversation.id.trim(): conversation,
    };
    return events
        .where((event) =>
            event.kind == AnalysisHistoryKind.analyze &&
            _subjectIdFor(event, conversationsById) == id &&
            event.enthusiasmScore != null)
        .map((event) => HeatTrendPoint(
              date: event.createdAt,
              score: clampVisibleInvestmentScore(event.enthusiasmScore!),
              conversationName: event.subjectName ?? '',
            ))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  String? _subjectIdFor(
    AnalysisHistoryEvent event,
    Map<String, Conversation> conversationsById,
  ) {
    final conversationId =
        AnalysisHistoryEvent.normalizeScope(event.conversationId);
    if (conversationId != null) {
      final currentPartner = AnalysisHistoryEvent.normalizeScope(
        conversationsById[conversationId]?.partnerId,
      );
      if (currentPartner != null) return currentPartner;
    }

    final persistedPartner =
        AnalysisHistoryEvent.normalizeScope(event.partnerId);
    return persistedPartner ?? conversationId;
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
