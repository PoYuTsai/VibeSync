import 'dart:convert';

import '../../../analysis/domain/entities/analysis_models.dart';
import '../../../analysis/domain/entities/analysis_record.dart';
import '../../../analysis/domain/entities/game_stage.dart';
import '../../../conversation/domain/entities/conversation.dart';
import '../extensions/partner_aggregates.dart';
import '../services/partner_memory_tag_catalog.dart';
import 'mind_map_models.dart';

/// 把對象的既有分析資料組成作戰板節點樹。
///
/// 資料來源（與 partner_aggregates 同一套快照，不打任何新 API）：
/// - 階段 / 話題深度 / 下一步：最新一筆可完整解析（JSON + shape）的分析
///   紀錄；沒有獨立紀錄的舊資料才回退到 lastAnalysisSnapshotJson。
/// - 上次 → 這次 / 連續次數：依可解析的獨立分析紀錄計算；Conversation
///   裡相同快照只是鏡像，不重複計次。
/// - 本輪訊號：最新快照既有、非低信心的 coachActionHint.catchablePoint。
/// - 已確認資料：Partner.customNote 經 allowlist chips 解析，舊自由文字不採用。
/// - 興趣 / 特質：PartnerAggregateView 跨對話聚合（已去重、各上限 8）。
PartnerMindMap buildPartnerMindMap({
  required String partnerName,
  required PartnerAggregateView aggregate,
  required List<Conversation> conversations,
  List<AnalysisRecord> analysisRecords = const [],
  String? partnerCustomNote,
}) {
  final descByDate = [...conversations]
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  final parsedSnapshots = _latestParsedSnapshots(
    conversations: descByDate,
    analysisRecords: analysisRecords,
  );
  final latestSnapshot = parsedSnapshots.isEmpty ? null : parsedSnapshots.first;
  final stageInfo = latestSnapshot?.stageInfo;
  final topicDepth = latestSnapshot?.topicDepth;
  final snapshotStrategy = latestSnapshot?.strategy ?? '';
  final snapshotConversationId = latestSnapshot?.conversationId;
  final currentSignal = latestSnapshot?.coachActionHint?.catchablePoint.trim();
  final confirmedFacts = _confirmedFacts(partnerCustomNote);

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
          label: _progressLabel(
            current: stage.label,
            newestFirst: parsedSnapshots.map(
              (snapshot) => snapshot.stageInfo.current.label,
            ),
          ),
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
            label: _progressLabel(
              current: depth.label,
              newestFirst: parsedSnapshots.map(
                (snapshot) => snapshot.topicDepth.current.label,
              ),
            ),
            branch: MindMapBranch.topicDepth,
          ),
        ],
      ));
    }

    if (currentSignal != null && currentSignal.isNotEmpty) {
      branches.add(MindMapNode(
        id: 'current-signal',
        label: '本輪訊號',
        branch: MindMapBranch.currentSignal,
        children: [
          MindMapNode(
            id: 'current-signal-value',
            label: currentSignal,
            branch: MindMapBranch.currentSignal,
          ),
        ],
      ));
    }

    if (confirmedFacts.isNotEmpty) {
      branches.add(_confirmedFactsBranch(confirmedFacts));
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
    currentSignal:
        currentSignal == null || currentSignal.isEmpty ? null : currentSignal,
    confirmedFacts: confirmedFacts,
    topics: aggregate.unionInterests,
    fullNextStep: fullNextStep,
  );
}

const _maxConfirmedFactLeaves = 5;

List<String> _confirmedFacts(String? stored) {
  final serialized = PartnerMemoryTagCatalog.serialize(
    PartnerMemoryTagCatalog.parse(stored),
  );
  if (serialized.isEmpty) return const [];
  return List.unmodifiable(serialized.split('、'));
}

MindMapNode _confirmedFactsBranch(List<String> facts) {
  final hasOverflow = facts.length > _maxConfirmedFactLeaves;
  final directLimit = hasOverflow ? _maxConfirmedFactLeaves - 1 : facts.length;
  return MindMapNode(
    id: 'confirmed-facts',
    label: '已確認資料',
    branch: MindMapBranch.confirmedFacts,
    children: [
      for (var i = 0; i < directLimit; i++)
        MindMapNode(
          id: 'confirmed-fact-$i',
          label: facts[i],
          branch: MindMapBranch.confirmedFacts,
        ),
      if (hasOverflow)
        MindMapNode(
          id: 'confirmed-fact-more',
          label: '另有 ${facts.length - directLimit} 項',
          branch: MindMapBranch.confirmedFacts,
        ),
    ],
  );
}

