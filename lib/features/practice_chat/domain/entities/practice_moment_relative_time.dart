// Threads 慣例的相對時間標籤（純函式，可 TDD）。
//
// 「剛剛 / N 分鐘前 / N 小時前 / 昨天 HH:mm / M月D日」——不用絕對時間戳，
// 這是 Threads 版面（D5b）的一部分：時間是次級資訊，短、不搶焦點。
//
// **時鐘偏差鐵則**：server 與手機的時鐘會差幾秒，postedAt 有可能「在未來」。
// 一律當「剛剛」，絕不出現「-3 小時前」。

/// [postedAt] 相對於 [now] 的短標籤。兩者都會先轉成本地時區再比。
String momentRelativeLabel(DateTime postedAt, DateTime now) {
  final local = postedAt.toLocal();
  final localNow = now.toLocal();
  final elapsed = localNow.difference(local);

  // 未來時間（時鐘偏差）→「剛剛」，不做負數運算。
  if (elapsed.isNegative) return '剛剛';
  if (elapsed.inMinutes < 1) return '剛剛';
  if (elapsed.inMinutes < 60) return '${elapsed.inMinutes} 分鐘前';

  // 小時／昨天的分界看**日曆日**而不是 24 小時：早上 9 點看昨晚 11 點的貼文
  // 該說「昨天 23:00」，不是「10 小時前」。
  final today = DateTime(localNow.year, localNow.month, localNow.day);
  final postedDay = DateTime(local.year, local.month, local.day);
  final dayGap = today.difference(postedDay).inDays;

  if (dayGap <= 0) return '${elapsed.inHours} 小時前';
  if (dayGap == 1) {
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '昨天 $hh:$mm';
  }
  return '${local.month}月${local.day}日';
}
