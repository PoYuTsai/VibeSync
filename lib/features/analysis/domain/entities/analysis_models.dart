// lib/features/analysis/domain/entities/analysis_models.dart
import 'game_stage.dart';

/// Topic depth levels (話題深度)
enum TopicDepthLevel {
  event,    // 事件層 (表面話題)
  personal, // 個人層 (深入了解)
  intimate, // 曖昧層 (情感連結)
}

extension TopicDepthLevelX on TopicDepthLevel {
  static TopicDepthLevel fromString(String value) {
    switch (value.toLowerCase()) {
      case 'facts':
      case 'event':
        return TopicDepthLevel.event;
      case 'personal':
        return TopicDepthLevel.personal;
      case 'intimate':
        return TopicDepthLevel.intimate;
      default:
        return TopicDepthLevel.event;
    }
  }

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

  factory TopicDepth.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const TopicDepth(current: TopicDepthLevel.event, suggestion: '');
    }
    return TopicDepth(
      current: TopicDepthLevelX.fromString(json['current'] as String? ?? 'event'),
      suggestion: json['suggestion'] as String? ?? '',
    );
  }
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

  factory HealthCheck.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const HealthCheck(issues: [], suggestions: []);
    }
    return HealthCheck(
      issues: (json['issues'] as List?)?.cast<String>() ?? [],
      suggestions: (json['suggestions'] as List?)?.cast<String>() ?? [],
      hasNeedySignals: json['hasNeedySignals'] as bool? ?? false,
      hasInterviewStyle: json['hasInterviewStyle'] as bool? ?? false,
      speakingRatio: (json['speakingRatio'] as num?)?.toDouble(),
    );
  }
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

  factory GameStageInfo.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const GameStageInfo(current: GameStage.opening, nextStep: '');
    }
    return GameStageInfo(
      current: GameStage.fromString(json['current'] as String? ?? 'opening'),
      status: GameStageStatus.fromString(json['status'] as String? ?? 'normal'),
      nextStep: json['nextStep'] as String? ?? '',
    );
  }
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

  factory PsychologyAnalysis.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const PsychologyAnalysis(subtext: '');
    }
    // Parse nested shitTest object if present
    final shitTestData = json['shitTest'] as Map<String, dynamic>?;
    String? shitTestSuggestion;
    if (shitTestData != null && shitTestData['detected'] == true) {
      shitTestSuggestion = shitTestData['suggestion'] as String?;
    }
    return PsychologyAnalysis(
      subtext: json['subtext'] as String? ?? '',
      shitTest: shitTestSuggestion,
      qualificationSignal: json['qualificationSignal'] as bool? ?? false,
    );
  }
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

  factory FinalRecommendation.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const FinalRecommendation(
        pick: 'extend',
        content: '',
        reason: '',
        psychology: '',
      );
    }
    return FinalRecommendation(
      pick: json['pick'] as String? ?? 'extend',
      content: json['content'] as String? ?? '',
      reason: json['reason'] as String? ?? '',
      psychology: json['psychology'] as String? ?? '',
    );
  }
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

  factory AnalysisResult.fromJson(Map<String, dynamic> json) {
    final enthusiasm = json['enthusiasm'] as Map<String, dynamic>?;
    final repliesData = json['replies'] as Map<String, dynamic>?;

    // Parse healthCheck only if present (Essential tier only)
    HealthCheck? healthCheck;
    if (json['healthCheck'] != null) {
      healthCheck = HealthCheck.fromJson(json['healthCheck'] as Map<String, dynamic>?);
    }

    // Determine if should give up (cold enthusiasm + specific signals)
    final enthusiasmLevel = enthusiasm?['level'] as String?;
    final warnings = (json['warnings'] as List?)?.cast<String>() ?? [];
    final shouldGiveUp = enthusiasmLevel == 'cold' &&
        (warnings.contains('建議放棄') || warnings.contains('開新對話'));

    return AnalysisResult(
      enthusiasmScore: enthusiasm?['score'] as int? ?? 50,
      strategy: json['strategy'] as String? ?? '',
      gameStage: GameStageInfo.fromJson(json['gameStage'] as Map<String, dynamic>?),
      psychology: PsychologyAnalysis.fromJson(json['psychology'] as Map<String, dynamic>?),
      topicDepth: TopicDepth.fromJson(json['topicDepth'] as Map<String, dynamic>?),
      healthCheck: healthCheck,
      replies: repliesData?.map((k, v) => MapEntry(k, v.toString())) ?? {},
      recommendation: FinalRecommendation.fromJson(json['finalRecommendation'] as Map<String, dynamic>?),
      reminder: json['reminder'] as String?,
      shouldGiveUp: shouldGiveUp,
    );
  }
}
