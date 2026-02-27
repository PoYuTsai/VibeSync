import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/conversation/data/repositories/conversation_repository.dart';

void main() {
  late ConversationRepository repository;

  setUp(() {
    repository = ConversationRepository();
  });

  group('parseMessages', () {
    test('parses messages correctly', () {
      const rawText = '''
她: 你好
我: 嗨
她: 在幹嘛
我: 工作中
''';

      final messages = repository.parseMessages(rawText);

      expect(messages.length, 4);
      expect(messages[0].isFromMe, false);
      expect(messages[0].content, '你好');
      expect(messages[1].isFromMe, true);
      expect(messages[1].content, '嗨');
      expect(messages[2].isFromMe, false);
      expect(messages[2].content, '在幹嘛');
      expect(messages[3].isFromMe, true);
      expect(messages[3].content, '工作中');
    });

    test('handles empty lines', () {
      const rawText = '''
她: 你好

我: 嗨
''';

      final messages = repository.parseMessages(rawText);
      expect(messages.length, 2);
    });

    test('ignores invalid lines', () {
      const rawText = '''
她: 你好
無效的行
我: 嗨
''';

      final messages = repository.parseMessages(rawText);
      expect(messages.length, 2);
    });

    test('handles full-width colon', () {
      const rawText = '''
她：你好
我：嗨
''';

      final messages = repository.parseMessages(rawText);
      expect(messages.length, 2);
      expect(messages[0].content, '你好');
      expect(messages[1].content, '嗨');
    });

    test('handles 他 prefix for male counterpart', () {
      const rawText = '''
他: 你好
我: 嗨
''';

      final messages = repository.parseMessages(rawText);
      expect(messages.length, 2);
      expect(messages[0].isFromMe, false);
      expect(messages[0].content, '你好');
    });

    test('ignores lines without valid prefix', () {
      const rawText = '''
她: 你好
隨便打的字
朋友: 這個不算
我: 嗨
''';

      final messages = repository.parseMessages(rawText);
      expect(messages.length, 2);
    });

    test('returns empty list for empty input', () {
      final messages = repository.parseMessages('');
      expect(messages.length, 0);
    });

    test('handles message with whitespace', () {
      const rawText = '''
她:   你好世界
我:   嗨
''';

      final messages = repository.parseMessages(rawText);
      expect(messages.length, 2);
      expect(messages[0].content, '你好世界');
      expect(messages[1].content, '嗨');
    });
  });
}
