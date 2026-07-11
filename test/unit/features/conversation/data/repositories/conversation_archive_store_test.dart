import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/conversation/data/repositories/conversation_archive_store.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';

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
      expect(
        store.entryFor(conversation)?.contentRevision,
        conversationContentRevision(conversation),
      );

      await store.markActive(conversation, changedAt: activeAt);
      expect(
        store.entryFor(conversation)?.status,
        ConversationArchiveStatus.active,
      );
      expect(store.entryFor(conversation)?.changedAt, activeAt);
      expect(store.entryFor(conversation)?.archivedAt, isNull);
      expect(
        store.entryFor(conversation)?.contentRevision,
        conversationContentRevision(conversation),
      );
    });

    test('content revision changes for same-count message edits', () {
      final conversation = _conversation(id: 'revision', ownerUserId: 'u-1')
        ..messages = [
          Message(
            id: 'm-1',
            content: '原本內容',
            isFromMe: false,
            timestamp: DateTime(2026, 7, 11),
          ),
        ];
      final before = conversationContentRevision(conversation);

      conversation.messages = [
        Message(
          id: 'm-1',
          content: '同一則但內容已編輯',
          isFromMe: false,
          timestamp: DateTime(2026, 7, 11),
        ),
      ];

      expect(conversationContentRevision(conversation), isNot(before));
    });

    test('analyzed-prefix revision ignores messages appended after analysis',
        () {
      final conversation = _conversation(id: 'prefix', ownerUserId: 'u-1')
        ..messages = [
          Message(
            id: 'm-1',
            content: '已分析內容',
            isFromMe: false,
            timestamp: DateTime(2026, 7, 11),
          ),
        ];
      final analyzedRevision = conversationContentRevision(
        conversation,
        messageCount: 1,
      );
      conversation.messages = [
        ...conversation.messages,
        Message(
          id: 'm-2',
          content: '後來才新增',
          isFromMe: true,
          timestamp: DateTime(2026, 7, 11, 0, 1),
        ),
      ];

      expect(
        conversationContentRevision(conversation, messageCount: 1),
        analyzedRevision,
      );
      expect(
          conversationContentRevision(conversation), isNot(analyzedRevision));
    });

    test('active marker preserves the revision of the restorable snapshot',
        () async {
      final conversation = _conversation(id: 'preserve', ownerUserId: 'u-1')
        ..messages = [
          Message(
            id: 'm-1',
            content: '已分析內容',
            isFromMe: false,
            timestamp: DateTime(2026, 7, 11),
          ),
        ];
      await store.markArchived(
        conversation,
        archivedAt: DateTime.utc(2026, 7, 11),
      );
      final analyzedRevision = conversationContentRevision(conversation);
      conversation.messages = [
        Message(
          id: 'm-1',
          content: '分析後編輯的新內容',
          isFromMe: false,
          timestamp: DateTime(2026, 7, 11),
        ),
      ];

      await store.markActive(conversation);

      expect(store.entryFor(conversation)?.contentRevision, analyzedRevision);
      expect(
        store.entryFor(conversation)?.contentRevision,
        isNot(conversationContentRevision(conversation)),
      );
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
