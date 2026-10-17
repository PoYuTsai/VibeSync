// lib/features/onboarding/data/demo_conversation.dart
import '../../conversation/domain/entities/message.dart';
import '../../analysis/domain/entities/guide_v3_result.dart';

class DemoConversation {
  static const name = '範例對話';

  static final messages = [
    Message(
      id: 'demo_1',
      content: '欸你週末都在幹嘛',
      isFromMe: false,
      timestamp: DateTime.now().subtract(const Duration(hours: 2)),
    ),
    Message(
      id: 'demo_2',
      content: '看情況欸 有時候爬山有時候耍廢',
      isFromMe: true,
      timestamp: DateTime.now().subtract(const Duration(hours: 1, minutes: 50)),
    ),
    Message(
      id: 'demo_3',
      content: '哇塞你也爬山！我最近去了抹茶山超美',
      isFromMe: false,
      timestamp: DateTime.now().subtract(const Duration(hours: 1, minutes: 45)),
    ),
  ];

  // 預設結果（不呼叫 API）：對話分析 v3 的燈號、局面判讀與任務卡
  // （Eric 2026-10-17：新流程不留熱度、階段、雷達，每次 3–5 張回覆依局面搭配）。
  static const demoLight = GuideV3Light.green;

  static const demoJudgment = '她不只回答，還主動分享剛去的抹茶山，是往前的訊號。'
      '接住她的分享，也可以順勢約她。';

  static const demoCards = [
    (task: GuideV3Task.accept, text: '抹茶山那段稜線真的很美，你是挑晴天去的吧？'),
    (task: GuideV3Task.resonate, text: '我也喜歡爬到一半，雲海突然整片出現的那種感覺'),
    (task: GuideV3Task.push, text: '這週六要不要一起去爬？我帶你走一條人比較少的路線'),
  ];
}
