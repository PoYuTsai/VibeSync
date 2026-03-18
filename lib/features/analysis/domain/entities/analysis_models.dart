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

/// 「我說」話題延續分析結果
class MyMessageAnalysis {
  final String sentMessage;
  final ResponsePrediction ifColdResponse;
  final ResponsePrediction ifWarmResponse;
  final List<String> backupTopics;
  final List<String> warnings;

  const MyMessageAnalysis({
    required this.sentMessage,
    required this.ifColdResponse,
    required this.ifWarmResponse,
    required this.backupTopics,
    required this.warnings,
  });

  factory MyMessageAnalysis.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return MyMessageAnalysis(
        sentMessage: '',
        ifColdResponse: ResponsePrediction.empty(),
        ifWarmResponse: ResponsePrediction.empty(),
        backupTopics: [],
        warnings: [],
      );
    }
    return MyMessageAnalysis(
      sentMessage: json['sentMessage'] as String? ?? '',
      ifColdResponse: ResponsePrediction.fromJson(json['ifColdResponse'] as Map<String, dynamic>?),
      ifWarmResponse: ResponsePrediction.fromJson(json['ifWarmResponse'] as Map<String, dynamic>?),
      backupTopics: (json['backupTopics'] as List?)?.cast<String>() ?? [],
      warnings: (json['warnings'] as List?)?.cast<String>() ?? [],
    );
  }
}

/// 回覆預測
class ResponsePrediction {
  final String prediction;
  final String suggestion;

  const ResponsePrediction({
    required this.prediction,
    required this.suggestion,
  });

  factory ResponsePrediction.empty() => const ResponsePrediction(prediction: '', suggestion: '');

  factory ResponsePrediction.fromJson(Map<String, dynamic>? json) {
    if (json == null) return ResponsePrediction.empty();
    return ResponsePrediction(
      prediction: json['prediction'] as String? ?? '',
      suggestion: json['suggestion'] as String? ?? '',
    );
  }
}

/// 截圖識別結果中的單則訊息
class RecognizedMessage {
  final bool isFromMe;
  final String content;

  const RecognizedMessage({
    required this.isFromMe,
    required this.content,
  });

  factory RecognizedMessage.fromJson(Map<String, dynamic> json) {
    return RecognizedMessage(
      isFromMe: json['isFromMe'] as bool? ?? false,
      content: json['content'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'isFromMe': isFromMe,
        'content': content,
      };

  RecognizedMessage copyWith({
    bool? isFromMe,
    String? content,
  }) {
    return RecognizedMessage(
      isFromMe: isFromMe ?? this.isFromMe,
      content: content ?? this.content,
    );
  }
}

/// 截圖識別結果
class RecognizedConversation {
  final String? contactName; // 從截圖標題識別的對方名字
  final int messageCount;
  final String summary;
  final List<RecognizedMessage>? messages;
  final String classification;
  final String importPolicy;
  final String confidence;
  final String? warning;

  const RecognizedConversation({
    this.contactName,
    required this.messageCount,
    required this.summary,
    this.messages,
    this.classification = 'valid_chat',
    this.importPolicy = 'allow',
    this.confidence = 'high',
    this.warning,
  });

  factory RecognizedConversation.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const RecognizedConversation(messageCount: 0, summary: '');
    }
    return RecognizedConversation(
      contactName: json['contactName'] as String?,
      messageCount: json['messageCount'] as int? ?? 0,
      summary: json['summary'] as String? ?? '',
      messages: json['messages'] != null
          ? (json['messages'] as List)
              .map((m) => RecognizedMessage.fromJson(m as Map<String, dynamic>))
              .toList()
          : null,
      classification: json['classification'] as String? ?? 'valid_chat',
      importPolicy: json['importPolicy'] as String? ?? 'allow',
      confidence: json['confidence'] as String? ?? 'high',
      warning: json['warning'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'contactName': contactName,
        'messageCount': messageCount,
        'summary': summary,
        'messages': messages?.map((message) => message.toJson()).toList(),
        'classification': classification,
        'importPolicy': importPolicy,
        'confidence': confidence,
        'warning': warning,
      };

  RecognizedConversation copyWith({
    String? contactName,
    int? messageCount,
    String? summary,
    List<RecognizedMessage>? messages,
    String? classification,
    String? importPolicy,
    String? confidence,
    String? warning,
  }) {
    return RecognizedConversation(
      contactName: contactName ?? this.contactName,
      messageCount: messageCount ?? this.messageCount,
      summary: summary ?? this.summary,
      messages: messages ?? this.messages,
      classification: classification ?? this.classification,
      importPolicy: importPolicy ?? this.importPolicy,
      confidence: confidence ?? this.confidence,
      warning: warning ?? this.warning,
    );
  }
}

/// Optimized user message result
class OptimizedMessage {
  final String original;   // 用戶原本的訊息
  final String optimized;  // AI 優化後的訊息
  final String reason;     // 優化理由

  const OptimizedMessage({
    required this.original,
    required this.optimized,
    required this.reason,
  });

  factory OptimizedMessage.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const OptimizedMessage(original: '', optimized: '', reason: '');
    return OptimizedMessage(
      original: json['original'] as String? ?? '',
      optimized: json['optimized'] as String? ?? '',
      reason: json['reason'] as String? ?? '',
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
  final Map<String, dynamic>? rawResponse; // 原始 AI 回應 (用於反饋)
  final OptimizedMessage? optimizedMessage; // 用戶訊息優化結果
  final MyMessageAnalysis? myMessageAnalysis; // 「我說」話題延續分析
  final RecognizedConversation? recognizedConversation; // 截圖識別結果
  final int? imagesUsed; // 使用的截圖數量

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
    this.rawResponse,
    this.optimizedMessage,
    this.myMessageAnalysis,
    this.recognizedConversation,
    this.imagesUsed,
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
    // warnings 可能是 String 或 Object 陣列，安全處理
    final rawWarnings = json['warnings'] as List? ?? [];
    final warnings = rawWarnings.map((w) => w is String ? w : w.toString()).toList();
    final shouldGiveUp = enthusiasmLevel == 'cold' &&
        (warnings.any((w) => w.contains('建議放棄') || w.contains('開新對話')));

    // Parse optimizedMessage if present (when user provided draft)
    OptimizedMessage? optimizedMessage;
    if (json['optimizedMessage'] != null) {
      optimizedMessage = OptimizedMessage.fromJson(json['optimizedMessage'] as Map<String, dynamic>?);
    }

    // Parse myMessageAnalysis if present (「我說」模式)
    MyMessageAnalysis? myMessageAnalysis;
    if (json['myMessageAnalysis'] != null) {
      myMessageAnalysis = MyMessageAnalysis.fromJson(json['myMessageAnalysis'] as Map<String, dynamic>?);
    }

    // Parse recognizedConversation if present (截圖識別結果)
    RecognizedConversation? recognizedConversation;
    if (json['recognizedConversation'] != null) {
      recognizedConversation = RecognizedConversation.fromJson(json['recognizedConversation'] as Map<String, dynamic>?);
    }

    // Parse imagesUsed from usage
    final usage = json['usage'] as Map<String, dynamic>?;
    final imagesUsed = usage?['imagesUsed'] as int?;

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
      rawResponse: json, // 保存原始回應
      optimizedMessage: optimizedMessage,
      myMessageAnalysis: myMessageAnalysis,
      recognizedConversation: recognizedConversation,
      imagesUsed: imagesUsed,
    );
  }
}
