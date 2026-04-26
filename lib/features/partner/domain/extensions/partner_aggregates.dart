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

    final notesOldestFirst =
        parsedDesc.reversed.expand((p) => p.notes).toList();
    final unionNotes =
        notesOldestFirst.isEmpty ? null : notesOldestFirst.join('\n');

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
