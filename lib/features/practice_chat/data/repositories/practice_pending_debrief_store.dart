import 'dart:convert';

import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_hint.dart';

/// 在途 debrief requestId 的持久化快照。
///
/// 只保存 payload 的 SHA-256 digest，不保存逐字稿、memorySummary 或 Hint 內容。
/// App 在 response 遺失後被系統回收，重建時仍能沿用同一個 requestId，讓 server
/// replay 已完成的拆解卡，而不是再吃一次 debrief 次數。
class PracticePendingDebrief {
  const PracticePendingDebrief({
    required this.sessionId,
    required this.payloadDigest,
    required this.requestId,
  });

  final String sessionId;
  final String payloadDigest;
  final String requestId;

  static final RegExp _sha256Pattern = RegExp(r'^[a-f0-9]{64}$');

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'payloadDigest': payloadDigest,
        'requestId': requestId,
      };

  static PracticePendingDebrief? fromJson(Map<String, dynamic> json) {
    final sessionId = json['sessionId'];
    final payloadDigest = json['payloadDigest'];
    final requestId = json['requestId'];
    if (sessionId is! String || sessionId.isEmpty) return null;
    if (payloadDigest is! String || !_sha256Pattern.hasMatch(payloadDigest)) {
      return null;
    }
    if (requestId is! String || requestId.isEmpty) return null;
    return PracticePendingDebrief(
      sessionId: sessionId,
      payloadDigest: payloadDigest,
      requestId: requestId,
    );
  }
}

/// Pending Debrief 必須在計費請求送出前持久化。
///
/// 因此 [save] 的失敗必須向上拋出，呼叫端才能 fail-closed；[load] 與
/// [clear] 仍可容錯，因為它們不會打開「請求已送出但 requestId 遺失」窗口。
abstract class PracticePendingDebriefStore {
  /// 最近寫入的快照，保留給 migration／診斷。
  PracticePendingDebrief? load();

  PracticePendingDebrief? loadFor({
    required String sessionId,
    required String payloadDigest,
  });

  Future<void> save(PracticePendingDebrief pending);

  /// 明確全域 reset／測試用。
  Future<void> clear();

  Future<void> clearFor(PracticePendingDebrief pending);
}

class InMemoryPracticePendingDebriefStore
    implements PracticePendingDebriefStore {
  final Map<String, PracticePendingDebrief> _pendingByIntent = {};
  String? _latestIntent;

  static String _intentKey(String sessionId, String payloadDigest) =>
      '${sessionId.trim()}::$payloadDigest';

  @override
  PracticePendingDebrief? load() =>
      _latestIntent == null ? null : _pendingByIntent[_latestIntent];

  @override
  PracticePendingDebrief? loadFor({
    required String sessionId,
    required String payloadDigest,
  }) =>
      _pendingByIntent[_intentKey(sessionId, payloadDigest)];

  @override
  Future<void> save(PracticePendingDebrief pending) async {
    final intent = _intentKey(pending.sessionId, pending.payloadDigest);
    _pendingByIntent[intent] = pending;
    _latestIntent = intent;
  }

  @override
  Future<void> clear() async {
    _pendingByIntent.clear();
    _latestIntent = null;
  }

  @override
  Future<void> clearFor(PracticePendingDebrief pending) async {
    final intent = _intentKey(pending.sessionId, pending.payloadDigest);
    final current = _pendingByIntent[intent];
    if (current?.requestId != pending.requestId) return;
    _pendingByIntent.remove(intent);
    if (_latestIntent == intent) {
      _latestIntent =
          _pendingByIntent.isEmpty ? null : _pendingByIntent.keys.last;
    }
  }
}

/// JSON 存進既有 AES-256 加密 settings box；不新增 Hive adapter/migration。
class HivePracticePendingDebriefStore implements PracticePendingDebriefStore {
  HivePracticePendingDebriefStore(this._openBox);

  final Box Function() _openBox;

  static const String storageKey = 'practice_pending_debrief';

