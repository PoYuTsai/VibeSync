import 'dart:convert';

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

  const PartnerAggregateView({
    required this.unionInterests,
    required this.unionTraits,
    required this.unionNotes,
    required this.latestHeat,
    required this.totalRounds,
    required this.totalMessages,
    required this.lastInteraction,
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

    return PartnerAggregateView(
      unionInterests: unionInterests,
      unionTraits: unionTraits,
      unionNotes: unionNotes,
      latestHeat: descByDate.first.lastEnthusiasmScore,
      totalRounds: totalRounds,
      totalMessages: totalMessages,
      lastInteraction: descByDate.first.updatedAt,
    );
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
    return _Parsed(
      updatedAt: updatedAt,
      interests: (tp['interests'] as List?)?.cast<String>() ?? const [],
      traits: (tp['traits'] as List?)?.cast<String>() ?? const [],
      notes: (tp['notes'] as List?)?.cast<String>() ?? const [],
    );
  } catch (_) {
    return null;
  }
}

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
