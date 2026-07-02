import 'dart:convert';

import '../../../../core/services/storage_service.dart';
import 'opener_service.dart';

class OpenerDraft {
  const OpenerDraft({
    required this.id,
    required this.result,
    required this.createdAt,
    this.displayName,
    this.sourceLabel,
    this.inputPreview,
    this.continuedAt,
    this.partnerId,
  });

  final String id;
  final OpenerResult result;
  final DateTime createdAt;
  final String? displayName;
  final String? sourceLabel;
  final String? inputPreview;
  final DateTime? continuedAt;
  final String? partnerId;

  String get title {
    final name = displayName?.trim();
    if (name != null && name.isNotEmpty) {
      return name;
    }

    final source = sourceLabel?.trim();
    if (source != null && source.isNotEmpty) {
      return source;
    }

    return '開場草稿';
  }

  String get preview {
    final input = inputPreview?.trim();
    if (input != null && input.isNotEmpty) {
      return input;
    }

    return result.bestOpenerText ?? '已保存開場建議';
  }

  OpenerDraft copyWith({
    OpenerResult? result,
    DateTime? continuedAt,
    String? partnerId,
  }) {
    return OpenerDraft(
      id: id,
      result: result ?? this.result,
      createdAt: createdAt,
      displayName: displayName,
      sourceLabel: sourceLabel,
      inputPreview: inputPreview,
      continuedAt: continuedAt ?? this.continuedAt,
      partnerId: partnerId ?? this.partnerId,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'result': result.toJson(),
        'createdAt': createdAt.toIso8601String(),
        'displayName': displayName,
        'sourceLabel': sourceLabel,
        'inputPreview': inputPreview,
        'continuedAt': continuedAt?.toIso8601String(),
        'partnerId': partnerId,
      };

  static OpenerDraft? fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString();
    final resultJson = json['result'];
    if (id == null || id.isEmpty || resultJson is! Map) {
      return null;
    }

    DateTime parseDate(Object? raw, DateTime fallback) {
      if (raw is! String || raw.isEmpty) {
        return fallback;
      }
      return DateTime.tryParse(raw) ?? fallback;
    }

    DateTime? parseNullableDate(Object? raw) {
      if (raw is! String || raw.isEmpty) {
        return null;
      }
      return DateTime.tryParse(raw);
    }

    final normalizedResult = resultJson.map(
      (key, value) => MapEntry(key.toString(), value),
    );

    return OpenerDraft(
      id: id,
      result: OpenerResult.fromJson(normalizedResult),
      createdAt: parseDate(json['createdAt'], DateTime.now()),
      displayName: json['displayName']?.toString(),
      sourceLabel: json['sourceLabel']?.toString(),
      inputPreview: json['inputPreview']?.toString(),
      continuedAt: parseNullableDate(json['continuedAt']),
      partnerId: json['partnerId']?.toString(),
    );
  }
}

class OpenerResultCacheService {
  static const _latestResultKey = 'opener_latest_result_v1';
  static const _draftsKey = 'opener_drafts_v1';
  static const maxDrafts = 10;
  static int _draftSequence = 0;

  Future<OpenerDraft> saveDraft({
    required OpenerResult result,
    String? displayName,
    String? sourceLabel,
    String? inputPreview,
    String? partnerId,
  }) async {
    final now = DateTime.now();
    final scopedPartnerId = _blankToNull(partnerId);
    final draftSequence = (_draftSequence = (_draftSequence + 1) & 0x3fffffff);
    final draft = OpenerDraft(
      id: 'opener_${now.microsecondsSinceEpoch}_$draftSequence',
      result: result,
      createdAt: now,
      displayName: _blankToNull(displayName),
      sourceLabel: _blankToNull(sourceLabel),
      inputPreview: _blankToNull(inputPreview),
      partnerId: scopedPartnerId,
    );

    final drafts = [
      draft,
      ...loadDrafts().where((existing) => existing.id != draft.id),
    ].take(maxDrafts).toList(growable: false);

    await _saveDrafts(drafts);
    if (scopedPartnerId == null) {
      await saveLatest(result);
    }
    return draft;
  }

