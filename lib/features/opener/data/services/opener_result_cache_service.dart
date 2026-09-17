import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../../../core/services/storage_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../../domain/opener_flow_models.dart';
import 'opener_service.dart';

/// 兩段式流程的階段（R2a：未完成操作也要落地，不只成功結果）。
enum OpenerDraftFlowStage {
  /// 分析完成、尚未生成（看分析、填回答中）。
  analyzed,

  /// 生成請求已送出、尚未收到可用結果（伺服器可能已結算）。
  generating,

  /// 已取得一組可交付結果。
  result,
}

/// 生成操作的送出快照（R2a）：retry 沿用它，不是目前被改過的 draft。
class OpenerPendingGeneration {
  const OpenerPendingGeneration({
    required this.generationId,
    required this.contribution,
  });

  final String generationId;
  final OpenerContribution contribution;

  Map<String, dynamic> toJson() => {
        'generationId': generationId,
        'contribution': contribution.toJson(),
      };

  static OpenerPendingGeneration? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final id = raw['generationId'];
    final contribution = OpenerContribution.tryParse(raw['contribution']);
    if (id is! String || id.isEmpty || contribution == null) return null;
    return OpenerPendingGeneration(generationId: id, contribution: contribution);
  }
}

/// 兩段式草稿的延伸資料（附件 §9.5、R2a）：分析與題目版本、本次回答草稿、
/// analysisRequestId／輸入指紋、送出中的 generationId＋回答快照、成功結果、
/// 到期時間與剩餘次數。舊草稿沒有這一段，照舊讀取。
class OpenerDraftFlow {
  const OpenerDraftFlow({
    required this.stage,
    required this.analysis,
    required this.contributionDraft,
    this.analysisRequestId,
    this.inputFingerprint,
    this.pendingGeneration,
    this.generation,
  });

  final OpenerDraftFlowStage stage;
  final OpenerAnalysis analysis;
  final OpenerContributionDraft contributionDraft;
  final String? analysisRequestId;
  final String? inputFingerprint;

  /// stage=generating 時的送出快照；伺服器已結算但回應遺失時靠它取回同組結果。
  final OpenerPendingGeneration? pendingGeneration;
  final OpenerGeneration? generation;

  int get generationsRemaining =>
      generation?.usage.generationsRemaining ?? analysis.generationsRemaining;

  /// 這份草稿是否還能繼續生成（未到期且本局還有次數）。
  bool canContinueAt(DateTime now) =>
      !analysis.isExpiredAt(now) && generationsRemaining > 0;

  OpenerDraftFlow copyWith({
    OpenerDraftFlowStage? stage,
    OpenerAnalysis? analysis,
    OpenerContributionDraft? contributionDraft,
    OpenerPendingGeneration? pendingGeneration,
    bool clearPendingGeneration = false,
    OpenerGeneration? generation,
  }) {
    return OpenerDraftFlow(
      stage: stage ?? this.stage,
      analysis: analysis ?? this.analysis,
      contributionDraft: contributionDraft ?? this.contributionDraft,
      analysisRequestId: analysisRequestId,
      inputFingerprint: inputFingerprint,
      pendingGeneration:
          clearPendingGeneration ? null : (pendingGeneration ?? this.pendingGeneration),
      generation: generation ?? this.generation,
    );
  }

  Map<String, dynamic> toJson() => {
        'stage': stage.name,
        'analysis': analysis.toJson(),
        'contributionDraft': contributionDraft.toJson(),
        if (analysisRequestId != null) 'analysisRequestId': analysisRequestId,
        if (inputFingerprint != null) 'inputFingerprint': inputFingerprint,
        if (pendingGeneration != null) 'pendingGeneration': pendingGeneration!.toJson(),
        if (generation != null) 'generation': generation!.toJson(),
      };

