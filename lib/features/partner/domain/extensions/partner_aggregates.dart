import 'dart:convert';

import 'package:vibesync/features/analysis/domain/entities/guide_v3_result.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';

class PartnerAggregateView {
  final List<String> unionInterests;
  final List<String> unionTraits;
  final String? unionNotes;
  final int? latestHeat;
  final int totalRounds;
  final int totalMessages;
  final DateTime? lastInteraction;

  /// 最近更新那段對話的分析是 v3（任務卡）。v3 沒有熱度，[latestHeat] 是 null
  /// 不代表還沒分析：顯示端要分開「沒分析過」跟「分析過但不算熱度」。
  final bool latestIsGuideV3;

  /// 最近更新那段對話的 v3 訊號（燈號、決定、邀約進度、冷訊號）；那段不是 v3 或讀不懂就是
  /// null。首頁卡的狀態與新話題都讀這份，不分方案（Eric 2026-10-18）。
  final PartnerGuideV3Signals? latestGuideV3Signals;

  const PartnerAggregateView({
    required this.unionInterests,
    required this.unionTraits,
    required this.unionNotes,
    required this.latestHeat,
    required this.totalRounds,
    required this.totalMessages,
    required this.lastInteraction,
    this.latestIsGuideV3 = false,
    this.latestGuideV3Signals,
  });

  factory PartnerAggregateView.empty() => const PartnerAggregateView(
        unionInterests: [],
        unionTraits: [],
        unionNotes: null,
        latestHeat: null,
        totalRounds: 0,
        totalMessages: 0,
        lastInteraction: null,
      );
}

/// 一次 v3 分析留給其他功能用的訊號（伺服器判讀的 decision／light／inviteReadiness／cold）。
/// 關心（care）不帶燈號：畫面本來就不給 care 顯示燈號，邀約進度與冷訊號伺服器也不送。
class PartnerGuideV3Signals {
  final GuideV3Decision decision;
  final GuideV3Light? light;
  final GuideV3InviteReadiness? inviteReadiness;

  /// 這一輪是 C1「他連續主動兩次、她都只回敷衍的字」判的先別回；舊快照是 null。
  final bool? c1;

  /// 她最近連續幾輪只回敷衍的字；舊快照是 null。
  final int? herPerfunctoryStreak;

  const PartnerGuideV3Signals({
    required this.decision,
    this.light,
    this.inviteReadiness,
    this.c1,
    this.herPerfunctoryStreak,
  });

  factory PartnerGuideV3Signals.fromRead(GuideV3Read read) {
    final isCare = read.decision == GuideV3Decision.care;
    return PartnerGuideV3Signals(
      decision: read.decision,
      light: isCare ? null : read.light,
      inviteReadiness: read.inviteReadiness,
      c1: read.cold?.c1,
      herPerfunctoryStreak: read.cold?.herPerfunctoryStreak,
    );
  }
}

const int _kMaxTags = 8;
const int _kMaxNotes = 8;

extension PartnerAggregates on Partner {
  PartnerAggregateView aggregateOver(List<Conversation> conversations) {
    if (conversations.isEmpty) return PartnerAggregateView.empty();

    final descByDate = [...conversations]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    final parsedDesc = <_Parsed>[];
    for (final c in descByDate) {
      final p = _parseSnapshot(c.updatedAt, c.lastAnalysisSnapshotJson);
      if (p != null) parsedDesc.add(p);
    }

    final unionInterests =
        _rankByRecency(parsedDesc, (p) => p.interests, cap: _kMaxTags);
    final unionTraits =
        _rankByRecency(parsedDesc, (p) => p.traits, cap: _kMaxTags);

    final unionNoteLines = _rankNotesByRecency(parsedDesc, cap: _kMaxNotes);
    final unionNotes =
        unionNoteLines.isEmpty ? null : unionNoteLines.join('\n');

    final totalRounds =
        conversations.fold<int>(0, (s, c) => s + c.currentRound);
    final totalMessages =
        conversations.fold<int>(0, (s, c) => s + c.messages.length);
    final latestGuideV3 =
        _guideV3Snapshot(descByDate.first.lastAnalysisSnapshotJson);

    return PartnerAggregateView(
      unionInterests: unionInterests,
      unionTraits: unionTraits,
      unionNotes: unionNotes,
      latestHeat: descByDate.first.lastEnthusiasmScore,
      totalRounds: totalRounds,
      totalMessages: totalMessages,
      lastInteraction: descByDate.first.updatedAt,
      latestIsGuideV3: latestGuideV3 != null,
      latestGuideV3Signals: latestGuideV3?.signals,
    );
  }
}

/// v3 快照（[isGuideV3Payload]）才回非 null；判讀讀不懂時 signals 是 null。
({PartnerGuideV3Signals? signals})? _guideV3Snapshot(String? jsonStr) {
  if (jsonStr == null || jsonStr.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(jsonStr);
    if (!isGuideV3Payload(decoded)) return null;
    final read = GuideV3Read.fromJson((decoded as Map)['read']);
    return (
      signals: read == null ? null : PartnerGuideV3Signals.fromRead(read)
    );
  } catch (_) {
    return null;
  }
}

