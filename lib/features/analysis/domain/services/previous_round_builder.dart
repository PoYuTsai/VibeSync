/// 新片段的上一輪脈絡（previousRound，Eric 2026-10-18）：從手機上已經有的資料挑出
/// 「上一輪」，也就是同一個對象的其他片段裡、在這個片段建立之前最近一次的 v3 結果，
/// 再裁成伺服器 `guide_v3/previous_round.ts` 的形狀與上限。不加新的儲存；什麼都
/// 沒有就回 null（請求不帶這個欄位）。
library;

import 'dart:convert';

import 'package:characters/characters.dart';

import '../../../analysis_history/domain/entities/analysis_history_event.dart';
import '../../../coaching_memory/domain/entities/coaching_outcome_event.dart';
import '../../../conversation/domain/entities/conversation.dart';
import '../entities/guide_v3_result.dart';
import '../entities/previous_round_context.dart';

class PreviousRoundBuilder {
  const PreviousRoundBuilder();

  /// 跟伺服器同一組上限：每段文字 120、最多 4 則、全部 600；字數照伺服器算法
  /// （trim 之後的字串長度）。
  static const maxChars = 600;
  static const maxTextChars = 120;
  static const maxMessages = 4;

  static const _snapshotClientMetaKey = '__vibesync_snapshot_meta_v1';
  static const _snapshotHistoryEventIdKey = 'historyEventId';
  static const _snapshotRunIdKey = 'analysisRunId';
  static const _snapshotMessageCountKey = 'messageCount';
  static const _truncationMark = '…';

  PreviousRoundContext? build({
    required Conversation current,
    required List<Conversation> partnerConversations,
    required List<AnalysisHistoryEvent> historyEvents,
    required List<CoachingOutcomeEvent> Function(String conversationId)
        outcomesFor,
  }) {
    final partnerId = _scope(current.partnerId);
    if (partnerId == null) return null;
    final analyzedAtByEventId = <String, DateTime>{
      for (final event in historyEvents)
        if (event.kind == AnalysisHistoryKind.analyze)
          event.id: event.createdAt,
    };
    _Candidate? latest;
    for (final conversation in partnerConversations) {
      if (conversation.id == current.id ||
          _scope(conversation.partnerId) != partnerId ||
          _ownerMismatch(current, conversation)) {
        continue;
      }
      final snapshot =
          _GuideV3Snapshot.tryParse(conversation.lastAnalysisSnapshotJson);
      // 自傷關心那一輪只有固定文案，不帶。
      if (snapshot == null || snapshot.result.isCare) continue;
      // 分析時間看歷史事件（之後的存檔不會改到它）；找不到才退回 updatedAt。
      final analyzedAt = analyzedAtByEventId[snapshot.historyEventId] ??
          conversation.updatedAt;
      // 只認這個片段建立之前就分析完的：比它晚才分析的那段不是「上一輪」。
      if (!analyzedAt.isBefore(current.createdAt)) continue;
      if (latest == null || analyzedAt.isAfter(latest.analyzedAt)) {
        latest = _Candidate(conversation, snapshot, analyzedAt);
      }
    }
    return latest == null ? null : _contextFrom(latest, outcomesFor);
  }

  PreviousRoundContext? _contextFrom(
    _Candidate candidate,
    List<CoachingOutcomeEvent> Function(String conversationId) outcomesFor,
  ) {
    final conversation = candidate.conversation;
    final read = candidate.snapshot.result.read;
    final judgment = _capped(read.judgment);
    final sentCard = _capped(_copiedCard(candidate, outcomesFor) ?? '');
    final analyzedCount = (candidate.snapshot.messageCount ??
            conversation.lastAnalyzedMessageCount ??
            conversation.messages.length)
        .clamp(0, conversation.messages.length)
        .toInt();
    final recent = <PreviousRoundMessage>[
      for (final message in conversation.messages.take(analyzedCount))
        if (_capped(message.content) case final content?)
          PreviousRoundMessage(isFromMe: message.isFromMe, content: content),
    ];
    final messages = recent.length > maxMessages
        ? recent.sublist(recent.length - maxMessages)
        : recent;
    // 超過合計上限就從最舊的一則拿掉：最新的幾則最接近她這次回的。
    final fixed = (judgment?.length ?? 0) + (sentCard?.length ?? 0);
    var total = fixed +
        messages.fold<int>(0, (sum, message) => sum + message.content.length);
    while (messages.isNotEmpty && total > maxChars) {
      total -= messages.removeAt(0).content.length;
    }
    if (judgment == null && sentCard == null && messages.isEmpty) return null;
    return PreviousRoundContext(
      decision: read.decision.wire,
      light: read.light?.wire,
      judgment: judgment,
      sentCard: sentCard,
      messages: List.unmodifiable(messages),
    );
  }

