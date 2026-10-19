/// 48 小時跟進提醒的窄 port：v3 判成關心（自傷、未成年）或停（她拒絕或封鎖）時，收回這位
/// 對象已排的那則（P1 安全修正；主審第 1 輪 finding 1）。串流 notifier（離開分析頁也繼續跑）、
/// 存檔與冷啟動還原都會叫；取消同一個 id，重複叫沒關係。
library;

typedef FollowUpSilencer = Future<void> Function(String partnerId);