  static OpenerDraftFlow? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final analysis = OpenerAnalysis.tryParse(raw['analysis']);
    if (analysis == null) return null;
    final generation = OpenerGeneration.tryParse(raw['generation']);
    final pending = OpenerPendingGeneration.tryParse(raw['pendingGeneration']);
    final stage = switch (raw['stage']) {
      'analyzed' => OpenerDraftFlowStage.analyzed,
      'generating' => OpenerDraftFlowStage.generating,
      'result' => OpenerDraftFlowStage.result,
      // 舊版 flow（只有成功結果）沒有 stage 欄位。
      _ => generation != null ? OpenerDraftFlowStage.result : OpenerDraftFlowStage.analyzed,
    };
    if (stage == OpenerDraftFlowStage.result && generation == null) return null;
    return OpenerDraftFlow(
      stage: stage,
      analysis: analysis,
      contributionDraft: OpenerContributionDraft.fromJson(raw['contributionDraft']),
      analysisRequestId: raw['analysisRequestId'] is String ? raw['analysisRequestId'] as String : null,
      inputFingerprint: raw['inputFingerprint'] is String ? raw['inputFingerprint'] as String : null,
      pendingGeneration: pending,
      generation: generation,
    );
  }
}

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
    this.flow,
  });

  final String id;

  /// 可交付結果；兩段式未完成階段（分析完、生成中）為 null。
  final OpenerResult? result;
  final DateTime createdAt;
  final String? displayName;
  final String? sourceLabel;
  final String? inputPreview;
  final DateTime? continuedAt;
  final String? partnerId;

  /// 兩段式延伸；舊單段草稿為 null。
  final OpenerDraftFlow? flow;

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

  /// Access-aware preview for the recent-drafts list. The opener-text
  /// fallback must respect the caller's tier — the stored result keeps the
  /// paid styles verbatim, so a raw `bestOpenerText` here would leak the
  /// locked pick to free users (Codex P2 on Batch 4 #4).
  String previewForAccess({required bool isFreeUser}) {
    final input = inputPreview?.trim();
    if (input != null && input.isNotEmpty) {
      return input;
    }
    final stored = result;
    if (stored == null) {
      return flow?.stage == OpenerDraftFlowStage.generating ? '生成中，尚未取得結果' : '分析完成，尚未生成';
    }
    return stored.bestOpenerTextForAccess(isFreeUser: isFreeUser) ??
        '已保存開場建議';
  }

  OpenerDraft copyWith({
    OpenerResult? result,
    DateTime? continuedAt,
    String? partnerId,
    OpenerDraftFlow? flow,
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
      flow: flow ?? this.flow,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        if (result != null) 'result': result!.toJson(),
        'createdAt': createdAt.toIso8601String(),
        'displayName': displayName,
        'sourceLabel': sourceLabel,
        'inputPreview': inputPreview,
        'continuedAt': continuedAt?.toIso8601String(),
        'partnerId': partnerId,
        if (flow != null) 'flow': flow!.toJson(),
      };

  static OpenerDraft? fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString();
    final resultJson = json['result'];
    final flow = OpenerDraftFlow.tryParse(json['flow']);
    // 舊草稿必有 result；兩段式未完成階段允許沒有 result 但要有 flow。
    if (id == null || id.isEmpty || (resultJson is! Map && flow == null)) {
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

    final result = resultJson is Map
        ? OpenerResult.fromJson(
            resultJson.map((key, value) => MapEntry(key.toString(), value)),
          )
        : null;

    return OpenerDraft(
      id: id,
      result: result,
      createdAt: parseDate(json['createdAt'], DateTime.now()),
      displayName: json['displayName']?.toString(),
      sourceLabel: json['sourceLabel']?.toString(),
      inputPreview: json['inputPreview']?.toString(),
      continuedAt: parseNullableDate(json['continuedAt']),
      partnerId: json['partnerId']?.toString(),
      flow: flow,
    );
  }
}

