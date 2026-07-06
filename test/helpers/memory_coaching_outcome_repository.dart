import 'package:vibesync/features/coaching_memory/domain/entities/coaching_outcome_event.dart';
import 'package:vibesync/features/coaching_memory/domain/repositories/coaching_outcome_repository.dart';

class MemoryCoachingOutcomeRepository implements CoachingOutcomeRepository {
  final _events = <String, CoachingOutcomeEvent>{};

  @override
  CoachingOutcomeEvent? get(String id) => _events[id.trim()];

  @override
  List<CoachingOutcomeEvent> listRecent({int? limit}) => _limit(
        _events.values.toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
        limit,
      );

  @override
  List<CoachingOutcomeEvent> listByPartner(String partnerId, {int? limit}) {
    final normalized = CoachingOutcomeEvent.normalizeScope(partnerId);
    if (normalized == null) return const [];
    return _limit(
      listRecent()
          .where((event) =>
              CoachingOutcomeEvent.normalizeScope(event.partnerId) ==
              normalized)
          .toList(),
      limit,
    );
  }

  @override
  List<CoachingOutcomeEvent> listUnbound({int? limit}) {
    return _limit(
      listRecent()
          .where((event) =>
              CoachingOutcomeEvent.normalizeScope(event.partnerId) == null)
          .toList(),
      limit,
    );
  }

  @override
  List<CoachingOutcomeEvent> listByConversation(
    String conversationId, {
    int? limit,
  }) {
    final normalized = CoachingOutcomeEvent.normalizeScope(conversationId);
    if (normalized == null) return const [];
    return _limit(
      listRecent()
          .where((event) =>
              CoachingOutcomeEvent.normalizeScope(event.conversationId) ==
              normalized)
          .toList(),
      limit,
    );
  }

  @override
  Future<void> put(CoachingOutcomeEvent event) async {
    _events[event.id] = event;
  }

  @override
  Future<void> delete(String id) async {
    _events.remove(id.trim());
  }

  @override
  Future<int> deleteByPartner(String partnerId) async {
    final normalized = CoachingOutcomeEvent.normalizeScope(partnerId);
    if (normalized == null) return 0;
    final keys = _events.entries
        .where((entry) =>
            CoachingOutcomeEvent.normalizeScope(entry.value.partnerId) ==
            normalized)
        .map((entry) => entry.key)
        .toList();
    for (final key in keys) {
      _events.remove(key);
    }
    return keys.length;
  }

  @override
  Future<int> reassignPartner({
    required String fromPartnerId,
    required String toPartnerId,
  }) async {
    final from = CoachingOutcomeEvent.normalizeScope(fromPartnerId);
    final to = CoachingOutcomeEvent.normalizeScope(toPartnerId);
    if (from == null || to == null) {
      throw ArgumentError('partner ids must be non-empty');
    }
    var count = 0;
    for (final entry in _events.entries.toList()) {
      if (CoachingOutcomeEvent.normalizeScope(entry.value.partnerId) == from) {
        _events[entry.key] = entry.value.withPartnerId(to);
        count++;
      }
    }
    return count;
  }

  @override
  Future<void> clearAll() async {
    _events.clear();
  }

  List<CoachingOutcomeEvent> _limit(
    List<CoachingOutcomeEvent> events,
    int? limit,
  ) {
    if (limit == null || limit >= events.length) return events;
    if (limit <= 0) return const [];
    return events.take(limit).toList();
  }
}
