import 'package:hive_ce/hive_ce.dart';

import '../domain/follow_up_opt_in.dart';

/// 讀寫 48h 跟進提醒 opt-in 狀態的抽象，讓 service 可注入記憶體實作測試。
abstract class FollowUpOptInStore {
  FollowUpOptIn read();
  Future<void> write(FollowUpOptIn value);

  /// 值變更通知（跨頁 reactive UI 用；預設空 stream，fake 可不管）。
  /// 2026-08-01 Eric 回報：設定頁開啟提醒後回首頁，起步清單打勾不更新
  /// ——read() 非 reactive、pop 不觸發 rebuild，重開 app 才對。
  Stream<FollowUpOptIn> changes() => const Stream.empty();
}

/// 存於現有 settings box，key `followUpOptIn`，存 enum name 字串。
/// 讀不到／無法解析時退回 [FollowUpOptIn.unknown]（fail-open 到「還沒問過」）。
class HiveFollowUpOptInStore extends FollowUpOptInStore {
  static const String storageKey = 'followUpOptIn';
  final Box _box;

  HiveFollowUpOptInStore(this._box);

  @override
  FollowUpOptIn read() {
    final raw = _box.get(storageKey) as String?;
    return FollowUpOptIn.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => FollowUpOptIn.unknown,
    );
  }

  @override
  Future<void> write(FollowUpOptIn value) => _box.put(storageKey, value.name);

  @override
  Stream<FollowUpOptIn> changes() =>
      _box.watch(key: storageKey).map((_) => read());
}
