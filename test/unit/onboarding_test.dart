// test/unit/onboarding_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/onboarding/data/demo_conversation.dart';

void main() {
  group('DemoConversation', () {
    test('has valid messages', () {
      expect(DemoConversation.messages.length, 3);
      expect(DemoConversation.messages[0].isFromMe, false);
      expect(DemoConversation.messages[1].isFromMe, true);
      expect(DemoConversation.messages[2].isFromMe, false);
    });

    test('messages have content', () {
      for (final msg in DemoConversation.messages) {
        expect(msg.content.isNotEmpty, true);
      }
    });

    test('demoResult has valid enthusiasm', () {
      expect(DemoConversation.demoResult.enthusiasmScore, 72);
      expect(DemoConversation.demoResult.enthusiasmLevel.label, 'hot');
    });

    test('demoResult has all reply types', () {
      final replies = DemoConversation.demoResult.replies;
      expect(replies.containsKey('extend'), true);
      expect(replies.containsKey('resonate'), true);
      expect(replies.containsKey('tease'), true);
      expect(replies.containsKey('humor'), true);
      expect(replies.containsKey('coldRead'), true);
    });

    test('demoResult has valid final recommendation', () {
      final rec = DemoConversation.demoResult.finalRecommendation;
      expect(rec.pick, 'tease');
      expect(rec.content.isNotEmpty, true);
      expect(rec.reason.isNotEmpty, true);
      expect(rec.psychology.isNotEmpty, true);
    });

    test('demoResult has reminder', () {
      expect(DemoConversation.demoResult.reminder.isNotEmpty, true);
    });
  });
}
