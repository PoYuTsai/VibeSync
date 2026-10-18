/// 新片段的上一輪脈絡（previousRound，Eric 2026-10-18）：從手機上已經有的資料挑出
/// 「上一輪」，也就是同一個對象裡、緊接在這個片段前面建立的那一段；那一段的分析
/// 確定在這個片段建立之前完成、是 v3 結果（不是自傷關心）、分析紀錄也還在（沒被刪），
/// 才裁成伺服器 `guide_v3/previous_round.ts` 的形狀與上限。任何一關不過就回 null
/// （請求不帶這個欄位），絕不改拿更早的片段。不加新的儲存。
library;

import 'dart:convert';

import 'package:characters/characters.dart';

import '../../../analysis_history/domain/entities/analysis_history_event.dart';
import '../../../conversation/domain/entities/conversation.dart';
import '../entities/analysis_record.dart';
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
  static const _truncationMark = '…';

  PreviousRoundContext? build({
    required Conversation current,
    required List<Conversation> partnerConversations,
    required List<AnalysisHistoryEvent> historyEvents,
    // 那段對話現在的分析紀錄（紀錄庫的 currentFor）；被刪掉或沒有就是 null。
    required AnalysisRecord? Function(Conversation conversation) liveRecordFor,
  }) {
    final partnerId = _scope(current.partnerId);
    if (partnerId == null) return null;
    // 片段的先後照建立時間排（建立之後不會變），不看分析時間：分析時間會被重新分析、
    // 補寫的歷史事件改掉，拿它篩選會跳過真正的上一段、改送更早那段（主審第 2 輪 P2）。
    // 沒有訊息的空白片段只是畫面的佔位（離開就刪），不算一段。
    Conversation? previous;
    var tied = false;
    for (final conversation in partnerConversations) {
      if (conversation.id == current.id ||
          _scope(conversation.partnerId) != partnerId ||
          _ownerMismatch(current, conversation) ||
          conversation.messages.isEmpty) {
        continue;
      }
      final createdAt = conversation.createdAt;
      // 跟這個片段同一刻建立：分不出先後。
      if (createdAt.isAtSameMomentAs(current.createdAt)) return null;
      if (!createdAt.isBefore(current.createdAt)) continue;
      if (previous == null || createdAt.isAfter(previous.createdAt)) {
        previous = conversation;
        tied = false;
      } else if (createdAt.isAtSameMomentAs(previous.createdAt)) {
        tied = true;
      }
    }
    // 只驗這一段；下面任何一關不過就不帶，絕不往更早找。
    if (previous == null || tied) return null;
    final snapshot =
        _AnalyzedSnapshot.tryParse(previous.lastAnalysisSnapshotJson);
    // 上一段還沒分析過（例如有內容的草稿）。
    if (snapshot == null) return null;
    // 時間要確定在這個片段建立之前：那次分析的歷史事件要在，而且事件與那段對話最後一次
    // 存檔（快照就是在那次寫的）都早於這個片段建立。重新分析會覆寫快照、重存對話，第一筆
    // 事件沒寫進去時還會補寫成重新分析的時間；事件缺了或任一時間不早於這個片段，都當不
    // 知道快照是不是這個片段之前的（主審第 1、2 輪 P2）。改名之類的存檔也會讓這次不帶，
    // 寧可少帶。
    final firstAnalyzedAt =
        _analysisEventTime(historyEvents, snapshot.historyEventId);
    if (firstAnalyzedAt == null ||
        !firstAnalyzedAt.isBefore(current.createdAt) ||
        !previous.updatedAt.isBefore(current.createdAt)) {
      return null;
    }
    final result = snapshot.guideV3;
    // 上一輪是 v2 或自傷關心（只有固定文案）。
    if (result == null || result.isCare) return null;
    // 那次分析的紀錄被刪了（舊制多筆、部分紀錄刪除時對話本身還在），或紀錄跟快照不是
    // 同一次（主審第 1 輪 P2）。訊息只取那筆紀錄自己的片段，同一段對話裡被刪掉的較早
    // 紀錄不會混進來。
    final record = liveRecordFor(previous);
    if (record == null ||
        !_sameJson(record.analysisSnapshotJson, snapshot.payload)) {
      return null;
    }
    return _contextFrom(record, result);
  }

  DateTime? _analysisEventTime(
    List<AnalysisHistoryEvent> events,
    String? eventId,
  ) {
    if (eventId == null) return null;
    for (final event in events) {
      if (event.kind == AnalysisHistoryKind.analyze && event.id == eventId) {
        return event.createdAt;
      }
    }
    return null;
  }

  PreviousRoundContext? _contextFrom(
    AnalysisRecord record,
    GuideV3Result result,
  ) {
    final read = result.read;
    final judgment = _capped(read.judgment);
    final recent = <PreviousRoundMessage>[
      for (final message in record.messages)
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

  /// 紀錄存的是分析結果原樣的 JSON，對話快照是同一份再加上 App 的 meta；比內容不比字串。
  bool _sameJson(String recordSnapshotJson, Map<String, dynamic> payload) {
    try {
      return _jsonEquals(jsonDecode(recordSnapshotJson), payload);
    } catch (_) {
      return false;
    }
  }

  bool _jsonEquals(Object? a, Object? b) {
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final key in a.keys) {
        if (!b.containsKey(key) || !_jsonEquals(a[key], b[key])) return false;
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_jsonEquals(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
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

/// 對話快照（v2 或 v3）、去掉 App meta 的分析結果原樣，以及存檔時的歷史事件 id。
/// [guideV3] 只有 v3 結果才有；v2、或認不出來的 v3 是 null。
class _AnalyzedSnapshot {
  const _AnalyzedSnapshot({
    required this.guideV3,
    required this.payload,
    required this.historyEventId,
  });

  final GuideV3Result? guideV3;
  final Map<String, dynamic> payload;
  final String? historyEventId;

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
      return _AnalyzedSnapshot(
        guideV3: result,
        payload: payload,
        historyEventId: meta is Map
            ? text(meta[PreviousRoundBuilder._snapshotHistoryEventIdKey])
            : null,
      );
    } catch (_) {
      return null;
    }
  }
}
