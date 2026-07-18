import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vibesync/features/analysis/data/services/analysis_service.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';

Message _msg(String content) {
  return Message(
    id: content,
    content: content,
    isFromMe: false,
    timestamp: DateTime(2026, 7, 3, 12, 0, 0),
  );
}

// analyze 模型呼叫限流 429 的 client 側契約
// （docs/plans/2026-07-03-model-rate-limit-design.md）。
//
// server 對 analyze 入口新增 6/分、60/天限流，429 帶 code: MODEL_RATE_LIMITED
// 且**不帶** monthlyLimit/dailyLimit 鍵——client 必須：
//   1. 不落 Monthly/DailyLimitExceededException（那會誤導升級 paywall CTA）
//   2. 映射成 wait 動作＋優先顯示 server 文案
//   3. 不自動重試（重試只會繼續 429，養出 retry storm）

AnalysisService _service(MockClient client) {
  return AnalysisService(
    clientFactory: () => client,
    accessTokenProvider: () => 'fake-token',
    expectedTierProvider: () => null,
    revenueCatAppUserIdProvider: () async => null,
  );
}

Map<String, dynamic> _modelRateLimitedBody({required String message}) {
  return {
    'error': 'Model rate limited',
    'code': 'MODEL_RATE_LIMITED',
    'message': message,
    'retryable': false,
  };
}

void main() {
  group('analyze 429 MODEL_RATE_LIMITED mapping', () {
    test('maps to wait action with server message, single request (no retry)',
        () async {
      var requestCount = 0;
      final mockClient = MockClient((request) async {
        requestCount++;
        return http.Response(
          jsonEncode(
            _modelRateLimitedBody(message: '操作太頻繁，請稍等一分鐘再試。'),
          ),
          429,
          headers: {'content-type': 'application/json'},
        );
      });

      AnalysisException? caught;
      try {
        await _service(mockClient).analyzeConversation([_msg('她已讀不回')]);
        fail('expected AnalysisException');
      } on AnalysisException catch (error) {
        caught = error;
      }

      expect(caught.code, 'MODEL_RATE_LIMITED');
      expect(caught.suggestedAction, AnalysisErrorAction.wait);
      expect(caught.message, '操作太頻繁，請稍等一分鐘再試。');
      expect(requestCount, 1);
    });

    test('does NOT become Monthly/DailyLimitExceededException', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode(
            _modelRateLimitedBody(message: '今日使用次數已達上限，明天早上 8 點恢復。'),
          ),
          429,
          headers: {'content-type': 'application/json'},
        );
      });

      Object? caught;
      try {
        await _service(mockClient).analyzeConversation([_msg('她已讀不回')]);
        fail('expected AnalysisException');
      } catch (error) {
        caught = error;
      }

      expect(caught, isNot(isA<MonthlyLimitExceededException>()));
      expect(caught, isNot(isA<DailyLimitExceededException>()));
      expect(caught, isA<AnalysisException>());
    });

    test('MODEL_RATE_LIMITED is not auto-retriable', () {
      expect(
        AnalysisService.isAutoRetriableAnalysisError(
          code: 'MODEL_RATE_LIMITED',
          hasImages: false,
          recognizeOnly: false,
          hasDurableRequestId: false,
        ),
        isFalse,
      );
    });
  });
}
