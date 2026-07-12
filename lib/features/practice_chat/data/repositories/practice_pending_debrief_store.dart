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
  });

  final String sessionId;
  final List<Map<String, dynamic>> turns;
  final PracticeSuccessfulHintSnapshot? latestHint;

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'turns': turns,
        if (latestHint != null) 'latestHint': latestHint!.toJson(),
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
    return PracticeAppliedHintContext(
      sessionId: sessionId.trim(),
      turns: turns,
      latestHint: PracticeSuccessfulHintSnapshot.fromJson(json['latestHint']),
    );
  }
}

abstract class PracticeAppliedHintStore {
  PracticeAppliedHintContext? load(String sessionId);

  /// Save errors are observable so the controller can retain the exact
  /// pending Hint request id until the successful envelope is truly durable.
  Future<void> save(PracticeAppliedHintContext context);

  /// Clears only when [sessionId] still owns the stored context. This prevents
  /// a late old-controller cleanup from deleting a newer session's metadata.
  Future<void> clearForSession(String sessionId);
}

class InMemoryPracticeAppliedHintStore implements PracticeAppliedHintStore {
  final Map<String, PracticeAppliedHintContext> _contexts = {};

  @override
  PracticeAppliedHintContext? load(String sessionId) =>
      _contexts[sessionId.trim()];

  @override
  Future<void> save(PracticeAppliedHintContext context) async {
    _contexts[context.sessionId] = context;
  }

  @override
  Future<void> clearForSession(String sessionId) async {
    _contexts.remove(sessionId.trim());
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
      final normalizedSessionId = sessionId.trim();
      if (normalizedSessionId.isEmpty) return null;
      final box = _openBox();
      final current = _decodeContext(
        box.get(storageKeyForSession(normalizedSessionId)),
      );
      if (current?.sessionId == normalizedSessionId) return current;

      // Old builds wrote one global slot. Read it only when its identity
      // matches; the next successful save migrates it to the per-session key.
      final legacy = _decodeContext(box.get(storageKey));
      return legacy?.sessionId == normalizedSessionId ? legacy : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(PracticeAppliedHintContext context) async {
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
  Future<void> clearForSession(String sessionId) async {
    final normalizedSessionId = sessionId.trim();
    if (normalizedSessionId.isEmpty) return;
    final box = _openBox();
    await box.delete(storageKeyForSession(normalizedSessionId));
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
