// test/unit/token_usage_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/subscription/domain/entities/token_usage.dart';

void main() {
  group('TokenUsage', () {
    test('fromJson parses correctly', () {
      final json = {
        'id': 'test-id',
        'user_id': 'user-123',
        'model': 'claude-3-5-haiku-20241022',
        'input_tokens': 100,
        'output_tokens': 200,
        'total_tokens': 300,
        'cost_usd': 0.001,
        'conversation_id': 'conv-456',
        'created_at': '2026-02-27T10:00:00Z',
      };

      final usage = TokenUsage.fromJson(json);

      expect(usage.id, 'test-id');
      expect(usage.userId, 'user-123');
      expect(usage.model, 'claude-3-5-haiku-20241022');
      expect(usage.inputTokens, 100);
      expect(usage.outputTokens, 200);
      expect(usage.totalTokens, 300);
      expect(usage.costUsd, 0.001);
      expect(usage.conversationId, 'conv-456');
    });

    test('toJson serializes correctly', () {
      final usage = TokenUsage(
        id: 'test-id',
        userId: 'user-123',
        model: 'claude-sonnet-4-20250514',
        inputTokens: 500,
        outputTokens: 1000,
        totalTokens: 1500,
        costUsd: 0.0165,
        conversationId: null,
        createdAt: DateTime.utc(2026, 2, 27),
      );

      final json = usage.toJson();

      expect(json['model'], 'claude-sonnet-4-20250514');
      expect(json['input_tokens'], 500);
      expect(json['output_tokens'], 1000);
      expect(json['conversation_id'], isNull);
    });
  });

  group('MonthlyTokenSummary', () {
    test('fromJson parses correctly', () {
      final json = {
        'user_id': 'user-123',
        'month': '2026-02-01T00:00:00Z',
        'total_input_tokens': 10000,
        'total_output_tokens': 20000,
        'total_tokens': 30000,
        'total_cost_usd': 0.5,
        'request_count': 50,
      };

      final summary = MonthlyTokenSummary.fromJson(json);

      expect(summary.totalTokens, 30000);
      expect(summary.requestCount, 50);
      expect(summary.averageTokensPerRequest, 600);
    });

    test('averageTokensPerRequest handles zero requests', () {
      final json = {
        'user_id': 'user-123',
        'month': '2026-02-01T00:00:00Z',
        'total_input_tokens': 0,
        'total_output_tokens': 0,
        'total_tokens': 0,
        'total_cost_usd': 0.0,
        'request_count': 0,
      };

      final summary = MonthlyTokenSummary.fromJson(json);

      expect(summary.averageTokensPerRequest, 0);
    });
  });

  group('ConversationCostSummary', () {
    test('fromJson parses correctly', () {
      final json = {
        'user_id': 'user-123',
        'conversation_id': 'conv-456',
        'analysis_count': 10,
        'total_input_tokens': 5000,
        'total_output_tokens': 10000,
        'total_tokens': 15000,
        'total_cost_usd': 0.25,
        'first_analysis': '2026-02-20T10:00:00Z',
        'last_analysis': '2026-02-27T15:00:00Z',
      };

      final summary = ConversationCostSummary.fromJson(json);

      expect(summary.conversationId, 'conv-456');
      expect(summary.analysisCount, 10);
      expect(summary.averageCostPerAnalysis, 0.025);
    });

    test('averageCostPerAnalysis handles zero analyses', () {
      final json = {
        'user_id': 'user-123',
        'conversation_id': 'conv-456',
        'analysis_count': 0,
        'total_input_tokens': 0,
        'total_output_tokens': 0,
        'total_tokens': 0,
        'total_cost_usd': 0.0,
        'first_analysis': '2026-02-27T10:00:00Z',
        'last_analysis': '2026-02-27T10:00:00Z',
      };

      final summary = ConversationCostSummary.fromJson(json);

      expect(summary.averageCostPerAnalysis, 0);
    });
  });
}