  static String storageKeyFor({
    required String sessionId,
    required String payloadDigest,
  }) {
    final encodedSession =
        base64Url.encode(utf8.encode(sessionId.trim())).replaceAll('=', '');
    return '$storageKey:v2:$encodedSession:$payloadDigest';
  }

  @override
  PracticePendingDebrief? load() {
    try {
      return _decode(_openBox().get(storageKey));
    } catch (_) {
      return null;
    }
  }

  @override
  PracticePendingDebrief? loadFor({
    required String sessionId,
    required String payloadDigest,
  }) {
    try {
      final box = _openBox();
      final current = _decode(box.get(storageKeyFor(
        sessionId: sessionId,
        payloadDigest: payloadDigest,
      )));
      if (_matches(
        current,
        sessionId: sessionId,
        payloadDigest: payloadDigest,
      )) {
        return current;
      }
      final legacy = _decode(box.get(storageKey));
      return _matches(
        legacy,
        sessionId: sessionId,
        payloadDigest: payloadDigest,
      )
          ? legacy
          : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(PracticePendingDebrief pending) async {
    final box = _openBox();
    final encoded = jsonEncode(pending.toJson());
    await box.put(
      storageKeyFor(
        sessionId: pending.sessionId,
        payloadDigest: pending.payloadDigest,
      ),
      encoded,
    );
    await box.put(storageKey, encoded);
  }

  @override
  Future<void> clear() async {
    try {
      final box = _openBox();
      final keys = box.keys
          .where((key) =>
              key is String &&
              (key == storageKey || key.startsWith('$storageKey:v2:')))
          .toList(growable: false);
      for (final key in keys) {
        await box.delete(key);
      }
    } catch (_) {
      // 殘留快照會在 payload digest 不符時自然失效。
    }
  }

  @override
  Future<void> clearFor(PracticePendingDebrief pending) async {
    try {
      final box = _openBox();
      final scopedKey = storageKeyFor(
        sessionId: pending.sessionId,
        payloadDigest: pending.payloadDigest,
      );
      final scoped = _decode(box.get(scopedKey));
      if (_sameIdentity(scoped, pending)) {
        await box.delete(scopedKey);
      }
      final latest = _decode(box.get(storageKey));
      if (_sameIdentity(latest, pending)) {
        await box.delete(storageKey);
      }
    } catch (_) {
      // Identity-scoped cleanup is best-effort; stale rows are replay-safe.
    }
  }

  static PracticePendingDebrief? _decode(dynamic raw) {
    if (raw is! String) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return PracticePendingDebrief.fromJson(
        Map<String, dynamic>.from(decoded),
      );
    } catch (_) {
      return null;
    }
  }

  static bool _matches(
    PracticePendingDebrief? pending, {
    required String sessionId,
    required String payloadDigest,
  }) =>
      pending?.sessionId == sessionId.trim() &&
      pending?.payloadDigest == payloadDigest;

  static bool _sameIdentity(
    PracticePendingDebrief? current,
    PracticePendingDebrief expected,
  ) =>
      current?.sessionId == expected.sessionId &&
      current?.payloadDigest == expected.payloadDigest &&
      current?.requestId == expected.requestId;
}

/// Applied-Hint accountability context for the current open practice session.
///
/// This intentionally uses JSON in the already encrypted settings box instead
/// of adding another Hive type-adapter field. It therefore survives provider /
/// app rebuilds without a binary schema migration. DTO validation stays in the
/// API layer; this store only preserves the allowlisted JSON maps.
class PracticeSuccessfulHintSnapshot {
  const PracticeSuccessfulHintSnapshot({
    required this.aiCount,
    required this.result,
    required this.qualitySchemaVersion,
    this.requestId,
  }) : assert(qualitySchemaVersion == kPracticeHintQualitySchemaVersion);

  const PracticeSuccessfulHintSnapshot._decoded({
    required this.aiCount,
    required this.result,
    required this.qualitySchemaVersion,
    this.requestId,
  });

  final int aiCount;
  final PracticeHintResult result;
  final String? qualitySchemaVersion;
  final String? requestId;

