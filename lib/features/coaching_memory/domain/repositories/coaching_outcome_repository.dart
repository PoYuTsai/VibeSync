import '../entities/coaching_outcome_event.dart';

abstract class CoachingOutcomeRepository {
  CoachingOutcomeEvent? get(String id);

  List<CoachingOutcomeEvent> listRecent({int? limit});

  List<CoachingOutcomeEvent> listByPartner(String partnerId, {int? limit});

  List<CoachingOutcomeEvent> listUnbound({int? limit});

  List<CoachingOutcomeEvent> listByConversation(
    String conversationId, {
    int? limit,
  });

  Future<void> put(CoachingOutcomeEvent event);

  Future<void> delete(String id);

  Future<int> deleteByPartner(String partnerId);

  Future<int> reassignPartner({
    required String fromPartnerId,
    required String toPartnerId,
  });

  Future<void> clearAll();
}
