import '../entities/coach_chat_result.dart';

abstract class CoachChatRepository {
  List<CoachChatResult> listByConversation(String conversationId);

  CoachChatResult? latestForConversation(String conversationId);

  Future<void> put(CoachChatResult result);

  Future<void> deleteConversation(String conversationId);

  Future<void> clearAll();
}
