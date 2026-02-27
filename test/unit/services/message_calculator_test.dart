import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/core/services/message_calculator.dart';

void main() {
  group('MessageCalculator.countMessages', () {
    test('counts single short message as 1', () {
      expect(MessageCalculator.countMessages('你好'), 1);
    });

    test('counts multiple lines correctly', () {
      expect(MessageCalculator.countMessages('你好\n在嗎\n吃飯了嗎'), 3);
    });

    test('counts long message by 200 char chunks', () {
      final longText = 'a' * 450; // 450 chars = ceil(450/200) = 3
      expect(MessageCalculator.countMessages(longText), 3);
    });

    test('handles empty lines', () {
      expect(MessageCalculator.countMessages('你好\n\n\n在嗎'), 2);
    });

    test('returns 0 for empty input', () {
      expect(MessageCalculator.countMessages(''), 0);
    });

    test('returns 0 for whitespace only', () {
      expect(MessageCalculator.countMessages('   \n\n   '), 0);
    });

    test('counts exactly 200 chars as 1 message', () {
      final text = 'a' * 200;
      expect(MessageCalculator.countMessages(text), 1);
    });

    test('counts 201 chars as 2 messages', () {
      final text = 'a' * 201;
      expect(MessageCalculator.countMessages(text), 2);
    });

    test('counts mixed short and long lines', () {
      // Line 1: "Hi" = 1 message
      // Line 2: 300 chars = 2 messages
      final line2 = 'a' * 300;
      expect(MessageCalculator.countMessages('Hi\n$line2'), 3);
    });

    test('handles Chinese characters correctly', () {
      // 5 Chinese characters = 1 message (< 200 chars)
      expect(MessageCalculator.countMessages('我今天很開心'), 1);
    });

    test('clamps minimum to 1 for non-empty', () {
      expect(MessageCalculator.countMessages('a'), 1);
    });
  });

  group('MessageCalculator.exceedsMaxLength', () {
    test('returns false for short text', () {
      expect(MessageCalculator.exceedsMaxLength('短文字'), false);
    });

    test('returns false at exactly 5000 chars', () {
      final text = 'a' * 5000;
      expect(MessageCalculator.exceedsMaxLength(text), false);
    });

    test('returns true at 5001 chars', () {
      final text = 'a' * 5001;
      expect(MessageCalculator.exceedsMaxLength(text), true);
    });
  });

  group('MessageCalculator.preview', () {
    test('returns correct preview for short text', () {
      final preview = MessageCalculator.preview('你好\n在嗎');

      expect(preview.messageCount, 2);
      expect(preview.charCount, 5); // "你好\n在嗎" = 5 chars
      expect(preview.exceedsLimit, false);
    });

    test('returns exceeds limit for long text', () {
      final longText = 'a' * 6000;
      final preview = MessageCalculator.preview(longText);

      expect(preview.messageCount, 30); // 6000 / 200 = 30
      expect(preview.charCount, 6000);
      expect(preview.exceedsLimit, true);
    });
  });
}
