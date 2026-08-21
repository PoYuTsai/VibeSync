/// 歷史脈絡摘要的窄 port：請求組裝器只需要「已持久化摘要、一次性摘要
/// 格式化、近幾輪裁切」三個操作與兩個輪數常數。data 層 MemoryService
/// 在 composition root 以 adapter 實作。
library;

import '../../../conversation/domain/entities/conversation.dart';
import '../../../conversation/domain/entities/message.dart';

abstract class ConversationMemoryPort {
  /// 已持久化的歷史摘要 prompt 區塊；沒有可用摘要回 null 或空字串。
  String? persistedHistoricalSummary(Conversation conversation);

  /// 為 0..[olderRounds] 生成一次性摘要並格式化為 prompt 區塊
  /// （沒有內容時回空字串）。
  Future<String> formatEphemeralSummary(
    Conversation conversation,
    int olderRounds,
  );

  List<Message> clipToRecentRounds(List<Message> messages, int maxRounds);

  int get maxRecentRounds;
  int get minRoundsPerSummary;
}
