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
}
