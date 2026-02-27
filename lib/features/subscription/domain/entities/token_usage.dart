// lib/features/subscription/domain/entities/token_usage.dart

class TokenUsage {
  final String id;
  final String userId;
  final String model;
  final int inputTokens;
  final int outputTokens;
  final int totalTokens;
  final double costUsd;
  final String? conversationId;
  final DateTime createdAt;

  const TokenUsage({
    required this.id,
    required this.userId,
    required this.model,
    required this.inputTokens,
    required this.outputTokens,
    required this.totalTokens,
    required this.costUsd,
    this.conversationId,
    required this.createdAt,
  });

  factory TokenUsage.fromJson(Map<String, dynamic> json) {
    return TokenUsage(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      model: json['model'] as String,
      inputTokens: json['input_tokens'] as int,
      outputTokens: json['output_tokens'] as int,
      totalTokens: json['total_tokens'] as int,
      costUsd: (json['cost_usd'] as num).toDouble(),
      conversationId: json['conversation_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'model': model,
        'input_tokens': inputTokens,
        'output_tokens': outputTokens,
        'total_tokens': totalTokens,
        'cost_usd': costUsd,
        'conversation_id': conversationId,
        'created_at': createdAt.toIso8601String(),
      };
}

class MonthlyTokenSummary {
  final String userId;
  final DateTime month;
  final int totalInputTokens;
  final int totalOutputTokens;
  final int totalTokens;
  final double totalCostUsd;
  final int requestCount;

  const MonthlyTokenSummary({
    required this.userId,
    required this.month,
    required this.totalInputTokens,
    required this.totalOutputTokens,
    required this.totalTokens,
    required this.totalCostUsd,
    required this.requestCount,
  });

  factory MonthlyTokenSummary.fromJson(Map<String, dynamic> json) {
    return MonthlyTokenSummary(
      userId: json['user_id'] as String,
      month: DateTime.parse(json['month'] as String),
      totalInputTokens: json['total_input_tokens'] as int,
      totalOutputTokens: json['total_output_tokens'] as int,
      totalTokens: json['total_tokens'] as int,
      totalCostUsd: (json['total_cost_usd'] as num).toDouble(),
      requestCount: json['request_count'] as int,
    );
  }

  double get averageTokensPerRequest =>
      requestCount > 0 ? totalTokens / requestCount : 0;
}

class ConversationCostSummary {
  final String userId;
  final String conversationId;
  final int analysisCount;
  final int totalInputTokens;
  final int totalOutputTokens;
  final int totalTokens;
  final double totalCostUsd;
  final DateTime firstAnalysis;
  final DateTime lastAnalysis;

  const ConversationCostSummary({
    required this.userId,
    required this.conversationId,
    required this.analysisCount,
    required this.totalInputTokens,
    required this.totalOutputTokens,
    required this.totalTokens,
    required this.totalCostUsd,
    required this.firstAnalysis,
    required this.lastAnalysis,
  });

  factory ConversationCostSummary.fromJson(Map<String, dynamic> json) {
    return ConversationCostSummary(
      userId: json['user_id'] as String,
      conversationId: json['conversation_id'] as String,
      analysisCount: json['analysis_count'] as int,
      totalInputTokens: json['total_input_tokens'] as int,
      totalOutputTokens: json['total_output_tokens'] as int,
      totalTokens: json['total_tokens'] as int,
      totalCostUsd: (json['total_cost_usd'] as num).toDouble(),
      firstAnalysis: DateTime.parse(json['first_analysis'] as String),
      lastAnalysis: DateTime.parse(json['last_analysis'] as String),
    );
  }

  double get averageCostPerAnalysis =>
      analysisCount > 0 ? totalCostUsd / analysisCount : 0;
}
