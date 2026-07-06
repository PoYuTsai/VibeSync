import 'package:hive_ce/hive_ce.dart';

import '../domain/follow_up_opt_in.dart';

/// 讀寫 48h 跟進提醒 opt-in 狀態的抽象，讓 service 可注入記憶體實作測試。
abstract class FollowUpOptInStore {
  FollowUpOptIn read();
  Future<void> write(FollowUpOptIn value);
}

/// 存於現有 settings box，key `followUpOptIn`，存 enum name 字串。
/// 讀不到／無法解析時退回 [FollowUpOptIn.unknown]（fail-open 到「還沒問過」）。
class HiveFollowUpOptInStore implements FollowUpOptInStore {
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
}