  /// Old snapshots are still decoded so their request id can replay the same
  /// server ledger row, but their visible content must never be restored.
  bool get isRestorable =>
      qualitySchemaVersion == kPracticeHintQualitySchemaVersion &&
      result.hasCurrentQualitySchema;

  Map<String, dynamic> toJson() => {
        'aiCount': aiCount,
        'result': result.toJson(),
        if (qualitySchemaVersion != null)
          'qualitySchemaVersion': qualitySchemaVersion,
        if (requestId != null && requestId!.trim().isNotEmpty)
          'requestId': requestId!.trim(),
      };

  static PracticeSuccessfulHintSnapshot? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final aiCount = raw['aiCount'];
    final result = PracticeHintResult.fromJson(raw['result']);
    if (aiCount is! int || aiCount < 0 || result == null) return null;
    final rawQualitySchemaVersion = raw['qualitySchemaVersion'];
    final qualitySchemaVersion = rawQualitySchemaVersion is String &&
            rawQualitySchemaVersion.trim().isNotEmpty
        ? rawQualitySchemaVersion.trim()
        : null;
    final rawRequestId = raw['requestId'];
    final requestId = rawRequestId is String && rawRequestId.trim().isNotEmpty
        ? rawRequestId.trim()
        : null;
    return PracticeSuccessfulHintSnapshot._decoded(
      aiCount: aiCount,
      result: result,
      qualitySchemaVersion: qualitySchemaVersion,
      requestId: requestId,
    );
  }
}

class PracticeAppliedHintContext {
  const PracticeAppliedHintContext({
    required this.sessionId,
    required this.turns,
    this.latestHint,
    this.revision = 0,
    this.writerId,
  });

  final String sessionId;
  final List<Map<String, dynamic>> turns;
  final PracticeSuccessfulHintSnapshot? latestHint;

  /// 同 session 的單調遞增寫入版本。store 的 save 拒絕不比現存新的 revision，
  /// 讓失去所有權的舊 controller 晚到的寫入不可能蓋掉較新 context。
  /// 舊格式沒有此欄位 → 0。
  final int revision;

  /// 寫入者身分（controller instance 隨機 id）。「save 落值後才拋錯」的
  /// 復原判斷需要它：內容全等不足以證明是自己寫的——另一個 controller
  /// 寫入完全相同內容時不得被誤認成自己成功（會繞過 fencing）。
  final String? writerId;

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'turns': turns,
        if (latestHint != null) 'latestHint': latestHint!.toJson(),
        'revision': revision,
        if (writerId != null) 'writerId': writerId,
      };

  static PracticeAppliedHintContext? fromJson(Map<String, dynamic> json) {
    final sessionId = json['sessionId'];
    final rawTurns = json['turns'];
    if (sessionId is! String || sessionId.trim().isEmpty || rawTurns is! List) {
      return null;
    }
    final turns = rawTurns
        .whereType<Map>()
        .map((turn) => Map<String, dynamic>.from(turn))
        .take(5)
        .toList(growable: false);
    final rawRevision = json['revision'];
    final rawWriterId = json['writerId'];
    return PracticeAppliedHintContext(
      sessionId: sessionId.trim(),
      turns: turns,
      latestHint: PracticeSuccessfulHintSnapshot.fromJson(json['latestHint']),
      revision: rawRevision is int && rawRevision > 0 ? rawRevision : 0,
      writerId: rawWriterId is String && rawWriterId.trim().isNotEmpty
          ? rawWriterId.trim()
          : null,
    );
  }
}

abstract class PracticeAppliedHintStore {
  PracticeAppliedHintContext? load(String sessionId);

  /// Save errors are observable so the controller can retain the exact
  /// pending Hint request id until the successful envelope is truly durable.
  /// Rejects（throw）revision 不比現存新的寫入：staging await 期間失去所有權的
  /// 舊 controller，其晚到的 save 不得蓋掉同 session 較新的 context。
  Future<void> save(PracticeAppliedHintContext context);

