/// Deterministic FNV-1a hash → 正 31-bit int，跨啟動穩定。
/// 用於本地通知 id（一 partner 一則待發通知）。
///
/// 為何不用 `String.hashCode`：Dart 的 hashCode 會隨進程 hash seed 隨機化，
/// 跨啟動不保證一致，導致下次啟動 cancel 不到上次排的那則排程。
int followUpNotificationId(String partnerId) {
  const int fnvOffset = 0x811c9dc5;
  const int fnvPrime = 0x01000193;
  int hash = fnvOffset;
  for (final codeUnit in partnerId.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * fnvPrime) & 0xFFFFFFFF;
  }
  return hash & 0x7FFFFFFF; // 折成正 31-bit，符合 plugin int id 範圍
}