class OpenerResultCacheService {
  /// Key 綁 account id（`<prefix>:<ownerUserId>`，同 chat_quiz/ebook 制度）：
  /// 草稿含付費開場內容，未綁 key 會讓同機下一個帳號直接看到上一個帳號的
  /// 草稿。沒有帳號時 fail closed——不讀不寫，不建立共用草稿。
  OpenerResultCacheService({String? Function()? ownerIdResolver})
      : _ownerIdResolver = ownerIdResolver ?? _defaultOwnerId;

  /// 測試用：widget 測試無法初始化 Supabase，又碰不到 screen/repo 內部
  /// 建構的實例，只能從這裡覆蓋預設 owner。
  @visibleForTesting
  static String? Function()? debugDefaultOwnerIdOverride;

  static String? _defaultOwnerId() =>
      debugDefaultOwnerIdOverride != null
          ? debugDefaultOwnerIdOverride!()
          : SupabaseService.currentUser?.id;

  static const _latestResultKeyPrefix = 'opener_latest_result_v1';
  static const _draftsKeyPrefix = 'opener_drafts_v1';
  static const maxDrafts = 10;
  static int _draftSequence = 0;

  final String? Function() _ownerIdResolver;

  String? get _owner {
    final owner = _ownerIdResolver()?.trim();
    return (owner == null || owner.isEmpty) ? null : owner;
  }

  String? get _draftsKey => _draftsKeyFor(_owner);

  String? get _latestResultKey => _latestKeyFor(_owner);

  // R2b：每個會跨 await 的寫入路徑都以「操作起點」解析一次 owner，之後一路
  // 帶著同一個 owner 走 drafts／latest 的所有寫入與讀回；不得在 await 後重讀
  // 目前帳號（切帳中會把 A 的結果寫進 B 的 key）。
  static String? _draftsKeyFor(String? owner) =>
      owner == null ? null : '$_draftsKeyPrefix:$owner';

  static String? _latestKeyFor(String? owner) =>
      owner == null ? null : '$_latestResultKeyPrefix:$owner';

  /// 未綁帳號的舊 key 一次性搬到目前帳號名下後刪除。單帳號裝置（絕大多數）
  /// 升級不掉草稿；多帳號裝置最壞情況＝舊資料歸給升級後第一個開 opener 的
  /// 帳號——跟修復前「永久共用」相比只窄不寬。
  String? _readScopedWithLegacyMigration(String scopedKey, String legacyKey) {
    final box = StorageService.settingsBox;
    final scoped = box.get(scopedKey);
    if (scoped is String && scoped.trim().isNotEmpty) {
      return scoped;
    }
    final legacy = box.get(legacyKey);
    if (legacy is! String || legacy.trim().isEmpty) {
      return null;
    }
    unawaited(box.put(scopedKey, legacy));
    unawaited(box.delete(legacyKey));
    return legacy;
  }

  Future<OpenerDraft> saveDraft({
    OpenerResult? result,
    String? displayName,
    String? sourceLabel,
    String? inputPreview,
    String? partnerId,
    OpenerDraftFlow? flow,
  }) async {
    assert(result != null || flow != null, '草稿至少要有結果或兩段式流程資料');
    final owner = _owner; // 操作起點解析一次，全程沿用（R2b）。
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
      flow: flow,
    );

    final drafts = [
      draft,
      ..._loadDraftsFor(owner).where((existing) => existing.id != draft.id),
    ].take(maxDrafts).toList(growable: false);

