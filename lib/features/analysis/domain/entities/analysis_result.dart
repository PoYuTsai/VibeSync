// lib/features/analysis/domain/entities/analysis_result.dart
import 'game_stage.dart';
import 'enthusiasm_level.dart';

/// 心理分析結果
class PsychologyAnalysis {
  final String subtext; // 淺溝通解讀
  final bool shitTestDetected; // 是否偵測到廢測
  final String? shitTestType; // 廢測類型
  final String? shitTestSuggestion;
  final bool qualificationSignal; // 她有在證明自己

  PsychologyAnalysis({
    required this.subtext,
    this.shitTestDetected = false,
    this.shitTestType,
    this.shitTestSuggestion,
    this.qualificationSignal = false,
  });

  factory PsychologyAnalysis.fromJson(Map<String, dynamic> json) {
    final shitTest = json['shitTest'] as Map<String, dynamic>?;
    return PsychologyAnalysis(
      subtext: json['subtext'] ?? '',
      shitTestDetected: shitTest?['detected'] ?? false,
      shitTestType: shitTest?['type'],
      shitTestSuggestion: shitTest?['suggestion'],
      qualificationSignal: json['qualificationSignal'] ?? false,
    );
  }
}

/// AI 最終建議
class FinalRecommendation {
  final String pick; // 選哪個回覆類型
  final String content; // 推薦的回覆內容
  final String reason; // 為什麼推薦這個
  final String psychology; // 心理學依據

  FinalRecommendation({
    required this.pick,
    required this.content,
    required this.reason,
    required this.psychology,
  });

  factory FinalRecommendation.fromJson(Map<String, dynamic> json) {
    return FinalRecommendation(
      pick: json['pick'] ?? '',
      content: json['content'] ?? '',
      reason: json['reason'] ?? '',
      psychology: json['psychology'] ?? '',
    );
  }
}

/// 完整分析結果
class AnalysisResult {
  // GAME 階段
  final GameStage gameStage;
  final GameStageStatus gameStatus;
  final String gameNextStep;

  // 熱度
  final int enthusiasmScore;
  final EnthusiasmLevel enthusiasmLevel;

  // 話題深度
  final String topicDepthCurrent;
  final String topicDepthSuggestion;

  // 心理分析
  final PsychologyAnalysis psychology;

  // 5 種回覆
  final Map<String, String> replies;

  // 最終建議
  final FinalRecommendation finalRecommendation;

  // 警告
  final List<String> warnings;

  // 健檢 (Essential)
  final List<String>? healthCheckIssues;
  final List<String>? healthCheckSuggestions;

  // 策略提示
  final String strategy;

  // 提醒
  final String reminder;

  AnalysisResult({
    required this.gameStage,
    required this.gameStatus,
    required this.gameNextStep,
    required this.enthusiasmScore,
    required this.enthusiasmLevel,
    required this.topicDepthCurrent,
    required this.topicDepthSuggestion,
    required this.psychology,
    required this.replies,
    required this.finalRecommendation,
    required this.warnings,
    this.healthCheckIssues,
    this.healthCheckSuggestions,
    required this.strategy,
    this.reminder = '記得用你的方式說，見面才自然',
  });

  factory AnalysisResult.fromJson(Map<String, dynamic> json) {
    final gameStageJson = json['gameStage'] as Map<String, dynamic>;
    final enthusiasmJson = json['enthusiasm'] as Map<String, dynamic>;
    final topicDepthJson = json['topicDepth'] as Map<String, dynamic>;
    final healthCheck = json['healthCheck'] as Map<String, dynamic>?;

    return AnalysisResult(
      gameStage: GameStage.values.firstWhere(
        (e) => e.name == gameStageJson['current'],
        orElse: () => GameStage.opening,
      ),
      gameStatus: GameStageStatus.values.firstWhere(
        (e) => e.label == gameStageJson['status'],
        orElse: () => GameStageStatus.normal,
      ),
      gameNextStep: gameStageJson['nextStep'] ?? '',
      enthusiasmScore: enthusiasmJson['score'] ?? 50,
      enthusiasmLevel:
          EnthusiasmLevel.fromScore(enthusiasmJson['score'] ?? 50),
      topicDepthCurrent: topicDepthJson['current'] ?? 'facts',
      topicDepthSuggestion: topicDepthJson['suggestion'] ?? '',
      psychology: PsychologyAnalysis.fromJson(json['psychology'] ?? {}),
      replies: Map<String, String>.from(json['replies'] ?? {}),
      finalRecommendation: FinalRecommendation.fromJson(
        json['finalRecommendation'] ?? {},
      ),
      warnings: List<String>.from(json['warnings'] ?? []),
      healthCheckIssues: healthCheck != null
          ? List<String>.from(healthCheck['issues'] ?? [])
          : null,
      healthCheckSuggestions: healthCheck != null
          ? List<String>.from(healthCheck['suggestions'] ?? [])
          : null,
      strategy: json['strategy'] ?? '',
      reminder: json['reminder'] ?? '記得用你的方式說，見面才自然',
    );
  }
}