String _progressLabel({
  required String current,
  required Iterable<String> newestFirst,
}) {
  final history = newestFirst.toList(growable: false);
  if (history.length < 2) return current;
  final previous = history[1];
  if (previous != current) return '$previous → $current';

  var streak = 0;
  for (final label in history) {
    if (label != current) break;
    streak++;
  }
  return '$current（連續 $streak 次）';
}

List<_ParsedMindMapSnapshot> _latestParsedSnapshots({
  required List<Conversation> conversations,
  required List<AnalysisRecord> analysisRecords,
}) {
  final sources = <_MindMapSnapshotSource>[];
  final recordMirrorKeys = <String>{};

  for (final record in analysisRecords) {
    final raw = record.analysisSnapshotJson.trim();
    if (raw.isEmpty) continue;
    recordMirrorKeys.add(_snapshotMirrorKey(record.conversationId, raw));
    sources.add(_MindMapSnapshotSource(
      conversationId: record.conversationId,
      occurredAt: record.createdAt,
      rawJson: raw,
      sourceId: 'record:${record.id}',
      isRecord: true,
    ));
  }

  for (final conversation in conversations) {
    final raw = conversation.lastAnalysisSnapshotJson?.trim();
    if (raw == null || raw.isEmpty) continue;
    if (recordMirrorKeys.contains(_snapshotMirrorKey(conversation.id, raw))) {
      continue;
    }
    sources.add(_MindMapSnapshotSource(
      conversationId: conversation.id,
      occurredAt: conversation.updatedAt,
      rawJson: raw,
      sourceId: 'conversation:${conversation.id}',
      isRecord: false,
    ));
  }

  sources.sort((a, b) {
    final byDate = b.occurredAt.compareTo(a.occurredAt);
    if (byDate != 0) return byDate;
    if (a.isRecord != b.isRecord) return a.isRecord ? -1 : 1;
    return b.sourceId.compareTo(a.sourceId);
  });

  final parsed = <_ParsedMindMapSnapshot>[];
  for (final source in sources) {
    final snapshot = _parseMindMapSnapshot(source);
    if (snapshot == null) continue;
    parsed.add(snapshot);
  }
  return parsed;
}

String _snapshotMirrorKey(String conversationId, String rawJson) =>
    '$conversationId\u0000${rawJson.trim()}';

_ParsedMindMapSnapshot? _parseMindMapSnapshot(
  _MindMapSnapshotSource source,
) {
  try {
    final decoded = jsonDecode(source.rawJson);
    if (decoded is! Map) return null;
    final json = decoded.map(
      (key, value) => MapEntry(key.toString(), value),
    );

    final gameStageJson = _strictOptionalJsonMap(json['gameStage']);
    final topicDepthJson = _strictOptionalJsonMap(json['topicDepth']);
    final rawStrategy = json['strategy'];
    if (rawStrategy != null && rawStrategy is! String) return null;

    final parsedStage = GameStageInfo.fromJson(gameStageJson);
    final parsedDepth = TopicDepth.fromJson(topicDepthJson);
    CoachActionHint? coachActionHint;
    final hintJson = _lenientJsonMap(json['coachActionHint']);
    if (hintJson != null) {
      final parsedHint = CoachActionHint.fromJson(hintJson);
      if (parsedHint.isUsable) coachActionHint = parsedHint;
    }

    return _ParsedMindMapSnapshot(
      conversationId: source.conversationId,
      stageInfo: parsedStage,
      topicDepth: parsedDepth,
      strategy: (rawStrategy as String?)?.trim() ?? '',
      coachActionHint: coachActionHint,
    );
  } catch (_) {
    // 與 partner_aggregates._parseSnapshot 同策略：壞 JSON / 錯 shape 跳過。
    return null;
  }
}

Map<String, dynamic>? _strictOptionalJsonMap(Object? value) {
  if (value == null) return null;
  if (value is! Map) throw const FormatException('Expected object shape');
  return value.map((key, value) => MapEntry(key.toString(), value));
}

Map<String, dynamic>? _lenientJsonMap(Object? value) {
  if (value is! Map) return null;
  return value.map((key, value) => MapEntry(key.toString(), value));
}

class _MindMapSnapshotSource {
  const _MindMapSnapshotSource({
    required this.conversationId,
    required this.occurredAt,
    required this.rawJson,
    required this.sourceId,
    required this.isRecord,
  });

  final String conversationId;
  final DateTime occurredAt;
  final String rawJson;
  final String sourceId;
  final bool isRecord;
}

class _ParsedMindMapSnapshot {
  const _ParsedMindMapSnapshot({
    required this.conversationId,
    required this.stageInfo,
    required this.topicDepth,
    required this.strategy,
    this.coachActionHint,
  });

  final String conversationId;
  final GameStageInfo stageInfo;
  final TopicDepth topicDepth;
  final String strategy;
  final CoachActionHint? coachActionHint;
}
