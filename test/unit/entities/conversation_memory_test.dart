import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation_summary.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';

void main() {
  group('ConversationSummary', () {
    test('creates with required fields', () {
      final summary = ConversationSummary(
        id: '1',
        roundsCovered: 10,
        content: 'Summary of conversation',
        keyTopics: ['travel', 'food'],
        sharedInterests: ['hiking'],
        relationshipStage: 'getting_to_know',
        createdAt: DateTime(2026, 2, 27),
      );

      expect(summary.id, '1');
      expect(summary.roundsCovered, 10);
      expect(summary.content, 'Summary of conversation');
      expect(summary.keyTopics, ['travel', 'food']);
      expect(summary.sharedInterests, ['hiking']);
      expect(summary.relationshipStage, 'getting_to_know');
    });

    test('fromJson creates instance correctly', () {
      final json = {
        'id': '2',
        'roundsCovered': 15,
        'content': 'They talked about movies',
        'keyTopics': ['movies', 'music'],
        'sharedInterests': ['jazz'],
        'relationshipStage': 'rapport',
        'createdAt': '2026-02-27T10:00:00.000',
      };

      final summary = ConversationSummary.fromJson(json);

      expect(summary.id, '2');
      expect(summary.roundsCovered, 15);
      expect(summary.content, 'They talked about movies');
      expect(summary.keyTopics, ['movies', 'music']);
      expect(summary.sharedInterests, ['jazz']);
    });

    test('fromJson handles missing optional fields', () {
      final json = <String, dynamic>{};

      final summary = ConversationSummary.fromJson(json);

      expect(summary.roundsCovered, 0);
      expect(summary.content, '');
      expect(summary.keyTopics, isEmpty);
      expect(summary.sharedInterests, isEmpty);
      expect(summary.relationshipStage, 'unknown');
    });

    test('toJson serializes correctly', () {
      final summary = ConversationSummary(
        id: '1',
        roundsCovered: 10,
        content: 'Summary',
        keyTopics: ['topic1'],
        sharedInterests: ['interest1'],
        relationshipStage: 'stage1',
        createdAt: DateTime(2026, 2, 27, 10, 0, 0),
      );

      final json = summary.toJson();

      expect(json['id'], '1');
      expect(json['roundsCovered'], 10);
      expect(json['content'], 'Summary');
      expect(json['keyTopics'], ['topic1']);
      expect(json['sharedInterests'], ['interest1']);
      expect(json['relationshipStage'], 'stage1');
      expect(json['createdAt'], '2026-02-27T10:00:00.000');
    });
  });

  group('Conversation memory features', () {
    Conversation createConversation({int messageCount = 0}) {
      final messages = List.generate(
        messageCount,
        (i) => Message(
          id: '$i',
          content: 'Message $i',
          isFromMe: i % 2 == 0,
          timestamp: DateTime.now(),
        ),
      );

      return Conversation(
        id: '1',
        name: 'Test',
        messages: messages,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        currentRound: messageCount ~/ 2,
      );
    }

    test('initializes with zero rounds by default', () {
      final conversation = Conversation(
        id: '1',
        name: 'Test',
        messages: [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(conversation.currentRound, 0);
      expect(conversation.summaries, isNull);
      expect(conversation.lastUserChoice, isNull);
    });

    test('getRecentMessages returns all when less than limit', () {
      final conversation = createConversation(messageCount: 10);

      final recent = conversation.getRecentMessages(15);

      expect(recent.length, 10);
    });

    test('getRecentMessages returns last N rounds', () {
      final conversation = createConversation(messageCount: 40);

      final recent = conversation.getRecentMessages(15); // 15 rounds = 30 messages

      expect(recent.length, 30);
      expect(recent.first.content, 'Message 10'); // Messages 10-39
    });

    test('needsSummary returns false when under 15 rounds', () {
      final conversation = createConversation(messageCount: 20); // 10 rounds

      expect(conversation.needsSummary, false);
    });

    test('needsSummary returns true when over 15 rounds and no summary', () {
      final conversation = Conversation(
        id: '1',
        name: 'Test',
        messages: [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        currentRound: 16,
        summaries: null,
      );

      expect(conversation.needsSummary, true);
    });

    test('needsSummary returns false when has summaries', () {
      final conversation = Conversation(
        id: '1',
        name: 'Test',
        messages: [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        currentRound: 20,
        summaries: [
          ConversationSummary(
            id: '1',
            roundsCovered: 10,
            content: 'Summary',
            keyTopics: [],
            sharedInterests: [],
            relationshipStage: 'intro',
            createdAt: DateTime.now(),
          ),
        ],
      );

      expect(conversation.needsSummary, false);
    });

    test('incrementRound increases round count', () {
      final conversation = createConversation(messageCount: 0);

      conversation.incrementRound();
      expect(conversation.currentRound, 1);

      conversation.incrementRound();
      expect(conversation.currentRound, 2);
    });

    test('addSummary creates list if null', () {
      final conversation = Conversation(
        id: '1',
        name: 'Test',
        messages: [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(conversation.summaries, isNull);

      final summary = ConversationSummary(
        id: '1',
        roundsCovered: 10,
        content: 'Summary',
        keyTopics: [],
        sharedInterests: [],
        relationshipStage: 'intro',
        createdAt: DateTime.now(),
      );

      conversation.addSummary(summary);

      expect(conversation.summaries, isNotNull);
      expect(conversation.summaries!.length, 1);
    });

    test('addSummary appends to existing list', () {
      final conversation = Conversation(
        id: '1',
        name: 'Test',
        messages: [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        summaries: [
          ConversationSummary(
            id: '1',
            roundsCovered: 10,
            content: 'First',
            keyTopics: [],
            sharedInterests: [],
            relationshipStage: 'intro',
            createdAt: DateTime.now(),
          ),
        ],
      );

      final newSummary = ConversationSummary(
        id: '2',
        roundsCovered: 10,
        content: 'Second',
        keyTopics: [],
        sharedInterests: [],
        relationshipStage: 'rapport',
        createdAt: DateTime.now(),
      );

      conversation.addSummary(newSummary);

      expect(conversation.summaries!.length, 2);
      expect(conversation.summaries!.last.content, 'Second');
    });

    test('lastUserChoice tracks selection', () {
      final conversation = Conversation(
        id: '1',
        name: 'Test',
        messages: [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        lastUserChoice: 'extend',
      );

      expect(conversation.lastUserChoice, 'extend');
    });
  });
}
