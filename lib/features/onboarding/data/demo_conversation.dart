// lib/features/onboarding/data/demo_conversation.dart
import '../../conversation/domain/entities/message.dart';
import '../../analysis/domain/entities/analysis_result.dart';
import '../../analysis/domain/entities/game_stage.dart';
import '../../analysis/domain/entities/enthusiasm_level.dart';

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

  // 預設結果 (不呼叫 API)
  static final demoResult = AnalysisResult(
    gameStage: GameStage.premise,
    gameStatus: GameStageStatus.canAdvance,
    gameNextStep: '可以推進到評估階段',
    enthusiasmScore: 72,
    enthusiasmLevel: EnthusiasmLevel.hot,
    topicDepthCurrent: 'personal',
    topicDepthSuggestion: '可以往曖昧導向推進',
    psychology: PsychologyAnalysis(
      subtext: '她主動分享代表對你有興趣，這是好的訊號',
      shitTestDetected: false,
      qualificationSignal: true,
    ),
    replies: {
      'extend': '抹茶山不錯欸，你喜歡哪種路線？',
      'resonate': '抹茶山超讚！雲海那段是不是很美',
      'tease': '聽起來你很會挑地方嘛，改天帶路？',
      'humor': '抹茶山...所以你是抹茶控？',
      'coldRead': '感覺你是那種週末不會待在家的人',
    },
    finalRecommendation: FinalRecommendation(
      pick: 'tease',
      content: '聽起來你很會挑地方嘛，改天帶路？',
      reason: '熱度足夠，用調情建立張力並埋下邀約伏筆',
      psychology: '她主動分享代表對你有興趣，適時推進可以加深關係',
    ),
    warnings: [],
    strategy: '保持輕鬆，適時推進',
    reminder: '記得用你的方式說，見面才自然',
  );
}
