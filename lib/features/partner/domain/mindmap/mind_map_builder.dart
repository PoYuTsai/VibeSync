import 'dart:convert';

import '../../../analysis/domain/entities/analysis_models.dart';
import '../../../analysis/domain/entities/game_stage.dart';
import '../../../conversation/domain/entities/conversation.dart';
import '../extensions/partner_aggregates.dart';
import 'mind_map_models.dart';

/// 把對象的既有分析資料組成作戰板節點樹。
///
/// 資料來源（與 partner_aggregates 同一套快照，不打任何新 API）：
/// - 階段 / 話題深度 / 下一步：最新一筆可完整解析（JSON + shape）的
///   lastAnalysisSnapshotJson；
///   階段另有 conversation.currentGameStage 作 fallback。
/// - 興趣 / 特質：PartnerAggregateView 跨對話聚合（已去重、各上限 8）。
PartnerMindMap buildPartnerMindMap({
  required String partnerName,
  required PartnerAggregateView aggregate,
  required List<Conversation> conversations,
}) {
  final descByDate = [...conversations]
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  GameStageInfo? stageInfo;
  TopicDepth? topicDepth;
  String snapshotStrategy = '';
  String? snapshotConversationId;
  for (final c in descByDate) {
    final raw = c.lastAnalysisSnapshotJson;
    if (raw == null || raw.trim().isEmpty) continue;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        // 在同一個 try 裡先把要用的欄位全部解掉：
        // 只有 shape 完整可消費的快照才會被選中。
        final parsedStage = GameStageInfo.fromJson(
            decoded['gameStage'] as Map<String, dynamic>?);
        final parsedDepth =
            TopicDepth.fromJson(decoded['topicDepth'] as Map<String, dynamic>?);
        final parsedStrategy = (decoded['strategy'] as String?)?.trim() ?? '';
        stageInfo = parsedStage;
        topicDepth = parsedDepth;
        snapshotStrategy = parsedStrategy;
        snapshotConversationId = c.id;
        break;
      }
    } catch (_) {
      // 與 partner_aggregates._parseSnapshot 同策略：
      // 壞快照（含 JSON 語法錯誤與錯 shape 的 type error）靜默跳過。
    }
  }

  String? fallbackStageRaw;
  for (final c in descByDate) {
    final raw = c.currentGameStage?.trim();
    if (raw != null && raw.isNotEmpty) {
      fallbackStageRaw = raw;
      break;
    }
  }

  final hasAnalysisData = stageInfo != null || fallbackStageRaw != null;
  final branches = <MindMapNode>[];
  String? relationshipSignal;
  String? fullNextStep;

  if (hasAnalysisData) {
    // 階段枝（hasAnalysisData 成立時必有，全圖至少一條邊）
    final stage = stageInfo != null
        ? stageInfo.current
        : GameStage.fromString(fallbackStageRaw!);
    // 關係信號 = 階段描述（詳情 panel 用；hasAnalysisData 時必有）。
    relationshipSignal = stage.description;
    branches.add(MindMapNode(
      id: 'stage',
      label: '關係階段',
      branch: MindMapBranch.stage,
      children: [
        MindMapNode(
          id: 'stage-current',
          label: '${stage.emoji} ${stage.label}',
          branch: MindMapBranch.stage,
        ),
      ],
    ));

    if (topicDepth != null) {
      final depth = topicDepth.current;
      branches.add(MindMapNode(
        id: 'depth',
        label: '話題深度',
        branch: MindMapBranch.topicDepth,
        children: [
          MindMapNode(
            id: 'depth-current',
            label: '${depth.emoji} ${depth.label}',
            branch: MindMapBranch.topicDepth,
          ),
        ],
      ));
    }

    if (aggregate.unionInterests.isNotEmpty) {
      branches.add(MindMapNode(
        id: 'interests',
        label: '興趣',
        branch: MindMapBranch.interests,
        children: [
          for (var i = 0; i < aggregate.unionInterests.length; i++)
            MindMapNode(
              id: 'interest-$i',
              label: aggregate.unionInterests[i],
              branch: MindMapBranch.interests,
            ),
        ],
      ));
    }

    if (aggregate.unionTraits.isNotEmpty) {
      branches.add(MindMapNode(
        id: 'traits',
        label: '特質',
        branch: MindMapBranch.traits,
        children: [
          for (var i = 0; i < aggregate.unionTraits.length; i++)
            MindMapNode(
              id: 'trait-$i',
              label: aggregate.unionTraits[i],
              branch: MindMapBranch.traits,
            ),
        ],
      ));
    }

    if (stageInfo != null) {
      final nextStep = stageInfo.nextStep.trim().isNotEmpty
          ? stageInfo.nextStep.trim()
          : snapshotStrategy;
      if (nextStep.isNotEmpty) {
        fullNextStep = nextStep;
        branches.add(MindMapNode(
          id: 'next',
          label: '下一步',
          branch: MindMapBranch.nextStep,
          children: [
            // 圖節點放短標籤；整句教練建議改由 [PartnerMindMap.fullNextStep]
            // 在詳情 panel 呈現（避免圖節點重貼整句）。
            MindMapNode(
              id: 'next-step',
              label: '下一步行動',
              branch: MindMapBranch.nextStep,
            ),
          ],
        ));
      }
    }
  }

  return PartnerMindMap(
    root: MindMapNode(
      id: 'root',
      label: partnerName,
      branch: MindMapBranch.root,
      children: branches,
    ),
    hasAnalysisData: hasAnalysisData,
    nextStepSourceConversationId: snapshotConversationId,
    relationshipSignal: relationshipSignal,
    topics: aggregate.unionInterests,
    fullNextStep: fullNextStep,
  );
}
