import 'dart:convert';

import 'package:hive_ce/hive_ce.dart';

/// 在途 hint 扣費 requestId 的持久化快照（單筆）。
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

/// 在途 hint requestId 的本地存取。所有實作讀寫都必須防呆：
/// 損毀資料當不存在、寫入失敗不丟例外——持久化失敗只是退回「重建後
/// 鑄新 id」的舊行為，絕不阻斷 hint 主流程。
abstract class PracticePendingHintStore {
  /// 取回在途快照；無資料或資料損毀回 null，絕不丟例外。
  PracticePendingHint? load();

  Future<void> save(PracticePendingHint pending);

  Future<void> clear();
}

/// 測試／無持久化情境用的記憶體版本。
class InMemoryPracticePendingHintStore implements PracticePendingHintStore {
  PracticePendingHint? _pending;

  @override
  PracticePendingHint? load() => _pending;

  @override
  Future<void> save(PracticePendingHint pending) async => _pending = pending;

  @override
  Future<void> clear() async => _pending = null;
}

/// 正式版本：JSON 存進既有的加密 settings box。比照
/// HivePracticeDrawDraftStore 刻意不新增 Hive typeId／adapter／migration——
/// 這是短命的單筆狀態，JSON 足矣。
///
/// 收 box **getter** 而非 box 本身：延遲到每次讀寫才取 box，且全程包在
/// try-catch 裡——box 沒開（headless／widget 測試環境）只是退化成
/// 「不持久化」，絕不在 provider 建構期丟例外。
class HivePracticePendingHintStore implements PracticePendingHintStore {
  HivePracticePendingHintStore(this._openBox);

  final Box Function() _openBox;

  static const String storageKey = 'practice_pending_hint';

  @override
  PracticePendingHint? load() {
    try {
      final raw = _openBox().get(storageKey);
      if (raw is! String) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return PracticePendingHint.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      // 損毀／舊格式：當作沒有在途 hint，退回鑄新 id。
      return null;
    }
  }

  @override
  Future<void> save(PracticePendingHint pending) async {
    try {
      await _openBox().put(storageKey, jsonEncode(pending.toJson()));
    } catch (_) {
      // 寫失敗只是失去「活過重建」的保險，絕不阻斷 hint 主流程。
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _openBox().delete(storageKey);
    } catch (_) {
      // 清失敗留下的殘骸靠指紋不吻合自然作廢。
    }
  }
}
