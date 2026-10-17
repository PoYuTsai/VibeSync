// test/unit/onboarding_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/entities/guide_v3_result.dart';
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

    // 對話分析 v3（Eric 2026-10-17）：示範是燈號＋局面判讀＋任務卡，
    // 沒有熱度、階段、雷達，也不再是五種風格。
    test('demo shows a green light with a judgment', () {
      expect(DemoConversation.demoLight, GuideV3Light.green);
      expect(DemoConversation.demoJudgment.isNotEmpty, true);
    });

    test('demo has three task cards in order', () {
      expect(
        DemoConversation.demoCards.map((c) => c.task).toList(),
        [GuideV3Task.accept, GuideV3Task.resonate, GuideV3Task.push],
      );
      for (final card in DemoConversation.demoCards) {
        expect(card.text.isNotEmpty, true);
        expect(guideV3TextHasBlank(card.text), false);
      }
    });
  });
}
