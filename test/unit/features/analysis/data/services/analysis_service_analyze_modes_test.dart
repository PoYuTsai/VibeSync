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
  group('AnalysisService.optimizeMessage billing contract', () {
    const requestId = '123e4567-e89b-42d3-a456-426614174000';

    test('wires one logical request id and reuses it across HTTP retry',
        () async {
      final bodies = <Map<String, dynamic>>[];
      var calls = 0;
      Future<http.Response> handler(http.Request request) async {
        calls += 1;
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        if (calls == 1) {
          return http.Response(
            jsonEncode({
              'error': 'OPTIMIZE_MESSAGE_SETTLEMENT_RETRYABLE',
              'code': 'OPTIMIZE_MESSAGE_SETTLEMENT_RETRYABLE',
              'message': '額度確認回應中斷',
            }),
            503,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({
            ..._fullSuccessBody,
            'optimizedMessage': {
              'original': '要不要喝咖啡',
              'optimized': '這週要不要一起喝杯咖啡？',
              'improvements': ['更自然'],
            },
            'usage': {
              'messagesUsed': 1,
              'monthlyRemaining': 799,
              'dailyRemaining': 79,
              'requestType': 'optimize_message',
              'quotaReason': 'optimize_message_fixed_1',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      final service = AnalysisService(
        clientFactory: () => MockClient(handler),
        accessTokenProvider: () => 'fake-token',
        expectedTierProvider: () => 'essential',
        revenueCatAppUserIdProvider: () async => r'$RCAnonymousID:optimize',
      );

      final result = await service.analyzeConversation(
        [_msg('最近有空嗎？')],
        userDraft: '要不要喝咖啡',
        requestId: requestId,
      );

      expect(calls, 2);
      expect(bodies.map((body) => body['requestId']), everyElement(requestId));
      expect(bodies.last['billingProtocolVersion'], 3);
      expect(bodies.last['userDraft'], '要不要喝咖啡');
      expect(result.optimizedMessage?.optimized, '這週要不要一起喝杯咖啡？');
      expect(result.rawResponse?['usage']['messagesUsed'], 1);
      expect(
        result.rawResponse?['usage']['quotaReason'],
        'optimize_message_fixed_1',
      );
    });

    test('refineInstruction：非空才進 payload，空白與未帶都不得出現這個鍵', () async {
      final bodies = <Map<String, dynamic>>[];
      Future<http.Response> handler(http.Request request) async {
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(
          jsonEncode({
            ..._fullSuccessBody,
            'optimizedMessage': {
              'original': '要不要喝咖啡',
              'optimized': '這週要不要一起喝杯咖啡？',
              'improvements': ['更自然'],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      final service = AnalysisService(
        clientFactory: () => MockClient(handler),
        accessTokenProvider: () => 'fake-token',
        expectedTierProvider: () => 'essential',
        revenueCatAppUserIdProvider: () async => r'$RCAnonymousID:optimize',
      );

      await service.analyzeConversation(
        [_msg('最近有空嗎？')],
        userDraft: '要不要喝咖啡',
        refineInstruction: '  短一點  ',
        requestId: requestId,
      );
      await service.analyzeConversation(
        [_msg('最近有空嗎？')],
        userDraft: '要不要喝咖啡',
        refineInstruction: '   ',
        requestId: requestId,
      );
      await service.analyzeConversation(
        [_msg('最近有空嗎？')],
        userDraft: '要不要喝咖啡',
        requestId: requestId,
      );

      expect(bodies[0]['refineInstruction'], '短一點');
      // 沒有指令的請求必須與拆分前 byte-identical，否則 server 端 input hash
      // 分岔，既有的潤飾 replay 會全部失效。
      expect(bodies[1].containsKey('refineInstruction'), isFalse);
      expect(bodies[2].containsKey('refineInstruction'), isFalse);
      expect(bodies[1], equals(bodies[2]));
    });

    test('錯誤文案依入口切換：微調不得說成草稿潤飾', () async {
      AnalysisService serviceFor(int status, String code) => AnalysisService(
            clientFactory: () => MockClient((request) async {
              return http.Response(
                jsonEncode({'error': code, 'code': code}),
                status,
                headers: {'content-type': 'application/json'},
              );
            }),
            accessTokenProvider: () => 'fake-token',
            expectedTierProvider: () => 'essential',
            revenueCatAppUserIdProvider: () async => r'$RCAnonymousID:optimize',
          );

      Future<String> messageFor(
        int status,
        String code, {
        String? refineInstruction,
      }) async {
        try {
          await serviceFor(status, code).analyzeConversation(
            [_msg('最近有空嗎？')],
            userDraft: '要不要喝咖啡',
            refineInstruction: refineInstruction,
            requestId: requestId,
          );
        } on AnalysisException catch (error) {
          return error.message;
        }
        fail('expected $code to throw');
      }

      // preflight mismatch 是 400、settlement race mismatch 是 409，兩條都要切。
      const cases = <List<Object>>[
        [400, 'INVALID_OPTIMIZE_MESSAGE_REQUEST_ID'],
        [400, 'OPTIMIZE_MESSAGE_REQUEST_REPLAY_MISMATCH'],
        [409, 'OPTIMIZE_MESSAGE_REQUEST_REPLAY_MISMATCH'],
        [500, 'OPTIMIZE_MESSAGE_REPLAY_INVALID'],
        [500, 'OPTIMIZE_MESSAGE_SETTLEMENT_FAILED'],
        // 同一個 code 兩個狀態碼（帳本快照 500、結果無效 502），都要保住
        // 「不扣額度」這句。
        [500, 'OPTIMIZE_MESSAGE_RESULT_INVALID'],
        [502, 'OPTIMIZE_MESSAGE_RESULT_INVALID'],
      ];

      for (final testCase in cases) {
        final status = testCase[0] as int;
        final code = testCase[1] as String;
        final refined = await messageFor(
          status,
          code,
          refineInstruction: '短一點',
        );
        final polished = await messageFor(status, code);

        expect(
          refined,
          isNot(contains('草稿潤飾')),
          reason: '$code($status) 從微調入口不得說草稿潤飾',
        );
        expect(
          refined,
          contains('本次不會扣額度'),
          reason: '$code($status) 必須維持不扣費保證',
        );
        expect(
          polished,
          isNot(contains('回覆微調')),
          reason: '$code($status) 從潤飾入口不得說回覆微調',
        );
      }

      // 泛用失敗分支同樣要跟著入口走。
      expect(
        await messageFor(503, 'UPSTREAM_UNAVAILABLE', refineInstruction: '短一點'),
        contains('回覆微調'),
      );
      expect(
        await messageFor(503, 'UPSTREAM_UNAVAILABLE'),
        contains('訊息優化'),
      );
    });

    test('安全攔下：專屬文案引導改寫、依入口切換、保住不扣費，不得說「請稍後再試」', () async {
      AnalysisService service() => AnalysisService(
            clientFactory: () => MockClient((request) async {
              return http.Response(
                jsonEncode({
                  'error': 'OPTIMIZE_MESSAGE_SAFETY_BLOCKED',
                  'code': 'OPTIMIZE_MESSAGE_SAFETY_BLOCKED',
                  'message': '這段內容帶有施壓或威脅的說法，安全守門已攔下。本次不會扣額度。',
                  'shouldChargeQuota': false,
                }),
                502,
                headers: {'content-type': 'application/json'},
              );
            }),
            accessTokenProvider: () => 'fake-token',
            expectedTierProvider: () => 'essential',
            revenueCatAppUserIdProvider: () async => r'$RCAnonymousID:optimize',
          );

      Future<String> messageFor({String? refineInstruction}) async {
        try {
          await service().analyzeConversation(
            [_msg('最近有空嗎？')],
            userDraft: '你不答應我就不走',
            refineInstruction: refineInstruction,
            requestId: requestId,
          );
        } on AnalysisException catch (error) {
          expect(error.code, 'OPTIMIZE_MESSAGE_SAFETY_BLOCKED');
          return error.message;
        }
        fail('expected OPTIMIZE_MESSAGE_SAFETY_BLOCKED to throw');
      }

      final polished = await messageFor();
      expect(polished, contains('施壓或威脅'));
      expect(polished, contains('本次不會扣額度'));
      expect(polished, isNot(contains('請稍後再試')));

      final refined = await messageFor(refineInstruction: '短一點');
      expect(refined, contains('施壓或威脅'));
      expect(refined, contains('本次不會扣額度'));
      expect(refined, isNot(contains('潤飾')));
    });

    test('亂碼草稿：專屬文案引導換草稿、保住不扣費，不得說「請稍後再試」', () async {
      final service = AnalysisService(
        clientFactory: () => MockClient((request) async {
          return http.Response(
            jsonEncode({
              'error': 'OPTIMIZE_MESSAGE_DRAFT_UNREADABLE',
              'code': 'OPTIMIZE_MESSAGE_DRAFT_UNREADABLE',
              'message': '看不懂這段草稿，請換成想傳的訊息再試一次。本次不會扣額度。',
              'shouldChargeQuota': false,
            }),
            502,
            headers: {'content-type': 'application/json'},
          );
        }),
        accessTokenProvider: () => 'fake-token',
        expectedTierProvider: () => 'essential',
        revenueCatAppUserIdProvider: () async => r'$RCAnonymousID:optimize',
      );

      await expectLater(
        () => service.analyzeConversation(
          [_msg('最近有空嗎？')],
          userDraft: '烏龜殼獸',
          requestId: requestId,
        ),
        throwsA(
          isA<AnalysisException>()
              .having(
                (error) => error.code,
                'code',
                'OPTIMIZE_MESSAGE_DRAFT_UNREADABLE',
              )
              .having(
                (error) => error.message,
                'message',
                allOf(
                  contains('看不懂這段草稿'),
                  contains('本次不會扣額度'),
                  isNot(contains('請稍後再試')),
                ),
              ),
        ),
      );
    });

    test('maps fixed-cost monthly 429 with quotaNeeded one', () async {
      final service = AnalysisService(
        clientFactory: () => MockClient((request) async {
          return http.Response(
            jsonEncode({
              'error': 'Monthly limit exceeded',
              'message': '本月額度已用完',
              'quotaNeeded': 1,
              'monthlyLimit': 800,
              'dailyLimit': 80,
              'monthlyUsed': 800,
              'dailyUsed': 20,
              'monthlyRemaining': 0,
              'dailyRemaining': 60,
            }),
            429,
            headers: {'content-type': 'application/json'},
          );
        }),
        accessTokenProvider: () => 'fake-token',
        expectedTierProvider: () => 'essential',
        revenueCatAppUserIdProvider: () async => r'$RCAnonymousID:optimize',
      );

      await expectLater(
        () => service.analyzeConversation(
          [_msg('最近有空嗎？')],
          userDraft: '要不要喝咖啡',
          requestId: requestId,
        ),
        throwsA(
          isA<MonthlyLimitExceededException>()
              .having((error) => error.quotaNeeded, 'quotaNeeded', 1)
              .having((error) => error.remaining, 'remaining', 0),
        ),
      );
    });

    test('surfaces authoritative invalid-result failure without usage',
        () async {
      var calls = 0;
      final service = AnalysisService(
        clientFactory: () => MockClient((request) async {
          calls += 1;
          return http.Response(
            jsonEncode({
              'error': 'OPTIMIZE_MESSAGE_RESULT_INVALID',
              'code': 'OPTIMIZE_MESSAGE_RESULT_INVALID',
              'message': '這次沒有產生可用的潤飾結果，本次不會扣額度。',
              'shouldChargeQuota': false,
            }),
            502,
            headers: {'content-type': 'application/json'},
          );
        }),
        accessTokenProvider: () => 'fake-token',
        expectedTierProvider: () => 'essential',
        revenueCatAppUserIdProvider: () async => r'$RCAnonymousID:optimize',
      );

      await expectLater(
        () => service.analyzeConversation(
          [_msg('最近有空嗎？')],
          userDraft: '要不要喝咖啡',
          requestId: requestId,
        ),
        throwsA(
          isA<AnalysisException>()
              .having(
                (error) => error.code,
                'code',
                'OPTIMIZE_MESSAGE_RESULT_INVALID',
              )
              .having(
                (error) => error.message,
                'message',
                contains('本次不會扣額度'),
              ),
        ),
      );
      expect(calls, 1, reason: 'authoritative failure must not auto-retry');
    });

    test('surfaces settlement failure as no-charge and does not retry',
        () async {
      var calls = 0;
      final service = AnalysisService(
        clientFactory: () => MockClient((request) async {
          calls += 1;
          return http.Response(
            jsonEncode({
              'error': 'OPTIMIZE_MESSAGE_SETTLEMENT_FAILED',
              'code': 'OPTIMIZE_MESSAGE_SETTLEMENT_FAILED',
              'message': '草稿潤飾額度確認失敗，本次不會扣額度。',
            }),
            500,
            headers: {'content-type': 'application/json'},
          );
        }),
        accessTokenProvider: () => 'fake-token',
        expectedTierProvider: () => 'essential',
        revenueCatAppUserIdProvider: () async => r'$RCAnonymousID:optimize',
      );

      await expectLater(
        () => service.analyzeConversation(
          [_msg('最近有空嗎？')],
          userDraft: '要不要喝咖啡',
          requestId: requestId,
        ),
        throwsA(
          isA<AnalysisException>()
              .having(
                (error) => error.code,
                'code',
                'OPTIMIZE_MESSAGE_SETTLEMENT_FAILED',
              )
              .having(
                (error) => error.message,
                'message',
                contains('本次不會扣額度'),
              ),
        ),
      );
      expect(calls, 1, reason: 'settlement failure must not auto-retry');
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
      // ADR #19 定案 #6：stream 路徑同樣必送 capability 訊號。
      expect(body['billingProtocolVersion'], 3);
    });

    test('maps a transport reset after partial stream content to NETWORK_ERROR',
        () async {
      final mockClient = MockClient.streaming((request, bodyStream) async {
        await bodyStream.drain<void>();
        final responseStream = Stream<List<int>>.multi((controller) {
          controller.add(
            utf8.encode(
              '${jsonEncode({
                    'type': 'analysis.started',
                    'runId': 'stream-recoverable',
                  })}\n'
              '${jsonEncode({
                    'type': 'analysis.recommendation',
                    'selectedStyle': 'resonate',
                    'message': '先接住她的情緒。',
                    'reason': '維持對話連續性。',
                  })}\n',
            ),
          );
          controller.addError(
            http.ClientException('Connection reset while receiving data'),
          );
          controller.close();
        });
        return http.StreamedResponse(
          responseStream,
          200,
          headers: {'content-type': 'application/x-ndjson'},
        );
      });
      final service = AnalysisService(
        clientFactory: () => mockClient,
        accessTokenProvider: () => 'fake-token',
      );

      expect(
        () => service.analyzeStream(messages: [_msg('hi')]).toList(),
        throwsA(
          isA<AnalysisException>()
              .having((error) => error.code, 'code', 'NETWORK_ERROR')
              .having(
                (error) => error.suggestedAction,
                'suggestedAction',
                AnalysisErrorAction.retry,
              ),
        ),
      );
    });

    test(
        'ADR #19 雙 limit 429：monthlyRemaining < quotaNeeded → Monthly'
        '（regression：buildQuotaExceededPayload 同時帶兩 limit，舊判別誤報 daily）',
        () async {
      final mockClient = MockClient((request) async {
        // buildQuotaExceededPayload 形狀：兩個 limit 欄位都在。
        return http.Response(
          jsonEncode({
            'error': 'Monthly limit exceeded',
            'message': '本月額度已用完，升級方案可取得更多分析與教練額度。',
            'quotaNeeded': 5,
            'used': 198,
            'limit': 200,
            'monthlyLimit': 200,
            'dailyLimit': 15,
            'monthlyUsed': 198,
            'dailyUsed': 3,
            'monthlyRemaining': 2,
            'dailyRemaining': 12,
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
        () => service.analyzeStream(messages: [_msg('hi')]).toList(),
        throwsA(
          isA<MonthlyLimitExceededException>()
              .having((e) => e.remaining, 'remaining', 2)
              .having((e) => e.quotaNeeded, 'quotaNeeded', 5)
              .having((e) => e.used, 'used', 198),
        ),
      );
    });

    test('ADR #19 雙 limit 429：daily 擋下時 → DailyLimitExceededException',
        () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': 'Daily limit exceeded',
            'message': '今日額度已用完，明天會自動恢復；也可以升級取得更多額度。',
            'quotaNeeded': 5,
            'used': 14,
            'limit': 15,
            'monthlyLimit': 200,
            'dailyLimit': 15,
            'monthlyUsed': 60,
            'dailyUsed': 14,
            'monthlyRemaining': 140,
            'dailyRemaining': 1,
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
        () => service.analyzeStream(messages: [_msg('hi')]).toList(),
        throwsA(
          isA<DailyLimitExceededException>()
              .having((e) => e.remaining, 'remaining', 1)
              .having((e) => e.quotaNeeded, 'quotaNeeded', 5)
              .having((e) => e.used, 'used', 14),
        ),
      );
    });

    test('legacy 單 limit 429（只帶 dailyLimit）維持 Daily 判別', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': 'Daily limit exceeded',
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
        () => service.analyzeStream(messages: [_msg('hi')]).toList(),
        throwsA(isA<DailyLimitExceededException>()),
      );
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

    test('rejects legacy JSON 200 instead of accepting a stream fallback',
        () async {
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

      await expectLater(
        service.analyzeStream(messages: [_msg('hi')]).toList(),
        throwsA(
          isA<AnalysisException>()
              .having(
                (error) => error.code,
                'code',
                'INVALID_STREAM_CONTENT_TYPE',
              )
              .having(
                (error) => error.suggestedAction,
                'suggestedAction',
                AnalysisErrorAction.retry,
              ),
        ),
      );
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

    // Fixed Chinese fallback surfaced when the server `analysis.error` message
    // is not safe to show (engineering English, error codes, JSON/schema
    // fragments, or empty). Must match the production fallback string.
    const streamErrorFallback = '這次分析沒順利完成，請稍後再試一次。';

    AnalysisService streamErrorService(Map<String, dynamic> errorEvent) {
      final mockClient = MockClient((request) async {
        // Encode as UTF-8 bytes so Chinese message bodies survive (the String
        // Response constructor defaults to Latin1 and rejects CJK).
        return http.Response.bytes(
          utf8.encode(jsonEncode(errorEvent)),
          200,
          headers: {'content-type': 'application/x-ndjson'},
        );
      });
      return AnalysisService(
        clientFactory: () => mockClient,
        accessTokenProvider: () => 'fake-token',
      );
    }

    test(
        'analysis.error sanitizes engineering message to fallback while '
        'preserving code/recoverable/retries', () async {
      // Quota/paywall routing keys off code + retriesRemaining, never the
      // message string. The raw English "Quota failed" must not reach the user,
      // but the error must NOT be eaten: code and retry budget survive.
      final service = streamErrorService({
        'type': 'analysis.error',
        'code': 'STREAM_CHARGE_FAILED',
        'message': 'Quota failed',
        'recoverable': true,
        'retriesRemaining': 2,
      });

      await expectLater(
        () => service.analyzeStream(messages: [_msg('hi')]).toList(),
        throwsA(
          isA<StreamModeException>()
              .having((e) => e.code, 'code', 'STREAM_CHARGE_FAILED')
              .having((e) => e.message, 'message', streamErrorFallback)
              .having((e) => e.recoverable, 'recoverable', true)
              .having((e) => e.retriesRemaining, 'retriesRemaining', 2),
        ),
      );
    });

    test('analysis.error shows a readable Chinese server message verbatim',
        () async {
      const readable = '本月額度已用完，升級後可以繼續分析。';
      final service = streamErrorService({
        'type': 'analysis.error',
        'code': 'STREAM_CHARGE_FAILED',
        'message': readable,
        'recoverable': false,
        'retriesRemaining': 0,
      });

      await expectLater(
        () => service.analyzeStream(messages: [_msg('hi')]).toList(),
        throwsA(
          isA<StreamModeException>()
              .having((e) => e.code, 'code', 'STREAM_CHARGE_FAILED')
              .having((e) => e.message, 'message', readable),
        ),
      );
    });

    test('analysis.error falls back when message is a JSON/schema fragment',
        () async {
      final service = streamErrorService({
        'type': 'analysis.error',
        'code': 'STREAM_FAILED',
        'message': 'SyntaxError: Unexpected token < in JSON at position 0',
        'recoverable': true,
        'retriesRemaining': 1,
      });

      await expectLater(
        () => service.analyzeStream(messages: [_msg('hi')]).toList(),
        throwsA(
          isA<StreamModeException>()
              .having((e) => e.message, 'message', streamErrorFallback),
        ),
      );
    });

    test('analysis.error falls back when the server message is missing',
        () async {
      final service = streamErrorService({
        'type': 'analysis.error',
        'code': 'STREAM_FAILED',
        'recoverable': true,
        'retriesRemaining': 1,
      });

      await expectLater(
        () => service.analyzeStream(messages: [_msg('hi')]).toList(),
        throwsA(
          isA<StreamModeException>()
              .having((e) => e.message, 'message', streamErrorFallback),
        ),
      );
    });
  });
}
