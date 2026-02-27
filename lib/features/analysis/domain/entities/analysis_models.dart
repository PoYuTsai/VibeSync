// lib/features/analysis/domain/entities/analysis_models.dart
import 'game_stage.dart';

/// Topic depth levels (話題深度)
enum TopicDepthLevel {
  event,    // 事件層 (表面話題)
  personal, // 個人層 (深入了解)
  intimate, // 曖昧層 (情感連結)
}

extension TopicDepthLevelX on TopicDepthLevel {
  String get label {
    switch (this) {
      case TopicDepthLevel.event:
        return '事件層';
      case TopicDepthLevel.personal:
        return '個人層';
      case TopicDepthLevel.intimate:
        return '曖昧層';
    }
  }

  String get emoji {
    switch (this) {
      case TopicDepthLevel.event:
        return '📰';
      case TopicDepthLevel.personal:
        return '👤';
      case TopicDepthLevel.intimate:
        return '💕';
    }
  }
}

/// Topic depth analysis result
class TopicDepth {
  final TopicDepthLevel current;
  final String suggestion;

  const TopicDepth({
    required this.current,
    required this.suggestion,
  });
}

/// Conversation health check result (對話健檢 - Essential專屬)
class HealthCheck {
  final List<String> issues;
  final List<String> suggestions;
  final bool hasNeedySignals;
  final bool hasInterviewStyle;
  final double? speakingRatio; // 用戶說話比例

  const HealthCheck({
    required this.issues,
    required this.suggestions,
    this.hasNeedySignals = false,
    this.hasInterviewStyle = false,
    this.speakingRatio,
  });
}

/// GAME stage analysis info
class GameStageInfo {
  final GameStage current;
  final GameStageStatus status;
  final String nextStep;

  const GameStageInfo({
    required this.current,
    this.status = GameStageStatus.normal,
    required this.nextStep,
  });
}

/// Psychology analysis (淺溝通解讀)
class PsychologyAnalysis {
  final String subtext;           // 她真正想說的
  final String? shitTest;         // 偵測到的廢測 (null = 無)
  final bool qualificationSignal; // 她是否在向你證明自己

  const PsychologyAnalysis({
    required this.subtext,
    this.shitTest,
    this.qualificationSignal = false,
  });
}

/// Final AI recommendation
class FinalRecommendation {
  final String pick;       // 推薦的回覆類型 (extend/resonate/tease/humor/coldRead)
  final String content;    // 推薦的回覆內容
  final String reason;     // 推薦理由
  final String psychology; // 心理學依據

  const FinalRecommendation({
    required this.pick,
    required this.content,
    required this.reason,
    required this.psychology,
  });
}

/// Complete analysis result from AI
class AnalysisResult {
  final int enthusiasmScore;
  final String strategy;
  final GameStageInfo gameStage;
  final PsychologyAnalysis psychology;
  final TopicDepth topicDepth;
  final HealthCheck? healthCheck; // null for Free users
  final Map<String, String> replies;
  final FinalRecommendation recommendation;
  final String? reminder;
  final bool shouldGiveUp; // 冰點放棄建議

  const AnalysisResult({
    required this.enthusiasmScore,
    required this.strategy,
    required this.gameStage,
    required this.psychology,
    required this.topicDepth,
    this.healthCheck,
    required this.replies,
    required this.recommendation,
    this.reminder,
    this.shouldGiveUp = false,
  });
}
