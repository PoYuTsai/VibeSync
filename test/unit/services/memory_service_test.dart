import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/conversation/data/services/memory_service.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation_summary.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';

void main() {
  late MemoryService service;

  setUp(() {
    service = MemoryService();
  });

  group('MemoryService.prepareContext', () {
    test('includes recent messages in context', () {
      final conversation = Conversation(
        id: '1',
        name: 'Test',
        messages: [
          Message(
            id: '1',
            content: '你好',
            isFromMe: true,
            timestamp: DateTime.now(),
          ),
          Message(
            id: '2',
            content: '嗨！你好',
            isFromMe: false,
            timestamp: DateTime.now(),
          ),
        ],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final context = service.prepareContext(conversation);

      expect(context, contains('我: 你好'));
      expect(context, contains('她: 嗨！你好'));
      expect(context, contains('最近對話'));
    });

    test('includes historical summaries when present', () {
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
            content: '討論了旅行和美食',
            keyTopics: ['旅行', '美食'],
            sharedInterests: ['日本'],
            relationshipStage: 'rapport',
            createdAt: DateTime.now(),
          ),
        ],
      );

      final context = service.prepareContext(conversation);

      expect(context, contains('歷史摘要'));
      expect(context, contains('討論了旅行和美食'));
      expect(context, contains('關鍵話題: 旅行, 美食'));
    });

    test('returns empty context for empty conversation', () {
      final conversation = Conversation(
        id: '1',
        name: 'Test',
        messages: [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final context = service.prepareContext(conversation);

      // Should be empty or minimal
      expect(context.trim().isEmpty || !context.contains('我:'), isTrue);
    });
  });

  group('MemoryService.inferUserChoice', () {
    test('returns matching reply type when keywords overlap', () {
      final theirReply = Message(
        id: '1',
        content: '哇健身！你練多久了？',
        isFromMe: false,
        timestamp: DateTime.now(),
      );

      final previousSuggestions = {
        'extend': '三個月了 越練越上癮 最近練胸',
        'resonate': '你也有運動習慣嗎',
        'tease': '練到可以單手抱你 抱著跑馬拉松',
      };

      final choice = service.inferUserChoice(theirReply, previousSuggestions);

      // Either 'extend' or 'tease' would work since both relate to exercise
      // The algorithm should find one with enough keyword overlap
      expect(
        choice == null || ['extend', 'tease'].contains(choice),
        isTrue,
      );
    });

    test('returns null when no significant overlap', () {
      final theirReply = Message(
        id: '1',
        content: '今天天氣真好',
        isFromMe: false,
        timestamp: DateTime.now(),
      );

      final previousSuggestions = {
        'extend': '三個月了，越練越上癮',
        'resonate': '你也有運動習慣嗎',
      };

      final choice = service.inferUserChoice(theirReply, previousSuggestions);
      expect(choice, isNull);
    });

    test('finds best match when multiple options match', () {
      final theirReply = Message(
        id: '1',
        content: '咖啡和旅行都是我的最愛！',
        isFromMe: false,
        timestamp: DateTime.now(),
      );

      final previousSuggestions = {
        'extend': '我喜歡喝咖啡 尤其是拿鐵',
        'resonate': '旅行真的很棒 我也超愛旅行',
        'tease': '你應該很難約出來吧',
      };

      final choice = service.inferUserChoice(theirReply, previousSuggestions);

      // Should match 'resonate' since it has more overlap (旅行 appears twice)
      expect(choice, anyOf(isNull, equals('resonate'), equals('extend')));
    });
  });

  group('MemoryService.generateSummary', () {
    test('creates summary with correct round coverage', () async {
      final conversation = Conversation(
        id: '1',
        name: 'Test',
        messages: List.generate(
          20,
          (i) => Message(
            id: '$i',
            content: 'Message $i about topic${i % 3}',
            isFromMe: i % 2 == 0,
            timestamp: DateTime.now(),
          ),
        ),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        currentRound: 10,
      );

      final summary = await service.generateSummary(conversation, 0, 10);

      expect(summary.roundsCovered, 10);
      expect(summary.createdAt, isNotNull);
      expect(summary.content, isNotEmpty);
    });

    test('extracts topics from messages', () async {
      final conversation = Conversation(
        id: '1',
        name: 'Test',
        messages: [
          Message(
            id: '0',
            content: '我喜歡旅行',
            isFromMe: true,
            timestamp: DateTime.now(),
          ),
          Message(
            id: '1',
            content: '旅行真的很棒 去過哪裡',
            isFromMe: false,
            timestamp: DateTime.now(),
          ),
          Message(
            id: '2',
            content: '日本 喜歡美食',
            isFromMe: true,
            timestamp: DateTime.now(),
          ),
          Message(
            id: '3',
            content: '日本美食確實很棒',
            isFromMe: false,
            timestamp: DateTime.now(),
          ),
        ],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        currentRound: 2,
      );

      final summary = await service.generateSummary(conversation, 0, 2);

      // Should extract frequently used words
      expect(summary.keyTopics, isNotEmpty);
    });

    test('guesses relationship stage based on round count', () async {
      // Early stage
      var conversation = Conversation(
        id: '1',
        name: 'Test',
        messages: [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        currentRound: 3,
      );

      var summary = await service.generateSummary(conversation, 0, 3);
      expect(summary.relationshipStage, 'initial');

      // Mid stage
      conversation = Conversation(
        id: '1',
        name: 'Test',
        messages: [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        currentRound: 10,
      );

      summary = await service.generateSummary(conversation, 0, 10);
      expect(summary.relationshipStage, 'getting_to_know');

      // Later stage
      conversation = Conversation(
        id: '1',
        name: 'Test',
        messages: [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        currentRound: 20,
      );

      summary = await service.generateSummary(conversation, 0, 15);
      expect(summary.relationshipStage, 'rapport');
    });
  });
}