  /// Clears only when [sessionId] still owns the stored context. This prevents
  /// a late old-controller cleanup from deleting a newer session's metadata.
  /// 帶 [ifRevisionAtMost] 時，現存 revision 比它新就不清（失去所有權後的
  /// 還原清除專用；無條件清除留給場次收尾）。
  ///
  /// 清除不物理刪除，而是寫入「空 tombstone」（turns 空、latestHint null、
  /// revision +1）保留世代——物理刪除會讓 revision 歸零，清除後失去所有權的
  /// 舊寫入就能以較大 revision 復活已清掉的血統。load 會回傳這個空 context，
  /// 消費端把「turns 空且無 latestHint」視同已清除。
  ///
  /// Tombstone 每個 session 至多一筆小紀錄、與場次紀錄同量級（有界）；
  /// 若未來場次量大到需要回收，再做批次清理。
  ///
  /// [writerId]（清除者身分）會記在 tombstone 上：controller 中途只准
  /// 重新採納「自己清出來的」tombstone 世代——不比身分的話，舊 controller
  /// 可以搭別人的 tombstone 重新取得寫入世代、繞過 fencing。
  Future<void> clearForSession(
    String sessionId, {
    int? ifRevisionAtMost,
    String? writerId,
  });
}

class InMemoryPracticeAppliedHintStore implements PracticeAppliedHintStore {
  final Map<String, PracticeAppliedHintContext> _contexts = {};

  @override
  PracticeAppliedHintContext? load(String sessionId) =>
      _contexts[sessionId.trim()];

  @override
  Future<void> save(PracticeAppliedHintContext context) async {
    final key = context.sessionId.trim();
    final existing = _contexts[key];
    if (existing != null && context.revision <= existing.revision) {
      throw StateError('practice_applied_hint_stale_write');
    }
    // 存正規化過 sessionId 的副本：load 用 trimmed key 找得到之後，
    // 回傳的 identity 也要對得上（controller restore 比對 sessionId）。
    _contexts[key] = context.sessionId == key
        ? context
        : PracticeAppliedHintContext(
            sessionId: key,
            turns: context.turns,
            latestHint: context.latestHint,
            revision: context.revision,
            writerId: context.writerId,
          );
  }

  @override
  Future<void> clearForSession(
    String sessionId, {
    int? ifRevisionAtMost,
    String? writerId,
  }) async {
    final key = sessionId.trim();
    if (key.isEmpty) return; // 與 Hive 對齊：空 sessionId 一律 no-op
    final existing = _contexts[key];
    if (existing == null) {
      // 空 store 也要留 tombstone（世代 1），否則失去所有權的舊 controller
      // 事後仍能以 revision 1 寫進第一代血統。守衛清除（stale 路徑）除外——
      // stale caller 不得產生任何寫入。
      if (ifRevisionAtMost == null) {
        _contexts[key] = PracticeAppliedHintContext(
          sessionId: key,
          turns: const [],
          revision: 1,
          writerId: writerId,
        );
      }
      return;
    }
    if (ifRevisionAtMost != null && existing.revision > ifRevisionAtMost) {
      return;
    }
    if (existing.turns.isEmpty && existing.latestHint == null) return; // 已清
    _contexts[key] = PracticeAppliedHintContext(
      sessionId: key,
      turns: const [],
      revision: existing.revision + 1,
      writerId: writerId,
    );
  }
}

class HivePracticeAppliedHintStore implements PracticeAppliedHintStore {
  HivePracticeAppliedHintStore(this._openBox);

  final Box Function() _openBox;

  /// Legacy single-slot key retained for backward-compatible reads only.
  static const String storageKey = 'practice_applied_hint_context';

  static String storageKeyForSession(String sessionId) {
    final encoded =
        base64Url.encode(utf8.encode(sessionId.trim())).replaceAll('=', '');
    return '$storageKey:$encoded';
  }

  @override
  PracticeAppliedHintContext? load(String sessionId) {
    try {
      return _loadStrict(sessionId);
    } catch (_) {
      return null;
    }
  }

