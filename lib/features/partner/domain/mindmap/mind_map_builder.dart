import 'dart:convert';

import '../../../analysis/domain/entities/analysis_models.dart';
import '../../../analysis/domain/entities/game_stage.dart';
import '../../../conversation/domain/entities/conversation.dart';
import '../extensions/partner_aggregates.dart';
import 'mind_map_models.dart';

/// 把對象的既有分析資料組成作戰板節點樹。
///
/// 資料來源（與 partner_aggregates 同一套快照，不打任何新 API）：
/// - 階段 / 話題深度 / 下一步：最新一筆可解析的 lastAnalysisSnapshotJson；
///   階段另有 conversation.currentGameStage 作 fallback。
/// - 興趣 / 特質：PartnerAggregateView 跨對話聚合（已去重、各上限 8）。
PartnerMindMap buildPartnerMindMap({
  required String partnerName,
  required PartnerAggregateView aggregate,
  required List<Conversation> conversations,
}) {
  final descByDate = [...conversations]
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  Map<String, dynamic>? snapshot;
  for (final c in descByDate) {
    final raw = c.lastAnalysisSnapshotJson;
    if (raw == null || raw.trim().isEmpty) continue;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        snapshot = decoded;
        break;
      }
    } catch (_) {
      // 與 partner_aggregates._parseSnapshot 同策略：壞快照靜默跳過。
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

  final hasAnalysisData = snapshot != null || fallbackStageRaw != null;
  final branches = <MindMapNode>[];

  if (hasAnalysisData) {
    // 階段枝（hasAnalysisData 成立時必有，全圖至少一條邊）
    final stage = snapshot != null
        ? GameStageInfo.fromJson(snapshot['gameStage'] as Map<String, dynamic>?)
            .current
        : GameStage.fromString(fallbackStageRaw!);
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

    if (snapshot != null) {
      final depth =
          TopicDepth.fromJson(snapshot['topicDepth'] as Map<String, dynamic>?)
              .current;
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

    if (snapshot != null) {
      final stageInfo = GameStageInfo.fromJson(
          snapshot['gameStage'] as Map<String, dynamic>?);
      final strategy = (snapshot['strategy'] as String?)?.trim() ?? '';
      final nextStep = stageInfo.nextStep.trim().isNotEmpty
          ? stageInfo.nextStep.trim()
          : strategy;
      if (nextStep.isNotEmpty) {
        branches.add(MindMapNode(
          id: 'next',
          label: '下一步',
          branch: MindMapBranch.nextStep,
          children: [
            MindMapNode(
              id: 'next-step',
              label: nextStep,
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
  );
}
