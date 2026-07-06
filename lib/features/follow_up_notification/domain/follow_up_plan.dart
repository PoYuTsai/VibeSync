import 'follow_up_opt_in.dart';

/// 一次分析完成後，若需排程 48h 跟進提醒所產生的計畫（純資料）。
class FollowUpPlan {
  final String title;
  final String body;
  final DateTime fireAt;
  final String payload; // partnerId，tap 後 deep-link 用

  const FollowUpPlan({
    required this.title,
    required this.body,
    required this.fireAt,
    required this.payload,
  });
}

/// 決定「這次分析要不要排、排什麼」。
/// 只有 partnerId 非空且 opt-in=granted 才排；文案帶 displayName（空則用「這位對象」）。
/// 回傳 null 代表不排程。
FollowUpPlan? buildFollowUpPlan({
  required String? partnerId,
  required String displayName,
  required FollowUpOptIn optIn,
  required DateTime now,
}) {
  if (partnerId == null || partnerId.isEmpty) return null;
  if (!canSchedule(optIn)) return null;
  final name = displayName.trim().isEmpty ? '這位對象' : displayName.trim();
  return FollowUpPlan(
    title: '跟進提醒 👀',
    body: '跟$name的對話停兩天囉，要不要看看下一步？',
    fireAt: now.add(const Duration(hours: 48)),
    payload: partnerId,
  );
}
