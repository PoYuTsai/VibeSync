/// 48h 跟進提醒的 opt-in 狀態。
/// - [unknown]：沒問過軟卡（首次綁 partner 分析完成才會問）。
/// - [granted]：問過且系統授權成功。
/// - [denied]：問過但被拒／使用者關掉總開關。
enum FollowUpOptIn { unknown, granted, denied }

/// 只有 [FollowUpOptIn.unknown] 才顯示軟詢問卡，避免重複纏人。
bool shouldShowSoftCard(FollowUpOptIn s) => s == FollowUpOptIn.unknown;

/// 只有 [FollowUpOptIn.granted] 才實際排程本地通知。
bool canSchedule(FollowUpOptIn s) => s == FollowUpOptIn.granted;