  /// 他複製的那張：複製紀錄的 key 跟分析頁一樣是
  /// `analyze:<片段>:<runId>:v3:<第幾張>:<任務>`，再調過的卡是 `refine:<那個 key>:…`。
  /// 回報「沒送」的不算；複製過好幾張就取最後一次。
  String? _copiedCard(
    _Candidate candidate,
    List<CoachingOutcomeEvent> Function(String conversationId) outcomesFor,
  ) {
    final runId = candidate.snapshot.runId;
    if (runId == null) return null;
    final conversationId = candidate.conversation.id;
    final cardPrefix = 'analyze:$conversationId:$runId:v3:';
    CoachingOutcomeEvent? latest;
    for (final event in outcomesFor(conversationId)) {
      if (event.source != CoachingOutcomeSource.analyze ||
          event.userAction == CoachingUserAction.didNotSend ||
          !(event.id.startsWith(cardPrefix) ||
              event.id.startsWith('refine:$cardPrefix'))) {
        continue;
      }
      if (latest == null || event.createdAt.isAfter(latest.createdAt)) {
        latest = event;
      }
    }
    return latest?.suggestedMoveSummary;
  }

  /// trim；空的回 null；超過 120 就照字（不切開 emoji）截到 119 再加「…」。
  String? _capped(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    if (text.length <= maxTextChars) return text;
    final buffer = StringBuffer();
    var used = 0;
    for (final cluster in text.characters) {
      if (used + cluster.length > maxTextChars - _truncationMark.length) break;
      buffer.write(cluster);
      used += cluster.length;
    }
    return '${buffer.toString().trimRight()}$_truncationMark';
  }

  bool _ownerMismatch(Conversation current, Conversation other) =>
      current.ownerUserId != null &&
      other.ownerUserId != null &&
      current.ownerUserId != other.ownerUserId;

  String? _scope(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

class _Candidate {
  const _Candidate(this.conversation, this.snapshot, this.analyzedAt);

  final Conversation conversation;
  final _GuideV3Snapshot snapshot;
  final DateTime analyzedAt;
}

/// 對話快照裡的 v3 結果與存檔時的 meta（歷史事件 id、伺服器 runId、分析了幾則）。
class _GuideV3Snapshot {
  const _GuideV3Snapshot({
    required this.result,
    required this.historyEventId,
    required this.runId,
    required this.messageCount,
  });

  final GuideV3Result result;
  final String? historyEventId;
  final String? runId;
  final int? messageCount;

  static _GuideV3Snapshot? tryParse(String? snapshotJson) {
    if (snapshotJson == null || snapshotJson.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(snapshotJson);
      if (decoded is! Map) return null;
      final payload = decoded.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      final meta = payload.remove(PreviousRoundBuilder._snapshotClientMetaKey);
      if (!isGuideV3Payload(payload)) return null;
      final result = GuideV3Result.fromJson(payload);
      if (result == null) return null;
      String? text(Object? value) =>
          value is String && value.trim().isNotEmpty ? value.trim() : null;
      final rawCount = meta is Map
          ? meta[PreviousRoundBuilder._snapshotMessageCountKey]
          : null;
      return _GuideV3Snapshot(
        result: result,
        historyEventId: meta is Map
            ? text(meta[PreviousRoundBuilder._snapshotHistoryEventIdKey])
            : null,
        runId: meta is Map
            ? text(meta[PreviousRoundBuilder._snapshotRunIdKey])
            : null,
        messageCount: rawCount is int ? rawCount : null,
      );
    } catch (_) {
      return null;
    }
  }
}
