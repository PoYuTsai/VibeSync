import 'dart:convert';

import 'package:hive_ce/hive_ce.dart';

/// 在途 hint 扣費 requestId 的持久化快照。
///
/// controller 是 autoDispose：離開練習室／app 回收後記憶體的
/// `_pendingHintRequestId` 就消失。若 server 已入帳但 client 沒收到回應，
/// 重建後再按 hint 必須沿用同一個 requestId，server 才能 replay 上次結果
/// 而不是重新生成再扣一次。指紋＝sessionId＋aiCount（當下 AI 回覆數）：
/// 任一不吻合＝針對別的 turn，一律作廢鑄新 id。
class PracticePendingHint {
  const PracticePendingHint({
    required this.sessionId,
    required this.aiCount,
    required this.requestId,
  });

  final String sessionId;
  final int aiCount;
  final String requestId;

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'aiCount': aiCount,
        'requestId': requestId,
      };

  /// 欄位缺漏／型別不對回 null（當不存在），絕不丟例外。
  static PracticePendingHint? fromJson(Map<String, dynamic> json) {
    final sessionId = json['sessionId'];
    final aiCount = json['aiCount'];
    final requestId = json['requestId'];
    if (sessionId is! String || sessionId.isEmpty) return null;
    if (aiCount is! int) return null;
    if (requestId is! String || requestId.isEmpty) return null;
    return PracticePendingHint(
      sessionId: sessionId,
      aiCount: aiCount,
      requestId: requestId,
    );
  }
}

/// 在途 hint requestId 的本地存取。損毀資料讀取時當不存在；正式送出
/// billable Hint 前，寫入失敗必須可被 controller 觀察並中止 dispatch，
/// 否則 process kill 後無法用同一 id replay，可能重複扣費。
abstract class PracticePendingHintStore {
  /// 取回最近寫入的快照。保留給 migration／診斷；正式 replay 應使用
  /// [loadFor]，避免另一場的寫入覆蓋目前 session 的 requestId。
  PracticePendingHint? load();

  /// 按 session＋AI turn 指紋取回在途快照；無資料或損毀回 null。
  PracticePendingHint? loadFor({
    required String sessionId,
    required int aiCount,
  });

  Future<void> save(PracticePendingHint pending);

  /// 清除所有 pending。只供明確全域 reset／測試使用。
  Future<void> clear();

  /// 只清指定 session＋turn，並以 [requestId] 防止晚到舊回應誤刪新 id。
  Future<void> clearFor({
    required String sessionId,
    required int aiCount,
    required String requestId,
  });
}

/// 測試／無持久化情境用的記憶體版本。
class InMemoryPracticePendingHintStore implements PracticePendingHintStore {
  final Map<String, PracticePendingHint> _pendingByFingerprint = {};
  String? _latestFingerprint;

  static String _fingerprint(String sessionId, int aiCount) =>
      '${sessionId.trim()}::$aiCount';

  @override
  PracticePendingHint? load() => _latestFingerprint == null
      ? null
      : _pendingByFingerprint[_latestFingerprint];

  @override
  PracticePendingHint? loadFor({
    required String sessionId,
    required int aiCount,
  }) =>
      _pendingByFingerprint[_fingerprint(sessionId, aiCount)];

  @override
  Future<void> save(PracticePendingHint pending) async {
    final fingerprint = _fingerprint(pending.sessionId, pending.aiCount);
    _pendingByFingerprint[fingerprint] = pending;
    _latestFingerprint = fingerprint;
  }

  @override
  Future<void> clear() async {
    _pendingByFingerprint.clear();
    _latestFingerprint = null;
  }

  @override
  Future<void> clearFor({
    required String sessionId,
    required int aiCount,
    required String requestId,
  }) async {
    final fingerprint = _fingerprint(sessionId, aiCount);
    final current = _pendingByFingerprint[fingerprint];
    if (current?.requestId != requestId) return;
    _pendingByFingerprint.remove(fingerprint);
    if (_latestFingerprint == fingerprint) {
      _latestFingerprint = _pendingByFingerprint.isEmpty
          ? null
          : _pendingByFingerprint.keys.last;
    }
  }
}

/// 正式版本：JSON 存進既有的加密 settings box。比照
/// HivePracticeDrawDraftStore 刻意不新增 Hive typeId／adapter／migration——
/// 這是少量、短命的 per-session 狀態，JSON 足矣。
///
/// 收 box **getter** 而非 box 本身：延遲到每次讀寫才取 box，且全程包在
/// try-catch 裡——box 沒開（headless／widget 測試環境）只是退化成
/// 「不持久化」，絕不在 provider 建構期丟例外。
class HivePracticePendingHintStore implements PracticePendingHintStore {
  HivePracticePendingHintStore(this._openBox);

  final Box Function() _openBox;

  static const String storageKey = 'practice_pending_hint';

  static String storageKeyFor({
    required String sessionId,
    required int aiCount,
  }) {
    final encodedSession =
        base64Url.encode(utf8.encode(sessionId.trim())).replaceAll('=', '');
    return '$storageKey:v2:$encodedSession:$aiCount';
  }

  @override
  PracticePendingHint? load() {
    try {
      return _decode(_openBox().get(storageKey));
    } catch (_) {
      // 損毀／舊格式：當作沒有在途 hint，退回鑄新 id。
      return null;
    }
  }

  @override
  PracticePendingHint? loadFor({
    required String sessionId,
    required int aiCount,
  }) {
    try {
      final box = _openBox();
      final current = _decode(box.get(storageKeyFor(
        sessionId: sessionId,
        aiCount: aiCount,
      )));
      if (_matches(current, sessionId: sessionId, aiCount: aiCount)) {
        return current;
      }

      // 舊版只存一個全域 slot。指紋吻合時仍可 replay；下一次 save 會
      // 自動寫入 v2 per-session key。
      final legacy = _decode(box.get(storageKey));
      return _matches(legacy, sessionId: sessionId, aiCount: aiCount)
          ? legacy
          : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(PracticePendingHint pending) async {
    final box = _openBox();
    final encoded = jsonEncode(pending.toJson());
    await box.put(
      storageKeyFor(
        sessionId: pending.sessionId,
        aiCount: pending.aiCount,
      ),
      encoded,
    );
    // 維持舊版／診斷 load() 的「最近一筆」語意。正式讀取不依賴此 slot。
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
      // 清失敗留下的殘骸靠指紋不吻合自然作廢。
    }
  }

  @override
  Future<void> clearFor({
    required String sessionId,
    required int aiCount,
    required String requestId,
  }) async {
    try {
      final box = _openBox();
      final scopedKey = storageKeyFor(
        sessionId: sessionId,
        aiCount: aiCount,
      );
      final scoped = _decode(box.get(scopedKey));
      if (_matches(scoped, sessionId: sessionId, aiCount: aiCount) &&
          scoped!.requestId == requestId) {
        await box.delete(scopedKey);
      }
      final latest = _decode(box.get(storageKey));
      if (_matches(latest, sessionId: sessionId, aiCount: aiCount) &&
          latest!.requestId == requestId) {
        await box.delete(storageKey);
      }
    } catch (_) {
      // Identity mismatch or cleanup failure leaves a replay-safe stale row.
    }
  }

  static PracticePendingHint? _decode(dynamic raw) {
    if (raw is! String) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return PracticePendingHint.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  static bool _matches(
    PracticePendingHint? pending, {
    required String sessionId,
    required int aiCount,
  }) =>
      pending?.sessionId == sessionId.trim() && pending?.aiCount == aiCount;
}
