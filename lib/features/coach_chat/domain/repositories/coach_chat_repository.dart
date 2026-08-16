import '../entities/coach_chat_result.dart';
import '../entities/unified_coach_result.dart';

abstract class CoachChatRepository {
  List<CoachChatResult> listByConversation(String conversationId);

  CoachChatResult? latestForConversation(String conversationId);

  Future<void> put(CoachChatResult result);

  Future<void> deleteConversation(String conversationId);

  Future<void> clearAll();

  /// Phase D scope-keyed reads/writes over the unified store.
  ///
  /// [scopeType] is `'conversation'` or `'partner'`; [scopeId] is the
  /// conversationId / partnerId respectively.
  List<UnifiedCoachResult> listByScope(String scopeType, String scopeId);

  UnifiedCoachResult? latestForScope(String scopeType, String scopeId);

  Future<void> putUnified(UnifiedCoachResult result);

  Future<void> deleteScope(String scopeType, String scopeId);

  /// 刪除單筆 unified 列（「想問別的」關掉釐清串用）。只砍 unified box；
  /// read-bridge 的 legacy 列刪不到，回傳 false 讓呼叫端停手。
  Future<bool> deleteUnified(String id);
}