  /// 守衛判斷（save 的 CAS、clear 的 revision guard）專用讀取：讀取失敗
  /// **必須拋出**。若沿用吞錯的 [load]，暫時性讀取錯誤會被當成「不存在」，
  /// stale 寫入與守衛清除就 fail open。
  ///
  /// 「槽位有值但解不開」同樣拋出——損壞資料的世代未知，把它當成不存在
  /// 就等於允許任意 revision 覆寫未知世代。代價是該 session 的血統寫入
  /// 會持續失敗（不套提示的一般送出不受影響）；新場次用新 sessionId 不受牽連。
  /// legacy 單槽的不可解資料無法歸屬 session，不擋（save 不覆寫 legacy 槽）。
  PracticeAppliedHintContext? _loadStrict(String sessionId) {
    final normalizedSessionId = sessionId.trim();
    if (normalizedSessionId.isEmpty) return null;
    final box = _openBox();
    final rawCurrent = box.get(storageKeyForSession(normalizedSessionId));
    if (rawCurrent != null) {
      final current = _decodeContext(rawCurrent);
      if (current == null || current.sessionId != normalizedSessionId) {
        throw StateError('practice_applied_hint_unreadable_slot');
      }
      return current;
    }

    // Old builds wrote one global slot. Read it only when its identity
    // matches; the next successful save migrates it to the per-session key.
    final legacy = _decodeContext(box.get(storageKey));
    return legacy?.sessionId == normalizedSessionId ? legacy : null;
  }

  @override
  Future<void> save(PracticeAppliedHintContext context) async {
    // _loadStrict 是同步、box.put 同步更新快取：check 與 put 之間沒有 await，
    // 同 isolate 內不會被別的寫入插隊；讀取失敗直接拋出（fail closed）。
    final existing = _loadStrict(context.sessionId);
    if (existing != null && context.revision <= existing.revision) {
      throw StateError('practice_applied_hint_stale_write');
    }
    final box = _openBox();
    await box.put(
      storageKeyForSession(context.sessionId),
      jsonEncode(context.toJson()),
    );
    final legacy = _decodeContext(box.get(storageKey));
    if (legacy?.sessionId == context.sessionId) {
      await box.delete(storageKey);
    }
  }

  @override
  Future<void> clearForSession(
    String sessionId, {
    int? ifRevisionAtMost,
    String? writerId,
  }) async {
    final normalizedSessionId = sessionId.trim();
    if (normalizedSessionId.isEmpty) return;
    // 讀取失敗直接拋出（fail closed）：吞錯會讓守衛清除誤刪較新 context。
    final existing = _loadStrict(normalizedSessionId);
    final box = _openBox();
    if (existing == null) {
      // 空 store：無條件清除也要留世代 1 的 tombstone（防止舊 controller
      // 事後以 revision 1 寫進第一代血統）；守衛清除（stale 路徑）不得寫入。
      if (ifRevisionAtMost == null) {
        await box.put(
          storageKeyForSession(normalizedSessionId),
          jsonEncode(PracticeAppliedHintContext(
            sessionId: normalizedSessionId,
            turns: const [],
            revision: 1,
            writerId: writerId,
          ).toJson()),
        );
      }
      return;
    }
    if (ifRevisionAtMost != null && existing.revision > ifRevisionAtMost) return;
    if (existing.turns.isNotEmpty || existing.latestHint != null) {
      await box.put(
        storageKeyForSession(normalizedSessionId),
        jsonEncode(PracticeAppliedHintContext(
          sessionId: normalizedSessionId,
          turns: const [],
          revision: existing.revision + 1,
          writerId: writerId,
        ).toJson()),
      );
    }
    final legacy = _decodeContext(box.get(storageKey));
    if (legacy?.sessionId == normalizedSessionId) {
      await box.delete(storageKey);
    }
  }

  static PracticeAppliedHintContext? _decodeContext(dynamic raw) {
    if (raw is! String) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return PracticeAppliedHintContext.fromJson(
        Map<String, dynamic>.from(decoded),
      );
    } catch (_) {
      return null;
    }
  }
}