    await _saveDraftsFor(owner, drafts);
    if (scopedPartnerId == null && result != null) {
      await _saveLatestFor(owner, result);
    }
    return draft;
  }

  /// 更新既有草稿（R2a：同一份紀錄隨流程階段更新，不另建歷史）。找不到就回 null。
  Future<OpenerDraft?> updateDraft(
    String id, {
    OpenerResult? result,
    OpenerDraftFlow? flow,
  }) async {
    final owner = _owner;
    final drafts = _loadDraftsFor(owner);
    OpenerDraft? updated;
    final next = drafts.map((draft) {
      if (draft.id != id) return draft;
      updated = draft.copyWith(result: result, flow: flow);
      return updated!;
    }).toList(growable: false);
    if (updated == null) return null;
    await _saveDraftsFor(owner, next);
    if (_blankToNull(updated!.partnerId) == null && result != null) {
      await _saveLatestFor(owner, result);
    }
    return updated;
  }

  List<OpenerDraft> loadDrafts() => _loadDraftsFor(_owner);

  List<OpenerDraft> _loadDraftsFor(String? owner) {
    final key = _draftsKeyFor(owner);
    if (key == null) {
      return const [];
    }
    final raw = _readScopedWithLegacyMigration(key, _draftsKeyPrefix);
    if (raw == null || raw.trim().isEmpty) {
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
    final firstWithResult =
        scopedDrafts.where((draft) => draft.result != null).firstOrNull;
    if (scopedDrafts.isNotEmpty) {
      return firstWithResult?.result;
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
    final owner = _owner;
    final updated = _loadDraftsFor(owner)
        .map(
          (draft) => draft.id == id
              ? draft.copyWith(continuedAt: DateTime.now())
              : draft,
        )
        .toList(growable: false);
    await _saveDraftsFor(owner, updated);
  }

  Future<void> deleteDraft(String id) async {
    final owner = _owner;
    final updated = _loadDraftsFor(owner)
        .where((draft) => draft.id != id)
        .toList(growable: false);
    await _saveDraftsFor(owner, updated);
  }

  /// Removes every draft scoped to [partnerId] (partner delete cascade).
  /// A blank id is a no-op — it must never match the unscoped (global-entry)
  /// drafts, which store a null partnerId.
  Future<void> deleteDraftsForPartner(String partnerId) async {
    final scopedPartnerId = _blankToNull(partnerId);
    if (scopedPartnerId == null) return;
    final owner = _owner;
    final updated = _loadDraftsFor(owner)
        .where((draft) => _blankToNull(draft.partnerId) != scopedPartnerId)
        .toList(growable: false);
    await _saveDraftsFor(owner, updated);
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
    final owner = _owner;
    final updated = _loadDraftsFor(owner)
        .map(
          (draft) => _blankToNull(draft.partnerId) == from
              ? draft.copyWith(partnerId: to)
              : draft,
        )
        .toList(growable: false);
    await _saveDraftsFor(owner, updated);
  }

  Future<void> clearDrafts() async {
    // 舊未綁 key 一併清：清理語意是「這台裝置的草稿清單歸零」。
    await StorageService.settingsBox.delete(_draftsKeyPrefix);
    final key = _draftsKey;
    if (key == null) return;
    await StorageService.settingsBox.delete(key);
  }

  Future<void> saveLatest(OpenerResult result) => _saveLatestFor(_owner, result);

  Future<void> _saveLatestFor(String? owner, OpenerResult result) async {
    final key = _latestKeyFor(owner);
    if (key == null) return;
    await StorageService.settingsBox.put(
      key,
      jsonEncode(result.toJson()),
    );
  }

  OpenerResult? loadLatest() {
    final key = _latestResultKey;
    if (key == null) {
      return null;
    }
    final raw = _readScopedWithLegacyMigration(key, _latestResultKeyPrefix);
    if (raw == null || raw.trim().isEmpty) {
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
    await StorageService.settingsBox.delete(_latestResultKeyPrefix);
    final key = _latestResultKey;
    if (key == null) return;
    await StorageService.settingsBox.delete(key);
  }

  Future<void> _saveDraftsFor(String? owner, List<OpenerDraft> drafts) async {
    final key = _draftsKeyFor(owner);
    if (key == null) return;
    await StorageService.settingsBox.put(
      key,
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
