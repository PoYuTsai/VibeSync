import '../../../conversation/domain/entities/conversation.dart';

/// 互動紀錄「進行中 / 較早的對話」分區門檻：updatedAt 距今超過 30 天算舊。
const Duration conversationRecencyThreshold = Duration(days: 30);

/// 依 updatedAt 距 [now] 是否 ≤30 天把對話切成「進行中」與「較早的對話」。
/// 只分區不排序（輸入已由 repository 依 updatedAt desc 排好，兩區各自保序）。
class ConversationRecencySections {
  final List<Conversation> active;
  final List<Conversation> older;

  const ConversationRecencySections({
    required this.active,
    required this.older,
  });
}

ConversationRecencySections partitionConversationsByRecency(
  List<Conversation> conversations,
  DateTime now,
) {
  final active = <Conversation>[];
  final older = <Conversation>[];
  for (final conversation in conversations) {
    final age = now.difference(conversation.updatedAt);
    (age <= conversationRecencyThreshold ? active : older).add(conversation);
  }
  return ConversationRecencySections(active: active, older: older);
}