  List<OpenerDraft> loadDrafts() {
    final raw = StorageService.settingsBox.get(_draftsKey);
    if (raw is! String || raw.trim().isEmpty) {
      return const [];
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const [];
      }

      final drafts = decoded
          .whereType<Map>()
          .map((entry) => entry.map(
                (key, value) => MapEntry(key.toString(), value),
              ))
          .map(OpenerDraft.fromJson)
          .whereType<OpenerDraft>()
          .toList();

      drafts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return drafts.take(maxDrafts).toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  List<OpenerDraft> loadDraftsForScope({String? partnerId}) {
    final scopedPartnerId = _blankToNull(partnerId);
    return loadDrafts()
        .where((draft) => _blankToNull(draft.partnerId) == scopedPartnerId)
        .toList(growable: false);
  }

  OpenerResult? loadLatestForScope({String? partnerId}) {
    final scopedPartnerId = _blankToNull(partnerId);
    final drafts = loadDrafts();
    final scopedDrafts = drafts
        .where((draft) => _blankToNull(draft.partnerId) == scopedPartnerId)
        .toList(growable: false);
    if (scopedDrafts.isNotEmpty) {
      return scopedDrafts.first.result;
    }

    if (scopedPartnerId != null) {
      return null;
    }

    return drafts.isEmpty ? loadLatest() : null;
  }

  OpenerDraft? loadDraft(String id) {
    for (final draft in loadDrafts()) {
      if (draft.id == id) {
        return draft;
      }
    }
    return null;
  }

  /// Stamps `continuedAt` on the draft. Never rewrites the stored result —
  /// a free/downgraded caller continuing a paid-era draft must not strip the
  /// paid styles from local storage; leak protection is read-time
  /// (`visibleForAccess`), not write-time (Batch 4 #4).
  Future<void> markDraftContinued(String id) async {
    final drafts = loadDrafts();
    final updated = drafts
        .map(
          (draft) => draft.id == id
              ? draft.copyWith(continuedAt: DateTime.now())
              : draft,
        )
        .toList(growable: false);
    await _saveDrafts(updated);
  }

  Future<void> deleteDraft(String id) async {
    final updated =
        loadDrafts().where((draft) => draft.id != id).toList(growable: false);
    await _saveDrafts(updated);
  }

  /// Removes every draft scoped to [partnerId] (partner delete cascade).
  /// A blank id is a no-op — it must never match the unscoped (global-entry)
  /// drafts, which store a null partnerId.
  Future<void> deleteDraftsForPartner(String partnerId) async {
    final scopedPartnerId = _blankToNull(partnerId);
    if (scopedPartnerId == null) return;
    final updated = loadDrafts()
        .where((draft) => _blankToNull(draft.partnerId) != scopedPartnerId)
        .toList(growable: false);
    await _saveDrafts(updated);
  }

  /// Re-points every draft scoped to [fromPartnerId] onto [toPartnerId]
  /// (partner merge cascade — paid opener content survives under the merged
  /// identity). Blank ids are a no-op for the same reason as
  /// [deleteDraftsForPartner].
  Future<void> reassignDraftsPartner({
    required String fromPartnerId,
    required String toPartnerId,
  }) async {
    final from = _blankToNull(fromPartnerId);
    final to = _blankToNull(toPartnerId);
    if (from == null || to == null || from == to) return;
    final updated = loadDrafts()
        .map(
          (draft) => _blankToNull(draft.partnerId) == from
              ? draft.copyWith(partnerId: to)
              : draft,
        )
        .toList(growable: false);
    await _saveDrafts(updated);
  }

  Future<void> clearDrafts() async {
    await StorageService.settingsBox.delete(_draftsKey);
  }

  Future<void> saveLatest(OpenerResult result) async {
    await StorageService.settingsBox.put(
      _latestResultKey,
      jsonEncode(result.toJson()),
    );
  }

  OpenerResult? loadLatest() {
    final raw = StorageService.settingsBox.get(_latestResultKey);
    if (raw is! String || raw.trim().isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return OpenerResult.fromJson(decoded);
      }
      if (decoded is Map) {
        return OpenerResult.fromJson(
          decoded.map((key, value) => MapEntry(key.toString(), value)),
        );
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  Future<void> clearLatest() async {
    await StorageService.settingsBox.delete(_latestResultKey);
  }

  Future<void> _saveDrafts(List<OpenerDraft> drafts) async {
    await StorageService.settingsBox.put(
      _draftsKey,
      jsonEncode(drafts.map((draft) => draft.toJson()).toList()),
    );
  }

  String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
