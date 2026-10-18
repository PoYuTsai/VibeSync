/// 新片段的上一輪脈絡（previousRound，Eric 2026-10-18）：從手機上已經有的資料挑出
/// 「上一輪」，也就是同一個對象的其他片段裡、在這個片段建立之前最近一次的分析；
/// 它是 v3 結果（不是自傷關心）才裁成伺服器 `guide_v3/previous_round.ts` 的形狀與
/// 上限。不加新的儲存；什麼都沒有就回 null（請求不帶這個欄位）。
library;

import 'dart:convert';

import 'package:characters/characters.dart';

import '../../../analysis_history/domain/entities/analysis_history_event.dart';
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
  static const _snapshotMessageCountKey = 'messageCount';
  static const _truncationMark = '…';

  PreviousRoundContext? build({
    required Conversation current,
    required List<Conversation> partnerConversations,
    required List<AnalysisHistoryEvent> historyEvents,
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
          _AnalyzedSnapshot.tryParse(conversation.lastAnalysisSnapshotJson);
      if (snapshot == null) continue;
      // 分析時間看歷史事件（之後的存檔不會改到它）；找不到才退回 updatedAt。
      final analyzedAt = analyzedAtByEventId[snapshot.historyEventId] ??
          conversation.updatedAt;
      // 只認這個片段建立之前就分析完的：比它晚才分析的那段不是「上一輪」。
      if (!analyzedAt.isBefore(current.createdAt)) continue;
      if (latest == null || analyzedAt.isAfter(latest.analyzedAt)) {
        latest = _Candidate(conversation, snapshot, analyzedAt);
      }
    }
    final result = latest?.snapshot.guideV3;
    // 上一輪是 v2 或自傷關心（只有固定文案）就不帶，也不跳去更早的那段：更早的那段
    // 已經不是上一輪了。
    if (latest == null || result == null || result.isCare) return null;
    return _contextFrom(latest, result);
  }

  PreviousRoundContext? _contextFrom(
    _Candidate candidate,
    GuideV3Result result,
  ) {
    final conversation = candidate.conversation;
    final read = result.read;
    final judgment = _capped(read.judgment);
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
    // 超過合計上限就從最舊的一則拿掉：最新的幾則最接近她這次回的（判讀＋4 則
    // 各 120 剛好 600，這條是之後改上限時的保險）。
    var total = (judgment?.length ?? 0) +
        messages.fold<int>(0, (sum, message) => sum + message.content.length);
    while (messages.isNotEmpty && total > maxChars) {
      total -= messages.removeAt(0).content.length;
    }
    if (judgment == null && messages.isEmpty) return null;
    return PreviousRoundContext(
      decision: read.decision.wire,
      light: read.light?.wire,
      judgment: judgment,
      messages: List.unmodifiable(messages),
    );
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
  final _AnalyzedSnapshot snapshot;
  final DateTime analyzedAt;
}

/// 對話快照（v2 或 v3）與存檔時的 meta（歷史事件 id、分析了幾則）。
/// [guideV3] 只有 v3 結果才有；v2、或認不出來的 v3 是 null。
class _AnalyzedSnapshot {
  const _AnalyzedSnapshot({
    required this.guideV3,
    required this.historyEventId,
    required this.messageCount,
  });

  final GuideV3Result? guideV3;
  final String? historyEventId;
  final int? messageCount;

  static _AnalyzedSnapshot? tryParse(String? snapshotJson) {
    if (snapshotJson == null || snapshotJson.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(snapshotJson);
      if (decoded is! Map) return null;
      final payload = decoded.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      final meta = payload.remove(PreviousRoundBuilder._snapshotClientMetaKey);
      if (payload.isEmpty) return null;
      final result =
          isGuideV3Payload(payload) ? GuideV3Result.fromJson(payload) : null;
      String? text(Object? value) =>
          value is String && value.trim().isNotEmpty ? value.trim() : null;
      final rawCount = meta is Map
          ? meta[PreviousRoundBuilder._snapshotMessageCountKey]
          : null;
      return _AnalyzedSnapshot(
        guideV3: result,
        historyEventId: meta is Map
            ? text(meta[PreviousRoundBuilder._snapshotHistoryEventIdKey])
            : null,
        messageCount: rawCount is int ? rawCount : null,
      );
    } catch (_) {
      return null;
    }
  }
}
