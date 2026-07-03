import 'dart:convert';

import 'package:hive_ce/hive_ce.dart';

/// 在途翻牌扣費 requestId 的持久化快照（單筆），比照
/// [PracticePendingHintStore] 模式。
///
/// server 的 `claim_practice_profile_draw` 已用 requestId 冪等去重，但 client
/// 過去每次點擊都當場鑄新 UUID：server 已入帳而回應丟失時，手動重試會用新
/// id 再抽再扣一次。改為：發起翻牌時先查 pending 快照，指紋吻合就沿用同
/// id（server replay 回同一位、不重扣），成功或 4xx 明確拒絕才 rotate。
/// 指紋＝currentProfileId（翻牌當下的目前對象；首抽為 null）：不吻合＝
/// 針對別的對象的舊意圖，一律作廢鑄新 id。
class PracticePendingDraw {
  const PracticePendingDraw({
    required this.currentProfileId,
    required this.requestId,
  });

  /// 翻牌當下的目前對象；locked 首抽時為 null。
  final String? currentProfileId;
  final String requestId;

  Map<String, dynamic> toJson() => {
        if (currentProfileId != null) 'currentProfileId': currentProfileId,
        'requestId': requestId,
      };

  /// 欄位缺漏／型別不對回 null（當不存在），絕不丟例外。
  static PracticePendingDraw? fromJson(Map<String, dynamic> json) {
    final currentProfileId = json['currentProfileId'];
    final requestId = json['requestId'];
    if (currentProfileId != null && currentProfileId is! String) return null;
    if (requestId is! String || requestId.isEmpty) return null;
    return PracticePendingDraw(
      currentProfileId: currentProfileId as String?,
      requestId: requestId,
    );
  }
}

/// 在途翻牌 requestId 的本地存取。讀寫都必須防呆：損毀資料當不存在、
/// 寫入失敗不丟例外——持久化失敗只是退回「重試鑄新 id」的舊行為，
/// 絕不阻斷翻牌主流程。
abstract class PracticePendingDrawStore {
  /// 取回在途快照；無資料或資料損毀回 null，絕不丟例外。
  PracticePendingDraw? load();

  Future<void> save(PracticePendingDraw pending);

  Future<void> clear();
}

/// 測試／無持久化情境用的記憶體版本。
class InMemoryPracticePendingDrawStore implements PracticePendingDrawStore {
  PracticePendingDraw? _pending;

  @override
  PracticePendingDraw? load() => _pending;

  @override
  Future<void> save(PracticePendingDraw pending) async => _pending = pending;

  @override
  Future<void> clear() async => _pending = null;
}

/// 正式版本：JSON 存進既有的加密 settings box（同
/// HivePracticePendingHintStore，不新增 Hive typeId／adapter／migration）。
///
/// 收 box **getter**：延遲到每次讀寫才取 box，全程 try-catch——box 沒開
/// （headless／widget 測試環境）只退化成「不持久化」，絕不在 provider
/// 建構期丟例外。
class HivePracticePendingDrawStore implements PracticePendingDrawStore {
  HivePracticePendingDrawStore(this._openBox);

  final Box Function() _openBox;

  static const String storageKey = 'practice_pending_draw';

  @override
  PracticePendingDraw? load() {
    try {
      final raw = _openBox().get(storageKey);
      if (raw is! String) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return PracticePendingDraw.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      // 損毀／舊格式：當作沒有在途翻牌，退回鑄新 id。
      return null;
    }
  }

  @override
  Future<void> save(PracticePendingDraw pending) async {
    try {
      await _openBox().put(storageKey, jsonEncode(pending.toJson()));
    } catch (_) {
      // 寫失敗只是失去「活過重建」的保險，絕不阻斷翻牌主流程。
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
