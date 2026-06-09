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
        expectedTierProvider: () => 'essential',
        revenueCatAppUserIdProvider: () async => r'$RCAnonymousID:abc',
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
      expect(body['expectedTier'], 'essential');
      expect(body['revenueCatAppUserId'], r'$RCAnonymousID:abc');
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
        expectedTierProvider: () => 'starter',
        revenueCatAppUserIdProvider: () async => r'$RCAnonymousID:def',
      );

      expect(
        () => service.analyzeQuick(messages: [_msg('hi')]),
        throwsA(
          isA<DailyLimitExceededException>()
              .having((e) => e.code, 'code', 'DAILY_LIMIT_EXCEEDED')
              .having((e) => e.message, 'message', contains('今日免費額度已用完'))
              .having((e) => e.message, 'message', isNot(contains('Daily'))),
        ),
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
          isA<AnalysisException>()
              .having((e) => e.code, 'code', 'UNAUTHORIZED'),
        ),
      );
    });
  });

  group('AnalysisService.analyzeFull', () {
    test(
        'POSTs with responseMode:full + analysisRunId, unwraps server envelope result',
        () async {
      late http.Request capturedRequest;
      final mockClient = MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          jsonEncode({
            'responseMode': 'full',
            'analysisRunId': 'run_q1',
            'quickResult': {
              'nextStep': '???',
              'recommendedReply': '?質絲靘敞???望?曄征銝銝?',
              'shortReason': '?交?蝺?撱嗡撓',
              'insufficientContext': false,
              'confidence': 'high',
            },
            'result': _fullSuccessBody,
            'retriesRemaining': 2,
            'telemetry': {'serverAiLatencyMs': 1234},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = AnalysisService(
        clientFactory: () => mockClient,
        accessTokenProvider: () => 'fake-token',
        expectedTierProvider: () => 'starter',
        revenueCatAppUserIdProvider: () async => r'$RCAnonymousID:def',
      );

      final result = await service.analyzeFull(
        analysisRunId: 'run_q1',
        messages: [_msg('在家追劇')],
      );

      expect(result.strategy, '保持沉穩');

      expect(result.replies['tease'], 'c');
      expect(result.recommendation.content, 'c');

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
          isA<FullModeException>()
              .having((e) => e.code, 'code', 'RUN_CONVERSATION_MISMATCH'),
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

    test('throws AnalysisException INVALID_FULL_RESPONSE on malformed envelope',
        () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'responseMode': 'full',
            'analysisRunId': 'run_q1',
            'quickResult': {
              'nextStep': '??????',
              'recommendedReply': '?鞈芰結????????秣??????',
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

      await expectLater(
        () => service.analyzeFull(
          analysisRunId: 'run_q1',
          messages: [_msg('hi')],
        ),
        throwsA(
          isA<AnalysisException>()
              .having((e) => e.code, 'code', 'INVALID_FULL_RESPONSE')
              .having(
                (e) => e.suggestedAction,
                'suggestedAction',
                AnalysisErrorAction.retry,
              ),
        ),
      );
    });
  });

  group('AnalysisService.analyzeStream', () {
    test('POSTs responseMode:stream and parses NDJSON updates', () async {
      late http.Request capturedRequest;
      final mockClient = MockClient((request) async {
        capturedRequest = request;
        return http.Response.bytes(
          utf8.encode(
            [
              jsonEncode({
                'type': 'analysis.started',
                'runId': 'stream_1',
                'etaSeconds': 18,
                'label': 'start',
              }),
              jsonEncode({
                'type': 'analysis.progress',
                'label': 'reading',
                'detail': 'checking context',
              }),
              jsonEncode({
                'type': 'analysis.decision',
                'nextStepTitle': 'Next move',
                'nextStepBody': 'Acknowledge first, then slow the pace.',
                'doThis': 'Send one grounded reply.',
                'avoidThis': 'Do not over-explain.',
              }),
              jsonEncode({
                'type': 'analysis.report_section',
                'section': 'strategy',
                'content': 'Back off and rebuild trust.',
              }),
              jsonEncode({
                'type': 'analysis.recommendation',
                'selectedStyle': 'resonate',
                'message': 'I get why that felt off.',
                'reason': 'Respect the boundary.',
                'quotedContext': 'too fast',
              }),
              jsonEncode({
                'type': 'analysis.done',
                'finalResult': _fullSuccessBody,
              }),
            ].join('\n'),
          ),
          200,
          headers: {'content-type': 'application/x-ndjson'},
        );
      });

      final service = AnalysisService(
        clientFactory: () => mockClient,
        accessTokenProvider: () => 'fake-token',
        expectedTierProvider: () => 'starter',
        revenueCatAppUserIdProvider: () async => r'$RCAnonymousID:def',
      );

      final updates = await service.analyzeStream(
        messages: [_msg('hi')],
      ).toList();

      expect(updates.map((u) => u.kind).toList(), [
        AnalysisStreamUpdateKind.started,
        AnalysisStreamUpdateKind.progress,
        AnalysisStreamUpdateKind.content,
        AnalysisStreamUpdateKind.content,
        AnalysisStreamUpdateKind.recommendation,
        AnalysisStreamUpdateKind.done,
      ]);
      expect(updates[0].runId, 'stream_1');
      expect(updates[0].etaSeconds, 18);
      expect(updates[1].label, 'reading');
      expect(updates[2].content?.title, 'Next move');
      expect(
        updates[2].content?.body,
        contains('Acknowledge first, then slow the pace.'),
      );
      expect(updates[3].content?.title, '深度策略');
      expect(updates[3].content?.body, 'Back off and rebuild trust.');
      expect(updates[4].recommendationPreview?.analysisRunId, 'stream_1');
      expect(updates[4].recommendationPreview?.pick, 'resonate');
      expect(updates[4].recommendationPreview?.recommendedReply,
          'I get why that felt off.');
      expect(updates[5].result?.strategy, _fullSuccessBody['strategy']);

      final body = jsonDecode(capturedRequest.body) as Map<String, dynamic>;
      expect(body['responseMode'], 'stream');
      expect(body.containsKey('analysisRunId'), isFalse);
      expect(body['expectedTier'], 'starter');
      expect(body['revenueCatAppUserId'], r'$RCAnonymousID:def');
    });

    test('sanitizes progress labels and details while waiting', () async {
      final mockClient = MockClient((request) async {
        return http.Response.bytes(
          utf8.encode(
            [
              jsonEncode({
                'type': 'analysis.started',
                'label': 'normal',
                'detail': "interests: ['健康飲食', '義美品牌']\n已進入 Personal 階段",
              }),
              jsonEncode({
                'type': 'analysis.done',
                'finalResult': _fullSuccessBody,
              }),
            ].join('\n'),
          ),
          200,
          headers: {'content-type': 'application/x-ndjson'},
        );
      });

      final service = AnalysisService(
        clientFactory: () => mockClient,
        accessTokenProvider: () => 'fake-token',
      );

      final updates = await service.analyzeStream(
        messages: [_msg('hi')],
      ).toList();

      expect(updates.first.label, '進展順利');
      expect(updates.first.detail, contains('她的興趣/偏好：健康飲食、義美品牌'));
      expect(updates.first.detail, contains('個人層階段'));
      expect(updates.first.detail, isNot(contains('interests:')));
      expect(updates.first.detail, isNot(contains('Personal')));
      expect(updates.first.detail, isNot(contains('normal')));
    });

    test('treats legacy JSON 200 as a completed stream fallback', () async {
      final mockClient = MockClient((request) async {
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

      final updates = await service.analyzeStream(
        messages: [_msg('hi')],
      ).toList();

      expect(updates.map((u) => u.kind).toList(), [
        AnalysisStreamUpdateKind.done,
      ]);
      expect(updates.single.result?.recommendation.content, 'c');
    });

    test('accepts analysis.done result alias from stream response', () async {
      final mockClient = MockClient((request) async {
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'type': 'analysis.done',
              'result': _fullSuccessBody,
            }),
          ),
          200,
          headers: {'content-type': 'application/x-ndjson'},
        );
      });

      final service = AnalysisService(
        clientFactory: () => mockClient,
        accessTokenProvider: () => 'fake-token',
      );

      final updates = await service.analyzeStream(
        messages: [_msg('hi')],
      ).toList();

      expect(updates.map((u) => u.kind).toList(), [
        AnalysisStreamUpdateKind.done,
      ]);
      expect(updates.single.result?.strategy, _fullSuccessBody['strategy']);
      expect(updates.single.result?.recommendation.content, 'c');
    });

    test('formats report section object payload without raw JSON', () async {
      final mockClient = MockClient((request) async {
        return http.Response.bytes(
          utf8.encode(
            [
              jsonEncode({
                'type': 'analysis.report_section',
                'section': 'psychology',
                'content': {
                  'subtext': '她用活潑的方式回應，展現友善開放的態度',
                  'qualificationSignal': false,
                },
              }),
              jsonEncode({
                'type': 'analysis.done',
                'finalResult': _fullSuccessBody,
              }),
            ].join('\n'),
          ),
          200,
          headers: {'content-type': 'application/x-ndjson'},
        );
      });

      final service = AnalysisService(
        clientFactory: () => mockClient,
        accessTokenProvider: () => 'fake-token',
      );

      final updates = await service.analyzeStream(
        messages: [_msg('hi')],
      ).toList();

      expect(updates.first.content?.title, '心理訊號');
      expect(updates.first.content?.body, contains('她用活潑的方式回應'));
      expect(updates.first.content?.body, contains('主動投入訊號：沒有'));
      expect(updates.first.content?.body, isNot(contains('{"subtext"')));
      expect(
          updates.first.content?.body, isNot(contains('qualificationSignal')));
    });

    test('formats report section JSON message without raw JSON', () async {
      final mockClient = MockClient((request) async {
        return http.Response.bytes(
          utf8.encode(
            [
              jsonEncode({
                'type': 'analysis.report_section',
                'section': 'gameStage',
                'message':
                    '{"current":"opening","status":"normal","nextStep":"可以開始輕鬆互動"}',
              }),
              jsonEncode({
                'type': 'analysis.done',
                'finalResult': _fullSuccessBody,
              }),
            ].join('\n'),
          ),
          200,
          headers: {'content-type': 'application/x-ndjson'},
        );
      });

      final service = AnalysisService(
        clientFactory: () => mockClient,
        accessTokenProvider: () => 'fake-token',
      );

      final updates = await service.analyzeStream(
        messages: [_msg('hi')],
      ).toList();

      expect(updates.first.content?.title, '關係階段');
      expect(updates.first.content?.body, contains('目前狀態：破冰階段'));
      expect(updates.first.content?.body, contains('狀態：進展順利'));
      expect(updates.first.content?.body, contains('下一步：可以開始輕鬆互動'));
      expect(updates.first.content?.body, isNot(contains('{"current"')));
      expect(updates.first.content?.body, isNot(contains('"nextStep"')));
      expect(updates.first.content?.body, isNot(contains('normal')));
    });

    test('formats report section status enum without English copy', () async {
      final mockClient = MockClient((request) async {
        return http.Response.bytes(
          utf8.encode(
            [
              jsonEncode({
                'type': 'analysis.report_section',
                'section': 'status',
                'content': 'normal',
              }),
              jsonEncode({
                'type': 'analysis.done',
                'finalResult': _fullSuccessBody,
              }),
            ].join('\n'),
          ),
          200,
          headers: {'content-type': 'application/x-ndjson'},
        );
      });

      final service = AnalysisService(
        clientFactory: () => mockClient,
        accessTokenProvider: () => 'fake-token',
      );

      final updates = await service.analyzeStream(
        messages: [_msg('hi')],
      ).toList();

      expect(updates.first.content?.title, '關係狀態');
      expect(updates.first.content?.body, '進展順利');
      expect(updates.first.content?.body, isNot(contains('normal')));
    });

    test('drops unknown report section when body is only schema enum',
        () async {
      final mockClient = MockClient((request) async {
        return http.Response.bytes(
          utf8.encode(
            [
              jsonEncode({
                'type': 'analysis.report_section',
                'content': 'normal',
              }),
              jsonEncode({
                'type': 'analysis.done',
                'finalResult': _fullSuccessBody,
              }),
            ].join('\n'),
          ),
          200,
          headers: {'content-type': 'application/x-ndjson'},
        );
      });

      final service = AnalysisService(
        clientFactory: () => mockClient,
        accessTokenProvider: () => 'fake-token',
      );

      final updates = await service.analyzeStream(
        messages: [_msg('hi')],
      ).toList();

      expect(
        updates
            .where((update) => update.kind == AnalysisStreamUpdateKind.content),
        isEmpty,
      );
      expect(updates.single.kind, AnalysisStreamUpdateKind.done);
    });

    test('formats mixed schema enum text without raw English labels', () async {
      final mockClient = MockClient((request) async {
        return http.Response.bytes(
          utf8.encode(
            [
              jsonEncode({
                'type': 'analysis.report_section',
                'content':
                    'normal，她主動分享生活片段，是正常的投入互動\n已進入 Personal 階段，她願意分享具體的生活細節和偏好',
              }),
              jsonEncode({
                'type': 'analysis.done',
                'finalResult': _fullSuccessBody,
              }),
            ].join('\n'),
          ),
          200,
          headers: {'content-type': 'application/x-ndjson'},
        );
      });

      final service = AnalysisService(
        clientFactory: () => mockClient,
        accessTokenProvider: () => 'fake-token',
      );

      final updates = await service.analyzeStream(
        messages: [_msg('hi')],
      ).toList();

      expect(updates.first.content?.body, contains('進展順利'));
      expect(updates.first.content?.body, contains('個人層階段'));
      expect(updates.first.content?.body, isNot(contains('normal')));
      expect(updates.first.content?.body, isNot(contains('Personal')));
    });

    test('formats capitalized status enum with punctuation', () async {
      final mockClient = MockClient((request) async {
        return http.Response.bytes(
          utf8.encode(
            [
              jsonEncode({
                'type': 'analysis.report_section',
                'content': 'Normal：她主動分享生活片段，是正常投入互動',
              }),
              jsonEncode({
                'type': 'analysis.done',
                'finalResult': _fullSuccessBody,
              }),
            ].join('\n'),
          ),
          200,
          headers: {'content-type': 'application/x-ndjson'},
        );
      });

      final service = AnalysisService(
        clientFactory: () => mockClient,
        accessTokenProvider: () => 'fake-token',
      );

      final updates = await service.analyzeStream(
        messages: [_msg('hi')],
      ).toList();

      expect(updates.first.content?.body, contains('進展順利'));
      expect(updates.first.content?.body, isNot(contains('Normal')));
      expect(updates.first.content?.body, isNot(contains('normal')));
    });

    test('formats partner memory schema keys without raw field names',
        () async {
      final mockClient = MockClient((request) async {
        return http.Response.bytes(
          utf8.encode(
            [
              jsonEncode({
                'type': 'analysis.report_section',
                'content':
                    "interests: ['健康飲食', '義美品牌'],\ntraits: ['注意細節', '願意嘗試新東西'],\nnotes: ['偏好無糖產品', '有固定的品牌忠誠度']",
              }),
              jsonEncode({
                'type': 'analysis.done',
                'finalResult': _fullSuccessBody,
              }),
            ].join('\n'),
          ),
          200,
          headers: {'content-type': 'application/x-ndjson'},
        );
      });

      final service = AnalysisService(
        clientFactory: () => mockClient,
        accessTokenProvider: () => 'fake-token',
      );

      final updates = await service.analyzeStream(
        messages: [_msg('hi')],
      ).toList();

      final body = updates.first.content?.body;
      expect(body, contains('她的興趣/偏好：健康飲食、義美品牌'));
      expect(body, contains('她的特質：注意細節、願意嘗試新東西'));
      expect(body, contains('補充觀察：偏好無糖產品、有固定的品牌忠誠度'));
      expect(body, isNot(contains('interests:')));
      expect(body, isNot(contains('traits:')));
      expect(body, isNot(contains('notes:')));
    });

    test('formats single-line partner memory schema keys', () async {
      final mockClient = MockClient((request) async {
        return http.Response.bytes(
          utf8.encode(
            [
              jsonEncode({
                'type': 'analysis.report_section',
                'content':
                    "interests: ['健康飲食', '義美品牌'], traits: ['注意細節', '願意嘗試新東西'], notes: ['偏好無糖產品', '有固定的品牌忠誠度']",
              }),
              jsonEncode({
                'type': 'analysis.done',
                'finalResult': _fullSuccessBody,
              }),
            ].join('\n'),
          ),
          200,
          headers: {'content-type': 'application/x-ndjson'},
        );
      });

      final service = AnalysisService(
        clientFactory: () => mockClient,
        accessTokenProvider: () => 'fake-token',
      );

      final updates = await service.analyzeStream(
        messages: [_msg('hi')],
      ).toList();

      final body = updates.first.content?.body;
      expect(body, contains('她的興趣/偏好：健康飲食、義美品牌'));
      expect(body, contains('她的特質：注意細節、願意嘗試新東西'));
      expect(body, contains('補充觀察：偏好無糖產品、有固定的品牌忠誠度'));
      expect(body, isNot(contains('interests:')));
      expect(body, isNot(contains('traits:')));
      expect(body, isNot(contains('notes:')));
    });

    test('formats partner memory object arrays without raw field names',
        () async {
      final mockClient = MockClient((request) async {
        return http.Response.bytes(
          utf8.encode(
            [
              jsonEncode({
                'type': 'analysis.report_section',
                'content': {
                  'interests': ['健康飲食', '義美品牌'],
                  'traits': ['注意細節', '願意嘗試新東西'],
                  'notes': ['偏好無糖產品', '有固定的品牌忠誠度'],
                },
              }),
              jsonEncode({
                'type': 'analysis.done',
                'finalResult': _fullSuccessBody,
              }),
            ].join('\n'),
          ),
          200,
          headers: {'content-type': 'application/x-ndjson'},
        );
      });

      final service = AnalysisService(
        clientFactory: () => mockClient,
        accessTokenProvider: () => 'fake-token',
      );

      final updates = await service.analyzeStream(
        messages: [_msg('hi')],
      ).toList();

      final body = updates.first.content?.body;
      expect(body, contains('她的興趣/偏好：健康飲食、義美品牌'));
      expect(body, contains('她的特質：注意細節、願意嘗試新東西'));
      expect(body, contains('補充觀察：偏好無糖產品、有固定的品牌忠誠度'));
      expect(body, isNot(contains('interests')));
      expect(body, isNot(contains('traits')));
      expect(body, isNot(contains('notes')));
    });

    test('includes analysisRunId when retrying an existing stream run',
        () async {
      late http.Request capturedRequest;
      final mockClient = MockClient((request) async {
        capturedRequest = request;
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'type': 'analysis.done',
              'finalResult': _fullSuccessBody,
            }),
          ),
          200,
          headers: {'content-type': 'application/x-ndjson'},
        );
      });

      final service = AnalysisService(
        clientFactory: () => mockClient,
        accessTokenProvider: () => 'fake-token',
      );

      await service.analyzeStream(
        analysisRunId: 'stream_retry_1',
        messages: [_msg('hi')],
      ).toList();

      final body = jsonDecode(capturedRequest.body) as Map<String, dynamic>;
      expect(body['responseMode'], 'stream');
      expect(body['analysisRunId'], 'stream_retry_1');
    });

    test('throws StreamModeException when stream emits analysis.error',
        () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'type': 'analysis.error',
            'code': 'STREAM_CHARGE_FAILED',
            'message': 'Quota failed',
            'recoverable': true,
            'retriesRemaining': 2,
          }),
          200,
          headers: {'content-type': 'application/x-ndjson'},
        );
      });

      final service = AnalysisService(
        clientFactory: () => mockClient,
        accessTokenProvider: () => 'fake-token',
      );

      await expectLater(
        () => service.analyzeStream(messages: [_msg('hi')]).toList(),
        throwsA(
          isA<StreamModeException>()
              .having((e) => e.code, 'code', 'STREAM_CHARGE_FAILED')
              .having((e) => e.message, 'message', 'Quota failed')
              .having((e) => e.recoverable, 'recoverable', true)
              .having((e) => e.retriesRemaining, 'retriesRemaining', 2),
        ),
      );
    });
  });
}
