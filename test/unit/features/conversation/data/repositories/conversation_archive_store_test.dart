import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/conversation/data/repositories/conversation_archive_store.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';

Conversation _conversation({
  required String id,
  required String ownerUserId,
}) =>
    Conversation(
      id: id,
      name: 'conversation-$id',
      messages: const [],
      createdAt: DateTime(2026, 7, 11),
      updatedAt: DateTime(2026, 7, 11),
      ownerUserId: ownerUserId,
    );

void main() {
  group('HiveConversationArchiveStore', () {
    late Box<dynamic> box;
    late HiveConversationArchiveStore store;

    setUp(() async {
      Hive.init('./.dart_tool/test_hive_conversation_archive');
      final timestamp = DateTime.now().microsecondsSinceEpoch;
      box = await Hive.openBox<dynamic>('conversation_archive_$timestamp');
      store = HiveConversationArchiveStore(() => box);
    });

    tearDown(() async {
      await box.deleteFromDisk();
    });

    test('archive and active markers persist with their timestamps', () async {
      final conversation = _conversation(id: 'c-1', ownerUserId: 'u-1');
      final archivedAt = DateTime.utc(2026, 7, 11, 9, 30);
      final activeAt = DateTime.utc(2026, 7, 11, 10, 45);

      await store.markArchived(conversation, archivedAt: archivedAt);
      expect(
        store.entryFor(conversation)?.status,
        ConversationArchiveStatus.archived,
      );
      expect(store.entryFor(conversation)?.archivedAt, archivedAt);

      await store.markActive(conversation, changedAt: activeAt);
      expect(
        store.entryFor(conversation)?.status,
        ConversationArchiveStatus.active,
      );
      expect(store.entryFor(conversation)?.changedAt, activeAt);
      expect(store.entryFor(conversation)?.archivedAt, isNull);
    });

    test('same conversation id is isolated by owner', () async {
      final firstOwner = _conversation(id: 'same-id', ownerUserId: 'u-1');
      final secondOwner = _conversation(id: 'same-id', ownerUserId: 'u-2');

      await store.markArchived(
        firstOwner,
        archivedAt: DateTime.utc(2026, 7, 11),
      );

      expect(store.entryFor(firstOwner), isNotNull);
      expect(store.entryFor(secondOwner), isNull);
    });

    test('malformed marker fails open and remove clears a valid marker',
        () async {
      final conversation = _conversation(id: 'c-2', ownerUserId: 'u-1');
      await box.put(
        'conversation_archive_v1:u-1:c-2',
        <String, Object?>{'status': 'archived', 'changedAt': 123},
      );

      expect(store.entryFor(conversation), isNull);

      await store.markArchived(
        conversation,
        archivedAt: DateTime.utc(2026, 7, 11),
      );
      await store.remove(conversation);
      expect(store.entryFor(conversation), isNull);
    });

    test('unavailable box fails open on reads', () {
      final unavailable = HiveConversationArchiveStore(
        () => throw HiveError('Box not found'),
      );

      expect(
        unavailable.entryFor(_conversation(id: 'c-3', ownerUserId: 'u-1')),
        isNull,
      );
    });
  });
}
