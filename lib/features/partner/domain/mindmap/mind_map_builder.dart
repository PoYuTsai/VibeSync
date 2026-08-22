import 'dart:convert';

import '../../../analysis/domain/entities/analysis_models.dart';
import '../../../analysis/domain/entities/analysis_record.dart';
import '../../../analysis/domain/entities/game_stage.dart';
import '../../../conversation/domain/entities/conversation.dart';
import '../../../conversation/domain/entities/session_context.dart';
import '../extensions/partner_aggregates.dart';
import '../services/partner_memory_tag_catalog.dart';
import 'mind_map_models.dart';

/// 把對象的既有分析資料組成作戰板節點樹。
///
/// 資料來源（與 partner_aggregates 同一套快照，不打任何新 API）：
/// - 階段 / 話題深度 / 下一步：最新一筆可完整解析（JSON + shape）的分析
///   紀錄；沒有獨立紀錄的舊資料才回退到 lastAnalysisSnapshotJson。
/// - 目前狀態 / 連續次數 / 歷程：依可解析的獨立分析紀錄計算；Conversation
///   裡相同快照只是鏡像，不重複計次。
/// - 互動脈絡：最近三次優先採既有高信心 catchablePoint，否則引用該次
///   真實聊天摘錄；更舊分析濃縮成階段與話題深度歷程，不新增 AI 呼叫。
/// - 已確認資料：Partner.customNote 經 allowlist chips 解析，舊自由文字不採用。
/// - AI 聚合興趣 / 特質不進「關於她」節點；aggregate 興趣只保留給既有
///   作戰重點 panel 的可接話題。
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
  GameStageInfo? stageInfo;
  _ParsedMindMapSnapshot? stageSnapshot;
  TopicDepth? topicDepth;
  for (final snapshot in parsedSnapshots) {
    if (stageInfo == null && snapshot.stageInfo != null) {
      stageInfo = snapshot.stageInfo;
      stageSnapshot = snapshot;
    }
    topicDepth ??= snapshot.topicDepth;
    if (stageInfo != null && topicDepth != null) break;
  }
  final snapshotConversationId = latestSnapshot?.conversationId;
  final currentSignal = latestSnapshot?.coachActionHint?.catchablePoint.trim();
  final confirmedFacts = _confirmedFacts(partnerCustomNote);

  ({GameStage stage, bool reconnectWording})? fallbackStage;
  for (final c in descByDate) {
    final parsed = GameStage.tryFromString(c.currentGameStage);
    if (parsed != null) {
      fallbackStage = (
        stage: parsed,
        reconnectWording: parsed == GameStage.opening &&
            c.sessionContext?.meetingContext == MeetingContext.committedPartner,
      );
      break;
    }
  }

  final hasAnalysisData = parsedSnapshots.isNotEmpty || fallbackStage != null;
  final branches = <MindMapNode>[];
  String? relationshipSignal;
  String? fullNextStep;

  if (hasAnalysisData) {
    if (stageInfo != null || fallbackStage != null) {
      final stage = stageInfo?.current ?? fallbackStage!.stage;
      final reconnectWording = stageInfo != null
          ? stageSnapshot!.reconnectWording
          : fallbackStage!.reconnectWording;
      final currentStageLabel = _visibleStageLabel(
        stage,
        reconnectWording: reconnectWording,
      );
      relationshipSignal = reconnectWording && stage == GameStage.opening
          ? '這輪重點是重新接上互動，不代表關係退回陌生人'
          : stage.description;
      branches.add(MindMapNode(
        id: 'stage',
        label: '目前互動重點',
        branch: MindMapBranch.stage,
        children: _progressNodes(
          idPrefix: 'stage',
          branch: MindMapBranch.stage,
          current: currentStageLabel,
          newestFirst: parsedSnapshots.map(
            (snapshot) => snapshot.visibleStageLabel,
          ),
        ),
      ));
    }

    if (topicDepth != null) {
      final depth = topicDepth.current;
      branches.add(MindMapNode(
        id: 'depth',
        label: '話題深度',
        branch: MindMapBranch.topicDepth,
        children: _progressNodes(
          idPrefix: 'depth',
          branch: MindMapBranch.topicDepth,
          current: depth.label,
          newestFirst: parsedSnapshots.map(
            (snapshot) => snapshot.topicDepth?.current.label,
          ),
        ),
      ));
    }

    final recentInteractionNodes = _recentInteractionNodes(parsedSnapshots);
    if (recentInteractionNodes.isNotEmpty) {
      branches.add(MindMapNode(
        id: 'interaction-history',
        label: '互動脈絡',
        branch: MindMapBranch.interactionHistory,
        children: recentInteractionNodes,
      ));
    }

    branches.add(_confirmedFactsBranch(confirmedFacts));

    if (latestSnapshot != null) {
      final nextStep = latestSnapshot.effectiveNextStep;
      if (nextStep.isNotEmpty) {
        fullNextStep = nextStep;
        final previousNextStep = parsedSnapshots.length >= 2
            ? parsedSnapshots[1].effectiveNextStep
            : null;
        final updateLabel = previousNextStep == nextStep ? '沿用上輪' : '本輪更新';
        branches.add(MindMapNode(
          id: 'next',
          label: '下一步',
          branch: MindMapBranch.nextStep,
          children: [
            // 打開作戰板就直接看得到完整行動；點擊只負責額外導向問教練，
            // 不是閱讀全文的必要步驟。
            MindMapNode(
              id: 'next-step',
              label: '$updateLabel｜$nextStep',
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
      label: parsedSnapshots.isEmpty
          ? partnerName
          : '$partnerName・已分析 ${parsedSnapshots.length} 次',
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

List<MindMapNode> _recentInteractionNodes(
  List<_ParsedMindMapSnapshot> snapshots,
) {
  const prefixes = ['本輪', '上輪', '上上輪'];
  final nodes = <MindMapNode>[];
  for (var i = 0; i < snapshots.length && i < prefixes.length; i++) {
    final trustedSignal =
        snapshots[i].coachActionHint?.catchablePoint.trim() ?? '';
    final fallbackHighlight = snapshots[i].fallbackHighlight.trim();
    final highlight = trustedSignal.isNotEmpty
        ? trustedSignal
        : fallbackHighlight.isNotEmpty
            ? fallbackHighlight
            : '沒有足夠可確認的聊天摘錄';
    nodes.add(MindMapNode(
      id: 'interaction-$i',
      label: '${prefixes[i]}｜$highlight',
      branch: i == 0 && trustedSignal.isNotEmpty
          ? MindMapBranch.currentSignal
          : MindMapBranch.interactionHistory,
    ));
  }
  if (snapshots.length > prefixes.length) {
    final older = snapshots.skip(prefixes.length).toList(growable: false);
    final stagePath = _transitionPath(
      older.map((snapshot) => snapshot.visibleStageLabel),
    );
    final depthPath = _transitionPath(
      older.map((snapshot) => snapshot.topicDepth?.current.label),
    );
    nodes.add(MindMapNode(
      id: 'interaction-older',
      label: '前 ${older.length} 次｜'
          '互動重點：${stagePath.isEmpty ? '未確認' : stagePath}；'
          '話題：${depthPath.isEmpty ? '未確認' : depthPath}',
      branch: MindMapBranch.interactionHistory,
    ));
  }
  return nodes;
}

String _transitionPath(Iterable<String?> newestFirst) {
  final transitions = <String>[];
  for (final rawLabel in newestFirst.toList(growable: false).reversed) {
    final label = rawLabel?.trim();
    if (label == null || label.isEmpty) continue;
    if (transitions.isEmpty || transitions.last != label) {
      transitions.add(label);
    }
  }
  if (transitions.length > 4) {
    return '${transitions.first} → … → '
        '${transitions[transitions.length - 2]} → ${transitions.last}';
  }
  return transitions.join(' → ');
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
    label: '關於她（已確認）',
    branch: MindMapBranch.confirmedFacts,
    children: [
      if (facts.isEmpty)
        const MindMapNode(
          id: 'confirmed-fact-empty',
          label: '尚無已確認資料',
          branch: MindMapBranch.confirmedFacts,
        ),
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

List<MindMapNode> _progressNodes({
  required String idPrefix,
  required MindMapBranch branch,
  required String current,
  required Iterable<String?> newestFirst,
}) {
  final history = newestFirst.toList(growable: false);
  var streak = 0;
  for (final label in history) {
    if (label != current) break;
    streak++;
  }
  final currentLabel = streak >= 2 ? '$current（連續 $streak 次）' : current;
  final nodes = <MindMapNode>[
    MindMapNode(
      id: '$idPrefix-current',
      label: currentLabel,
      branch: branch,
    ),
  ];
  final path = _transitionPath(history);
  if (path.isNotEmpty && path != current) {
    nodes.add(MindMapNode(
      id: '$idPrefix-history',
      label: '歷程：$path',
      branch: branch,
    ));
  }
  return nodes;
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
      reconnectWording: record.gameStageLabel.trim() == '重新連線',
      fallbackHighlight: _analysisRecordArchiveTitle(record),
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
      reconnectWording: _snapshotIsReconnect(raw) ??
          conversation.sessionContext?.meetingContext ==
              MeetingContext.committedPartner,
      fallbackHighlight: _conversationArchiveTitle(conversation),
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

const _snapshotClientMetaKey = '__vibesync_snapshot_meta_v1';
const _snapshotIsReconnectKey = 'isReconnect';

bool? _snapshotIsReconnect(String rawJson) {
  try {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map) return null;
    final meta = decoded[_snapshotClientMetaKey];
    if (meta is! Map) return null;
    final value = meta[_snapshotIsReconnectKey];
    return value is bool ? value : null;
  } catch (_) {
    return null;
  }
}

String _snapshotMirrorKey(String conversationId, String rawJson) =>
    '$conversationId\u0000${_normalizedSnapshotPayload(rawJson)}';

String _normalizedSnapshotPayload(String rawJson) {
  final trimmed = rawJson.trim();
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is! Map) return trimmed;
    final snapshot = decoded.map(
      (key, value) => MapEntry(key.toString(), value),
    )..remove(_snapshotClientMetaKey);
    return jsonEncode(snapshot);
  } catch (_) {
    // 損壞的舊資料仍沿用原始字串比對，避免正規化失敗影響作戰板顯示。
    return trimmed;
  }
}

String _analysisRecordArchiveTitle(AnalysisRecord record) {
  final hasSavedText = record.messages.any(
    (message) => message.content.trim().isNotEmpty,
  );
  return hasSavedText ? record.archiveTitle : '';
}

String _conversationArchiveTitle(Conversation conversation) {
  if (conversation.messages.isEmpty) return '';
  final message = conversation.messages.reversed.firstWhere(
    (item) => !item.isFromMe,
    orElse: () => conversation.messages.last,
  );
  final normalized = message.content.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty) return '';
  final preview =
      normalized.length <= 32 ? normalized : '${normalized.substring(0, 32)}…';
  final speaker = message.isFromMe ? '你說' : '她說';
  return '$speaker：「$preview」';
}

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

    final stageCandidate = _hasNonEmptyCurrent(gameStageJson)
        ? GameStageInfo.fromJson(gameStageJson)
        : null;
    final parsedStage =
        stageCandidate?.hasValidStage == true ? stageCandidate : null;
    final parsedDepth = _hasNonEmptyCurrent(topicDepthJson)
        ? TopicDepth.fromJson(topicDepthJson)
        : null;
    CoachActionHint? coachActionHint;
    final hintJson = _lenientJsonMap(json['coachActionHint']);
    if (hintJson != null) {
      final parsedHint = CoachActionHint.fromJson(hintJson);
      if (parsedHint.isUsable) coachActionHint = parsedHint;
    }

    return _ParsedMindMapSnapshot(
      conversationId: source.conversationId,
      stageInfo: parsedStage,
      reconnectWording: source.reconnectWording,
      topicDepth: parsedDepth,
      strategy: (rawStrategy as String?)?.trim() ?? '',
      coachActionHint: coachActionHint,
      fallbackHighlight: source.fallbackHighlight,
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

bool _hasNonEmptyCurrent(Map<String, dynamic>? json) {
  final current = json?['current'];
  return current is String && current.trim().isNotEmpty;
}

class _MindMapSnapshotSource {
  const _MindMapSnapshotSource({
    required this.conversationId,
    required this.occurredAt,
    required this.rawJson,
    required this.sourceId,
    required this.isRecord,
    required this.reconnectWording,
    required this.fallbackHighlight,
  });

  final String conversationId;
  final DateTime occurredAt;
  final String rawJson;
  final String sourceId;
  final bool isRecord;
  final bool reconnectWording;
  final String fallbackHighlight;
}

class _ParsedMindMapSnapshot {
  const _ParsedMindMapSnapshot({
    required this.conversationId,
    required this.stageInfo,
    required this.reconnectWording,
    required this.topicDepth,
    required this.strategy,
    required this.fallbackHighlight,
    this.coachActionHint,
  });

  final String conversationId;
  final GameStageInfo? stageInfo;
  final bool reconnectWording;
  final TopicDepth? topicDepth;
  final String strategy;
  final String fallbackHighlight;
  final CoachActionHint? coachActionHint;

  String? get visibleStageLabel {
    final stage = stageInfo?.current;
    if (stage == null) return null;
    return _visibleStageLabel(stage, reconnectWording: reconnectWording);
  }

  String get effectiveNextStep {
    final nextStep = stageInfo?.nextStep.trim() ?? '';
    return nextStep.isNotEmpty ? nextStep : strategy.trim();
  }
}

String _visibleStageLabel(
  GameStage stage, {
  required bool reconnectWording,
}) {
  if (stage == GameStage.opening && reconnectWording) return '重新連線';
  return stage.label;
}
