import 'package:hive_ce/hive_ce.dart';

import '../../domain/entities/coaching_outcome_event.dart';
import '../../domain/repositories/coaching_outcome_repository.dart';

class CoachingOutcomeRepositoryImpl implements CoachingOutcomeRepository {
  CoachingOutcomeRepositoryImpl(this._box);

  final Box<CoachingOutcomeEvent> _box;

  @override
  CoachingOutcomeEvent? get(String id) => _box.get(id.trim());

  @override
  List<CoachingOutcomeEvent> listRecent({int? limit}) {
    return _sorted(_box.values, limit: limit);
  }

  @override
  List<CoachingOutcomeEvent> listByPartner(String partnerId, {int? limit}) {
    final normalized = CoachingOutcomeEvent.normalizeScope(partnerId);
    if (normalized == null) return const [];
    return _sorted(
      _box.values.where(
        (event) =>
            CoachingOutcomeEvent.normalizeScope(event.partnerId) == normalized,
      ),
      limit: limit,
    );
  }

  @override
  List<CoachingOutcomeEvent> listUnbound({int? limit}) {
    return _sorted(
      _box.values.where(
        (event) => CoachingOutcomeEvent.normalizeScope(event.partnerId) == null,
      ),
      limit: limit,
    );
  }

  @override
  List<CoachingOutcomeEvent> listByConversation(
    String conversationId, {
    int? limit,
  }) {
    final normalized = CoachingOutcomeEvent.normalizeScope(conversationId);
    if (normalized == null) return const [];
    return _sorted(
      _box.values.where(
        (event) =>
            CoachingOutcomeEvent.normalizeScope(event.conversationId) ==
            normalized,
      ),
      limit: limit,
    );
  }

  @override
  Future<void> put(CoachingOutcomeEvent event) async {
    await _box.put(event.id, event);
  }

  @override
  Future<void> delete(String id) async {
    await _box.delete(id.trim());
  }

  @override
  Future<int> deleteByPartner(String partnerId) async {
    final normalized = CoachingOutcomeEvent.normalizeScope(partnerId);
    if (normalized == null) return 0;
    final keys = _matchingKeys(
      (event) =>
          CoachingOutcomeEvent.normalizeScope(event.partnerId) == normalized,
    );
    await _box.deleteAll(keys);
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
    if (from == to) return 0;

    var moved = 0;
    for (final key in _box.keys.toList(growable: false)) {
      final event = _box.get(key);
      if (event == null) continue;
      if (CoachingOutcomeEvent.normalizeScope(event.partnerId) != from) {
        continue;
      }
      await _box.put(key, event.withPartnerId(to));
      moved += 1;
    }
    return moved;
  }

  @override
  Future<void> clearAll() async {
    await _box.clear();
  }

  List<dynamic> _matchingKeys(bool Function(CoachingOutcomeEvent event) test) {
    final keys = <dynamic>[];
    for (final key in _box.keys) {
      final event = _box.get(key);
      if (event != null && test(event)) {
        keys.add(key);
      }
    }
    return keys;
  }

  static List<CoachingOutcomeEvent> _sorted(
    Iterable<CoachingOutcomeEvent> events, {
    int? limit,
  }) {
    final sorted = events.toList(growable: false)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (limit == null || limit >= sorted.length) return sorted;
    if (limit <= 0) return const [];
    return sorted.take(limit).toList(growable: false);
  }
}
