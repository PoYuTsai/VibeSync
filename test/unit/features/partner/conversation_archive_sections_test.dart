import 'package:flutter_test/flutter_test.dart';

import 'package:vibesync/features/conversation/data/repositories/conversation_archive_store.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/partner/presentation/utils/conversation_archive_sections.dart';

Conversation _conversation({
  required String id,
  String? snapshot,
  int? analyzedCount,
}) =>
    Conversation(
      id: id,
      name: id,
      messages: const [],
      createdAt: DateTime(2026, 7, 1),
      updatedAt: DateTime(2026, 7, 1),
      ownerUserId: 'u1',
      partnerId: 'p1',
      lastAnalysisSnapshotJson: snapshot,
      lastAnalyzedMessageCount: analyzedCount,
    );

void main() {
  test('explicit archived/active marker 是分流權威且保留 active 輸入順序', () {
    final a = _conversation(id: 'a');
    final b = _conversation(id: 'b');
    final c = _conversation(
      id: 'c',
      snapshot: '{"ok":true}',
      analyzedCount: 0,
    );
    final entries = <String, ConversationArchiveEntry>{
      'b': ConversationArchiveEntry.archived(
        archivedAt: DateTime(2026, 7, 3),
      ),
      'c': ConversationArchiveEntry.active(
        changedAt: DateTime(2026, 7, 4),
      ),
    };

    final sections = partitionConversationsByArchive(
      [a, b, c],
      entryFor: (conversation) => entries[conversation.id],
      latestAnalysisAtFor: (_) => DateTime(2026, 7, 5),
    );

    expect(sections.active.map((item) => item.id), ['a', 'c']);
    expect(sections.archived.map((item) => item.conversation.id), ['b']);
  });

  test('無 marker 的舊資料只有 snapshot/count/event 三證據完整才保守歸檔', () {
    final complete = _conversation(
      id: 'complete',
      snapshot: '{"ok":true}',
      analyzedCount: 0,
    );
    final noHistory = _conversation(
      id: 'no-history',
      snapshot: '{"ok":true}',
      analyzedCount: 0,
    );
    final noSnapshot = _conversation(id: 'no-snapshot', analyzedCount: 0);

    final sections = partitionConversationsByArchive(
      [complete, noHistory, noSnapshot],
      entryFor: (_) => null,
      latestAnalysisAtFor: (id) =>
          id == 'complete' ? DateTime(2026, 7, 2) : null,
    );

    expect(sections.archived.map((item) => item.conversation.id), ['complete']);
    expect(sections.active.map((item) => item.id), [
      'no-history',
      'no-snapshot',
    ]);
  });

  test('舊分析事件早於 conversation.updatedAt 時留在 active，避免同數量編輯誤藏', () {
    final edited = _conversation(
      id: 'edited',
      snapshot: '{"ok":true}',
      analyzedCount: 0,
    )..updatedAt = DateTime(2026, 7, 5);

    final sections = partitionConversationsByArchive(
      [edited],
      entryFor: (_) => null,
      latestAnalysisAtFor: (_) => DateTime(2026, 7, 4),
    );

    expect(sections.active.single.id, 'edited');
    expect(sections.archived, isEmpty);
  });
}
