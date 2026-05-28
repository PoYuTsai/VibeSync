import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vibesync/features/analysis/data/services/analysis_service.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';

Message _msg(String content, {bool fromMe = false}) {
  return Message(
    id: content,
    content: content,
    isFromMe: fromMe,
    timestamp: DateTime(2026, 5, 28, 12, 0, 0),
  );
}

const Map<String, dynamic> _fullSuccessBody = {
  'enthusiasm': {'score': 70, 'level': 'warm'},
  'gameStage': {'current': 'premise', 'status': 'normal', 'nextStep': '繼續'},
  'psychology': {
    'subtext': '有興趣',
    'shitTest': {'detected': false},
    'qualificationSignal': true,
  },
  'topicDepth': {'current': 'personal', 'suggestion': '可深入'},
  'replies': {
    'extend': 'a',
    'resonate': 'b',
    'tease': 'c',
    'humor': 'd',
    'coldRead': 'e',
  },
  'finalRecommendation': {
    'pick': 'tease',
    'content': 'c',
    'reason': 'r',
    'psychology': 'p',
  },
  'warnings': <dynamic>[],
  'strategy': '保持沉穩',
  'reminder': '記得用你的方式說',
};

void main() {
  group('AnalysisService.analyzeQuick', () {
    test('POSTs with responseMode:quick and parses quickResult', () async {
      late http.Request capturedRequest;
      final mockClient = MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          jsonEncode({
            'analysisRunId': 'run_q1',
            'estimatedFullSeconds': 16,
            'quickResult': {
              'nextStep': '先接情緒',
              'recommendedReply': '聽起來累爆，週末放空一下？',
              'shortReason': '接情緒再延伸',
              'insufficientContext': false,
              'confidence': 'high',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = AnalysisService(
        clientFactory: () => mockClient,
        accessTokenProvider: () => 'fake-token',
      );

      final result = await service.analyzeQuick(
        messages: [_msg('在家追劇'), _msg('好放鬆')],
      );

      expect(result.analysisRunId, 'run_q1');
      expect(result.recommendedReply, '聽起來累爆，週末放空一下？');
      expect(result.estimatedFullSeconds, 16);

      final body = jsonDecode(capturedRequest.body) as Map<String, dynamic>;
      expect(body['responseMode'], 'quick');
      expect(body.containsKey('analysisRunId'), isFalse);
      expect(body['messages'], isA<List<dynamic>>());
      expect((body['messages'] as List).length, 2);
    });

    test('throws DailyLimitExceededException on 429 with dailyLimit', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': 'Daily limit exceeded',
            'code': 'DAILY_LIMIT_EXCEEDED',
            'dailyLimit': 15,
            'used': 15,
          }),
          429,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = AnalysisService(
        clientFactory: () => mockClient,
        accessTokenProvider: () => 'fake-token',
      );

      expect(
        () => service.analyzeQuick(messages: [_msg('hi')]),
        throwsA(isA<DailyLimitExceededException>()),
      );
    });

    test('throws AnalysisException with UNAUTHORIZED when token missing',
        () async {
      final mockClient = MockClient((request) async {
        fail('http client should not be called when token is null');
      });
      final service = AnalysisService(
        clientFactory: () => mockClient,
        accessTokenProvider: () => null,
      );

      expect(
        () => service.analyzeQuick(messages: [_msg('hi')]),
        throwsA(
          isA<AnalysisException>().having((e) => e.code, 'code', 'UNAUTHORIZED'),
        ),
      );
    });
  });

  group('AnalysisService.analyzeFull', () {
    test('POSTs with responseMode:full + analysisRunId, parses AnalysisResult',
        () async {
      late http.Request capturedRequest;
      final mockClient = MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          jsonEncode(_fullSuccessBody),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = AnalysisService(
        clientFactory: () => mockClient,
        accessTokenProvider: () => 'fake-token',
      );

      final result = await service.analyzeFull(
        analysisRunId: 'run_q1',
        messages: [_msg('在家追劇')],
      );

      expect(result.strategy, '保持沉穩');

      final body = jsonDecode(capturedRequest.body) as Map<String, dynamic>;
      expect(body['responseMode'], 'full');
      expect(body['analysisRunId'], 'run_q1');
    });

    test('throws FullModeException RUN_EXPIRED on 410', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': 'RUN_EXPIRED',
            'code': 'RUN_EXPIRED',
            'message': 'Run expired',
          }),
          410,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = AnalysisService(
        clientFactory: () => mockClient,
        accessTokenProvider: () => 'fake-token',
      );

      await expectLater(
        () => service.analyzeFull(
          analysisRunId: 'run_expired',
          messages: [_msg('hi')],
        ),
        throwsA(
          isA<FullModeException>()
              .having((e) => e.code, 'code', 'RUN_EXPIRED')
              .having((e) => e.retriesRemaining, 'retriesRemaining', 0),
        ),
      );
    });

    test('throws FullModeException RUN_CONVERSATION_MISMATCH on 409', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': 'RUN_CONVERSATION_MISMATCH',
            'code': 'RUN_CONVERSATION_MISMATCH',
          }),
          409,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = AnalysisService(
        clientFactory: () => mockClient,
        accessTokenProvider: () => 'fake-token',
      );

      await expectLater(
        () => service.analyzeFull(
          analysisRunId: 'r',
          messages: [_msg('hi')],
        ),
        throwsA(
          isA<FullModeException>().having(
              (e) => e.code, 'code', 'RUN_CONVERSATION_MISMATCH'),
        ),
      );
    });

    test('throws FullModeException with retriesRemaining on 502', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': 'FULL_FAILED',
            'code': 'FULL_FAILED',
            'retriesRemaining': 2,
            'message': 'parse failed',
          }),
          502,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = AnalysisService(
        clientFactory: () => mockClient,
        accessTokenProvider: () => 'fake-token',
      );

      await expectLater(
        () => service.analyzeFull(
          analysisRunId: 'r',
          messages: [_msg('hi')],
        ),
        throwsA(
          isA<FullModeException>()
              .having((e) => e.code, 'code', 'FULL_FAILED')
              .having((e) => e.retriesRemaining, 'retriesRemaining', 2),
        ),
      );
    });

    test('throws FullModeException RUN_RETRY_EXHAUSTED on 429 with 0 left',
        () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': 'RUN_RETRY_EXHAUSTED',
            'code': 'RUN_RETRY_EXHAUSTED',
            'retriesRemaining': 0,
          }),
          429,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = AnalysisService(
        clientFactory: () => mockClient,
        accessTokenProvider: () => 'fake-token',
      );

      await expectLater(
        () => service.analyzeFull(
          analysisRunId: 'r',
          messages: [_msg('hi')],
        ),
        throwsA(
          isA<FullModeException>()
              .having((e) => e.code, 'code', 'RUN_RETRY_EXHAUSTED')
              .having((e) => e.retriesRemaining, 'retriesRemaining', 0),
        ),
      );
    });
  });
}
