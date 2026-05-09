import 'package:hive_ce/hive_ce.dart';

import '../../domain/entities/coach_chat_result.dart';
import '../../domain/repositories/coach_chat_repository.dart';

class CoachChatRepositoryImpl implements CoachChatRepository {
  CoachChatRepositoryImpl(this._box, {this.keepPerConversation = 10});

  final Box<CoachChatResult> _box;
  final int keepPerConversation;

  @override
  List<CoachChatResult> listByConversation(String conversationId) {
    final list = _box.values
        .where((result) => result.conversationId == conversationId)
        .toList()
      ..sort((a, b) => b.generatedAt.compareTo(a.generatedAt));
    return list;
  }

  @override
  CoachChatResult? latestForConversation(String conversationId) {
    final list = listByConversation(conversationId);
    return list.isEmpty ? null : list.first;
  }

  @override
  Future<void> put(CoachChatResult result) async {
    await _box.put(result.id, result);
    await _trimConversation(result.conversationId);
  }

  Future<void> _trimConversation(String conversationId) async {
    final list = listByConversation(conversationId);
    if (list.length <= keepPerConversation) return;
    final stale = list.skip(keepPerConversation);
    await Future.wait(stale.map((result) => _box.delete(result.id)));
  }

  @override
  Future<void> deleteConversation(String conversationId) async {
    final ids = _box.values
        .where((result) => result.conversationId == conversationId)
        .map((result) => result.id)
        .toList();
    await Future.wait(ids.map(_box.delete));
  }

  @override
  Future<void> clearAll() => _box.clear();
}