class _Parsed {
  final DateTime updatedAt;
  final List<String> interests;
  final List<String> traits;
  final List<String> notes;

  const _Parsed({
    required this.updatedAt,
    required this.interests,
    required this.traits,
    required this.notes,
  });
}

_Parsed? _parseSnapshot(DateTime updatedAt, String? jsonStr) {
  if (jsonStr == null || jsonStr.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(jsonStr);
    if (decoded is! Map) return null;
    final tp = decoded['targetProfile'];
    if (tp is! Map) return null;
    // v1 以前的 targetProfile 只有模型字串陣列，沒有任何可核對出處。
    // 這些舊標籤可以留在歷史快照，但不得再升格成跨輪記憶或新話題事實。
    if (tp['provenanceVersion'] != 1) return null;
    return _Parsed(
      updatedAt: updatedAt,
      interests: _stringList(tp['interests']),
      traits: _stringList(tp['traits']),
      notes: _stringList(tp['notes']),
    );
  } catch (_) {
    return null;
  }
}

List<String> _stringList(Object? value) => value is List
    ? value
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList()
    : const [];

List<String> _rankByRecency(
  List<_Parsed> descByDate,
  List<String> Function(_Parsed) extract, {
  required int cap,
}) {
  final seen = <String>{};
  final result = <String>[];
  for (final p in descByDate) {
    for (final tag in extract(p)) {
      if (seen.add(tag)) {
        result.add(tag);
        if (result.length >= cap) return result;
      }
    }
  }
  return result;
}

List<String> _rankNotesByRecency(
  List<_Parsed> descByDate, {
  required int cap,
}) {
  final seen = <String>{};
  final result = <_NoteCandidate>[];
  for (final p in descByDate) {
    for (var i = 0; i < p.notes.length; i++) {
      final raw = p.notes[i];
      final note = raw.trim();
      if (note.isEmpty) continue;

      final key = _normalizeNoteKey(note);
      if (key.isEmpty || seen.contains(key)) continue;

      seen.add(key);
      if (_isNearDuplicateNote(key, result)) continue;

      result.add(_NoteCandidate(
        note: note,
        updatedAt: p.updatedAt,
        sourceOrder: i,
      ));
      if (result.length >= cap) return _displayNotesInTimelineOrder(result);
    }
  }
  return _displayNotesInTimelineOrder(result);
}

List<String> _displayNotesInTimelineOrder(List<_NoteCandidate> notes) {
  final sorted = [...notes]..sort((a, b) {
      final byDate = a.updatedAt.compareTo(b.updatedAt);
      if (byDate != 0) return byDate;
      return a.sourceOrder.compareTo(b.sourceOrder);
    });
  return sorted.map((candidate) => candidate.note).toList();
}

bool _isNearDuplicateNote(
  String normalizedNote,
  List<_NoteCandidate> existingNotes,
) {
  for (final existing in existingNotes) {
    final existingKey = _normalizeNoteKey(existing.note);
    if (existingKey == normalizedNote) return true;
    if (normalizedNote.length < 6 || existingKey.length < 6) continue;
    if (_hasDifferentNegationSignal(normalizedNote, existingKey)) continue;
    if (normalizedNote.contains(existingKey) ||
        existingKey.contains(normalizedNote)) {
      return true;
    }
    final maxLength = normalizedNote.length > existingKey.length
        ? normalizedNote.length
        : existingKey.length;
    if (maxLength <= 24 &&
        _levenshteinDistance(normalizedNote, existingKey) <= 2) {
      return true;
    }
  }
  return false;
}

bool _hasDifferentNegationSignal(String a, String b) {
  return _hasNegationSignal(a) != _hasNegationSignal(b);
}

bool _hasNegationSignal(String value) {
  const tokens = ['不', '無', '沒', '別', 'not', 'no', 'never', 'cannot'];
  return tokens.any(value.contains);
}

class _NoteCandidate {
  final String note;
  final DateTime updatedAt;
  final int sourceOrder;

  const _NoteCandidate({
    required this.note,
    required this.updatedAt,
    required this.sourceOrder,
  });
}

String _normalizeNoteKey(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[\s，。！？、,.!?;；:：「」『』（）()【】\[\]…·\-—_]+'), '');
}

int _levenshteinDistance(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  var previous = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 0; i < a.length; i++) {
    final current = List<int>.filled(b.length + 1, 0);
    current[0] = i + 1;
    for (var j = 0; j < b.length; j++) {
      final cost = a[i] == b[j] ? 0 : 1;
      final insertion = current[j] + 1;
      final deletion = previous[j + 1] + 1;
      final substitution = previous[j] + cost;
      current[j + 1] = insertion < deletion
          ? (insertion < substitution ? insertion : substitution)
          : (deletion < substitution ? deletion : substitution);
    }
    previous = current;
  }
  return previous[b.length];
}
