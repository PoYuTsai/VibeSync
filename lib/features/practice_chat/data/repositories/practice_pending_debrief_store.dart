import 'dart:convert';

import 'package:hive_ce/hive_ce.dart';

/// 在途 debrief requestId 的持久化快照（單筆）。
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

/// 寫入失敗只會退化成 process-lifetime 冪等，不得阻斷拆解主流程。
abstract class PracticePendingDebriefStore {
  PracticePendingDebrief? load();

  Future<void> save(PracticePendingDebrief pending);

  Future<void> clear();
}

class InMemoryPracticePendingDebriefStore
    implements PracticePendingDebriefStore {
  PracticePendingDebrief? _pending;

  @override
  PracticePendingDebrief? load() => _pending;

  @override
  Future<void> save(PracticePendingDebrief pending) async => _pending = pending;

  @override
  Future<void> clear() async => _pending = null;
}

/// JSON 存進既有 AES-256 加密 settings box；不新增 Hive adapter/migration。
class HivePracticePendingDebriefStore implements PracticePendingDebriefStore {
  HivePracticePendingDebriefStore(this._openBox);

  final Box Function() _openBox;

  static const String storageKey = 'practice_pending_debrief';

  @override
  PracticePendingDebrief? load() {
    try {
      final raw = _openBox().get(storageKey);
      if (raw is! String) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return PracticePendingDebrief.fromJson(
        Map<String, dynamic>.from(decoded),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(PracticePendingDebrief pending) async {
    try {
      await _openBox().put(storageKey, jsonEncode(pending.toJson()));
    } catch (_) {
      // fail-open：只失去跨重啟 replay 保護，不阻斷拆解。
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _openBox().delete(storageKey);
    } catch (_) {
      // 殘留快照會在 payload digest 不符時自然失效。
    }
  }
}
