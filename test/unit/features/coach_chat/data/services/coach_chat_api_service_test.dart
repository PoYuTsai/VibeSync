import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/coach_chat/data/services/coach_chat_api_service.dart';

class _Recorded {
  final String fn;
  final Map<String, dynamic> body;

  const _Recorded(this.fn, this.body);
}

CoachChatInvoker _stub(
  CoachChatInvokeResponse response, {
  List<_Recorded>? recorder,
}) {
  return (String fn, {required Map<String, dynamic> body}) async {
    recorder?.add(_Recorded(fn, body));
    return response;
  };
}

Map<String, dynamic> _validResponse({
  Map<String, dynamic>? card,
  String generatedAt = '2026-05-07T12:00:00.000Z',
}) {
  return <String, dynamic>{
    'card': card ??
        <String, dynamic>{
          'mode': 'replyCraft',
          'responseType': 'coachAnswer',
          'headline': '接住她的觀察',
          'answer': '她是在丟一個觀察，不是要你立刻證明自己。',
          'userTruth': '你想接住她的好奇，但不想裝深沉。',
          'userState': '你可能急著解釋，反而把輕鬆感弄重。',
          'frictionType': 'overPolishing',
          'nextStep': '承認一半，補一個畫面，再把球丟回她。',
          'suggestedLine': '被妳發現了，我會在飲料櫃前思考人生。妳也是亂逛派嗎？',
          'rewriteDecision': 'light_edit',
          'rewriteReason': '保留原意，只補畫面與反問。',
          'boundaryReminder': '不要把一句觀察放大成考試。',
          'needsReflection': false,
          'reflectionQuestion': null,
          'costDeducted': 1,
        },
    'sessionId': 's-1',
    'provider': 'claude',
    'model': 'claude-sonnet-4-20250514',
    'generatedAt': generatedAt,
  };
}

CoachChatInvokeResponse _ok([Map<String, dynamic>? data]) =>
    CoachChatInvokeResponse(status: 200, data: data ?? _validResponse());

void main() {
  group('CoachChatApiService request contract', () {
    test('calls coach-chat and sends the compact context payload', () async {
      final calls = <_Recorded>[];
      final service =
          CoachChatApiService(invoker: _stub(_ok(), recorder: calls));

      await service.ask(
        conversationId: 'c-1',
        partnerId: 'p-1',
        sessionId: 's-1',
        question: ' 她這句話是真的有興趣嗎？ ',
        rawReplyDraft: '哈哈哪有',
        activeSessionTurns: const [
          CoachChatSessionTurn(
            role: 'user',
            kind: 'question',
            content: '她說我很有故事是什麼意思？',
          ),
          CoachChatSessionTurn(
            role: 'coach',
            kind: 'clarification',
            content: '你聽到她這句話後，心裡第一個反應是什麼？',
          ),
        ],
        forceAnswer: true,
        recentMessages: [
          CoachChatMessage(
            isFromMe: false,
            text: '感覺你是個很有故事的人',
            createdAt: DateTime.parse('2026-05-07T10:00:00Z'),
          ),
          const CoachChatMessage(isFromMe: true, text: '哈哈哪有'),
        ],
        conversationSummary: '最近在升溫。',
        analysisSnapshot: const CoachChatAnalysisSnapshot(
          heatScore: 68,
          stage: 'warming',
          summary: '她丟人格觀察句。',
          nextStep: '承認一半再反問。',
          coachActionType: 'extendTopicStoryFrame',
          keySignals: ['人格觀察', '可接球'],
        ),
        effectiveStyleContext: '  - Preferred voice: 幽默  ',
        partnerHint: const CoachChatPartnerHint(
          name: 'Mia',
          traits: ['活潑', '喜歡旅行'],
        ),
        dataQualityFlagged: false,
      );

      expect(calls, hasLength(1));
      expect(calls.single.fn, 'coach-chat');
      expect(calls.single.body['conversationId'], 'c-1');
      expect(calls.single.body['partnerId'], 'p-1');
      expect(calls.single.body['sessionId'], 's-1');
      expect(calls.single.body['userQuestion'], '她這句話是真的有興趣嗎？');
      expect(calls.single.body['rawReplyDraft'], '哈哈哪有');
      expect(calls.single.body['forceAnswer'], true);
      expect(calls.single.body['activeSessionTurns'], [
        {
          'role': 'user',
          'kind': 'question',
          'content': '她說我很有故事是什麼意思？',
        },
        {
          'role': 'coach',
          'kind': 'clarification',
          'content': '你聽到她這句話後，心裡第一個反應是什麼？',
        },
      ]);
      expect(calls.single.body['conversationSummary'], '最近在升溫。');
      expect(
          calls.single.body['effectiveStyleContext'], '- Preferred voice: 幽默');
      expect(calls.single.body['dataQualityFlagged'], isFalse);
      expect(calls.single.body['partnerHint'], {
        'name': 'Mia',
        'traits': ['活潑', '喜歡旅行'],
      });
      expect(calls.single.body['analysisSnapshot'], {
        'heatScore': 68,
        'stage': 'warming',
        'summary': '她丟人格觀察句。',
        'nextStep': '承認一半再反問。',
        'coachActionType': 'extendTopicStoryFrame',
        'keySignals': ['人格觀察', '可接球'],
      });
      expect(calls.single.body['recentMessages'], [
        {
          'sender': 'partner',
          'text': '感覺你是個很有故事的人',
          'createdAt': '2026-05-07T10:00:00.000Z',
        },
        {
          'sender': 'me',
          'text': '哈哈哪有',
        },
      ]);
    });

    test('strips partner traits when dataQualityFlagged is true', () async {
      final calls = <_Recorded>[];
      final service =
          CoachChatApiService(invoker: _stub(_ok(), recorder: calls));

      await service.ask(
        conversationId: 'c-1',
        partnerId: 'p-1',
        question: '我該怎麼判斷？',
        recentMessages: const [],
        partnerHint: const CoachChatPartnerHint(
          name: 'Mia',
          traits: ['活潑', '慢熟'],
        ),
        dataQualityFlagged: true,
      );

      expect(calls.single.body['partnerHint'], {'name': 'Mia'});
    });

    test('omits blank optional fields from the wire payload', () async {
      final calls = <_Recorded>[];
      final service =
          CoachChatApiService(invoker: _stub(_ok(), recorder: calls));

      await service.ask(
        conversationId: 'c-1',
        partnerId: null,
        question: '我是不是太急？',
        recentMessages: const [],
        conversationSummary: '   ',
        effectiveStyleContext: '   ',
        dataQualityFlagged: false,
      );

      expect(calls.single.body.containsKey('partnerId'), isFalse);
      expect(calls.single.body.containsKey('conversationSummary'), isFalse);
      expect(calls.single.body.containsKey('effectiveStyleContext'), isFalse);
      expect(calls.single.body.containsKey('partnerHint'), isFalse);
    });

    test('clamps over-length wire fields to server schema limits', () async {
      // server RequestSchema 是 strict＋硬上限：任一欄位超標整包 400，
      // 而長訊息/長分析快照會留在本機 → 同一對話每次問都失敗。
      final calls = <_Recorded>[];
      final service =
          CoachChatApiService(invoker: _stub(_ok(), recorder: calls));

      await service.ask(
        conversationId: 'c-1',
        partnerId: 'p-1',
        sessionId: 's-1',
        question: '問${'很' * 300}？',
        rawReplyDraft: '草稿${'長' * 300}',
        activeSessionTurns: [
          CoachChatSessionTurn(
            role: 'user',
            kind: 'question',
            content: '回合${'內' * 600}',
          ),
        ],
        recentMessages: [
          CoachChatMessage(isFromMe: true, text: '訊息${'字' * 600}'),
        ],
        conversationSummary: '摘要${'多' * 600}',
        analysisSnapshot: CoachChatAnalysisSnapshot(
          heatScore: 150,
          stage: '階段${'名' * 60}',
          summary: '分析${'長' * 300}',
          nextStep: '下一步${'走' * 300}',
          coachActionType: '動作${'型' * 100}',
          keySignals: ['訊號${'一' * 100}'],
        ),
        effectiveStyleContext: '風格${'述' * 600}',
        partnerHint: CoachChatPartnerHint(
          name: '名字${'長' * 100}',
          traits: ['特質${'多' * 60}'],
        ),
        dataQualityFlagged: false,
      );

      final body = calls.single.body;
      expect((body['userQuestion'] as String).length, lessThanOrEqualTo(240));
      expect((body['rawReplyDraft'] as String).length, lessThanOrEqualTo(240));
      expect(
        (body['conversationSummary'] as String).length,
        lessThanOrEqualTo(500),
      );
      expect(
        (body['effectiveStyleContext'] as String).length,
        lessThanOrEqualTo(500),
      );
      final turn =
          (body['activeSessionTurns'] as List).single as Map<String, dynamic>;
      expect((turn['content'] as String).length, lessThanOrEqualTo(500));
      final message =
          (body['recentMessages'] as List).single as Map<String, dynamic>;
      expect((message['text'] as String).length, lessThanOrEqualTo(500));
      final snapshot = body['analysisSnapshot'] as Map<String, dynamic>;
      expect(snapshot['heatScore'], 100);
      expect((snapshot['stage'] as String).length, lessThanOrEqualTo(40));
      expect((snapshot['summary'] as String).length, lessThanOrEqualTo(220));
      expect((snapshot['nextStep'] as String).length, lessThanOrEqualTo(220));
      expect(
        (snapshot['coachActionType'] as String).length,
        lessThanOrEqualTo(80),
      );
      final signal = (snapshot['keySignals'] as List).single as String;
      expect(signal.length, lessThanOrEqualTo(80));
      final hint = body['partnerHint'] as Map<String, dynamic>;
      expect((hint['name'] as String).length, lessThanOrEqualTo(80));
      final trait = (hint['traits'] as List).single as String;
      expect(trait.length, lessThanOrEqualTo(40));
    });

    test('wires outcomeInsightLines when provided (digest 回注)', () async {
      final calls = <_Recorded>[];
      final service =
          CoachChatApiService(invoker: _stub(_ok(), recorder: calls));

      await service.ask(
        conversationId: 'c-1',
        partnerId: 'p-1',
        question: '這樣推進會太快嗎？',
        recentMessages: const [],
        outcomeInsightLines: const [
          '最近 4 次教練建議結果：2 次有接、1 次冷回、1 次沒回。',
          '  她常在你照著發後冷回，先降速確認再推進。  ',
          '   ',
        ],
        dataQualityFlagged: false,
      );

      // 去空白行後只剩 2 行；每行 trim。
      expect(calls.single.body['outcomeInsightLines'], [
        '最近 4 次教練建議結果：2 次有接、1 次冷回、1 次沒回。',
        '她常在你照著發後冷回，先降速確認再推進。',
      ]);
    });

    test('omits outcomeInsightLines when empty (缺席＝現行為)', () async {
      final calls = <_Recorded>[];
      final service =
          CoachChatApiService(invoker: _stub(_ok(), recorder: calls));

      await service.ask(
        conversationId: 'c-1',
        partnerId: 'p-1',
        question: '我該怎麼開場？',
        recentMessages: const [],
        outcomeInsightLines: const [],
        dataQualityFlagged: false,
      );

      expect(calls.single.body.containsKey('outcomeInsightLines'), isFalse);
    });

    test('clamps outcomeInsightLines to schema limits (≤6 行、每行 ≤120)',
        () async {
      final calls = <_Recorded>[];
      final service =
          CoachChatApiService(invoker: _stub(_ok(), recorder: calls));

      await service.ask(
        conversationId: 'c-1',
        partnerId: 'p-1',
        question: '她到底在想什麼？',
        recentMessages: const [],
        outcomeInsightLines: [
          for (var i = 0; i < 10; i++) '洞察$i：${'長' * 300}',
        ],
        dataQualityFlagged: false,
      );

      final lines = calls.single.body['outcomeInsightLines'] as List;
      expect(lines.length, lessThanOrEqualTo(6));
      for (final line in lines) {
        expect((line as String).length, lessThanOrEqualTo(120));
      }
    });
  });

  group('CoachChatApiService response contract', () {
    test('header wait covers the buffered old-Edge worst case', () {
      expect(
        CoachChatApiService.defaultProgressConnectTimeout,
        greaterThanOrEqualTo(const Duration(seconds: 210)),
      );
    });

    test('progress transport emits lifecycle stages then parses final card',
        () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        expect(request.headers['Accept'], 'application/x-ndjson');
        expect(request.headers['Authorization'], 'Bearer access-token');
        final lines = [
          {'type': 'coach.progress', 'stage': 'request'},
          {
            'type': 'coach.progress',
            'stage': 'generating',
            'attempt': 1,
            'maxAttempts': 3,
          },
          {'type': 'coach.progress', 'stage': 'validating'},
          {'type': 'coach.progress', 'stage': 'finalizing'},
          {'type': 'coach.done', 'result': _validResponse()},
        ].map(jsonEncode).join('\n');
        return http.Response(
          '$lines\n',
          200,
          headers: {'content-type': 'application/x-ndjson; charset=utf-8'},
        );
      });
      final service = CoachChatApiService(
        clientFactory: () => client,
        accessTokenProvider: () => 'access-token',
        progressStreamingEnabled: true,
      );
      final updates = <CoachChatProgressUpdate>[];

      final result = await service.ask(
        conversationId: 'c-1',
        partnerId: 'p-1',
        question: '她是什麼意思？',
        recentMessages: const [],
        dataQualityFlagged: false,
        onProgress: updates.add,
      );

      expect(calls, 1);
      expect(
        updates.map((update) => update.stage),
        [
          CoachChatProgressStage.request,
          CoachChatProgressStage.generating,
          CoachChatProgressStage.validating,
          CoachChatProgressStage.finalizing,
        ],
      );
      expect(updates[1].attempt, 1);
      expect(updates[1].maxAttempts, 3);
      expect(result.headline, '接住她的觀察');
      expect(result.costDeducted, 1);
    });

    test('JSON 200 from an older Edge revision is accepted without replay',
        () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return http.Response(
          jsonEncode(_validResponse()),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = CoachChatApiService(
        clientFactory: () => client,
        accessTokenProvider: () => 'access-token',
        progressStreamingEnabled: true,
      );

      final result = await service.ask(
        conversationId: 'c-1',
        partnerId: null,
        question: '我該怎麼回？',
        recentMessages: const [],
        dataQualityFlagged: false,
      );

      expect(calls, 1);
      expect(result.headline, '接住她的觀察');
    });

    test('a progress-listener failure cannot abort the validated result',
        () async {
      final service = CoachChatApiService(
        progressInvoker: (
          functionName, {
          required body,
          required onProgress,
        }) async {
          onProgress(const CoachChatProgressUpdate(
            stage: CoachChatProgressStage.generating,
          ));
          return _ok();
        },
        progressStreamingEnabled: true,
      );

      final result = await service.ask(
        conversationId: 'c-1',
        partnerId: null,
        question: '我該怎麼回？',
        recentMessages: const [],
        dataQualityFlagged: false,
        onProgress: (_) => throw StateError('widget disposed'),
      );

      expect(result.headline, '接住她的觀察');
    });

    test('post-start 429 terminal frame preserves quota/paywall mapping',
        () async {
      final client = MockClient((request) async {
        final lines = [
          {'type': 'coach.progress', 'stage': 'finalizing'},
          {
            'type': 'coach.error',
            'status': 429,
            'error': {
              'error': 'Daily limit exceeded',
              'message': '今日額度已用完',
              'used': 15,
              'limit': 15,
            },
          },
        ].map(jsonEncode).join('\n');
        return http.Response(
          '$lines\n',
          200,
          headers: {
            'content-type': 'application/x-ndjson; charset=utf-8',
          },
        );
      });
      final service = CoachChatApiService(
        clientFactory: () => client,
        accessTokenProvider: () => 'access-token',
        progressStreamingEnabled: true,
      );

      expect(
        () => service.ask(
          conversationId: 'c-1',
          partnerId: null,
          question: '再給我一次正式建議',
          recentMessages: const [],
          dataQualityFlagged: false,
        ),
        throwsA(
          isA<CoachChatQuotaExceededException>()
              .having((error) => error.used, 'used', 15)
              .having((error) => error.limit, 'limit', 15),
        ),
      );
    });

    test('preflight model-rate 429 stays retryable API error, not paywall',
        () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': 'Model rate limited',
            'code': 'MODEL_RATE_LIMITED',
            'message': '操作太頻繁，請稍等一分鐘再試。',
          }),
          429,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final service = CoachChatApiService(
        clientFactory: () => client,
        accessTokenProvider: () => 'access-token',
        progressStreamingEnabled: true,
      );

      await expectLater(
        service.ask(
          conversationId: 'c-1',
          partnerId: null,
          question: '我該怎麼回？',
          recentMessages: const [],
          dataQualityFlagged: false,
        ),
        throwsA(
          allOf(
            isA<CoachChatApiException>(),
            isNot(isA<CoachChatQuotaExceededException>()),
          ),
        ),
      );
    });

    test('malformed progress stream fails once and never replays request',
        () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return http.Response(
          '{not-json}\n',
          200,
          headers: {'content-type': 'application/x-ndjson'},
        );
      });
      final service = CoachChatApiService(
        clientFactory: () => client,
        accessTokenProvider: () => 'access-token',
        progressStreamingEnabled: true,
      );

      await expectLater(
        service.ask(
          conversationId: 'c-1',
          partnerId: null,
          question: '我該怎麼回？',
          recentMessages: const [],
          dataQualityFlagged: false,
        ),
        throwsA(isA<CoachChatGenerationFailedException>()),
      );
      expect(calls, 1);
    });

    test('parses valid success response into a local result', () async {
      final service = CoachChatApiService(invoker: _stub(_ok()));

      final result = await service.ask(
        conversationId: 'c-1',
        partnerId: 'p-1',
        question: '她是什麼意思？',
        recentMessages: const [],
        dataQualityFlagged: false,
      );

      expect(result.conversationId, 'c-1');
      expect(result.partnerId, 'p-1');
      expect(result.question, '她是什麼意思？');
      expect(result.mode, 'replyCraft');
      expect(result.responseType, 'coachAnswer');
      expect(result.sessionId, 's-1');
      expect(result.frictionType, 'overPolishing');
      expect(result.rewriteDecision, 'light_edit');
      expect(result.costDeducted, 1);
      expect(result.provider, 'claude');
      expect(result.modelUsed, 'claude-sonnet-4-20250514');
      expect(result.generatedAt, DateTime.parse('2026-05-07T12:00:00.000Z'));
    });

    test('parses clarification response without cost deduction', () async {
      final service = CoachChatApiService(
        invoker: _stub(
          _ok(
            _validResponse(
              card: <String, dynamic>{
                'responseType': 'clarifyingQuestion',
                'mode': 'clarifyIntent',
                'headline': '先問清楚你的真實想法',
                'answer': '我先接住你：你不是沒答案，而是怕一回就失去分寸。',
                'userTruth': null,
                'userState': '你可能想推進，但還沒說出原本想回的句子。',
                'nextStep': '先補一句你心裡真正想怎麼回。',
                'suggestedLine': null,
                'rewriteDecision': null,
                'rewriteReason': null,
                'boundaryReminder': '補充釐清不扣額度；正式建議才扣 1 則。',
                'needsReflection': true,
                'reflectionQuestion': '你聽到她這句話後，心裡第一個反應是什麼？',
                'costDeducted': 0,
              },
            ),
          ),
        ),
      );

      final result = await service.ask(
        conversationId: 'c-1',
        partnerId: 'p-1',
        question: '她是什麼意思？',
        recentMessages: const [],
        dataQualityFlagged: false,
      );

      expect(result.isClarifyingQuestion, isTrue);
      expect(result.costDeducted, 0);
      expect(result.reflectionQuestion, contains('心裡第一個反應'));
    });

    test('defaults missing frictionType for older edge responses', () async {
      final service = CoachChatApiService(
        invoker: _stub(
          _ok(
            _validResponse(
              card: <String, dynamic>{
                'mode': 'replyCraft',
                'responseType': 'coachAnswer',
                'headline': '接住她的觀察',
                'answer': '她是在丟一個觀察，不是要你立刻證明自己。',
                'userTruth': '你想接住她的好奇，但不想裝深沉。',
                'userState': '你可能急著解釋，反而把輕鬆感弄重。',
                'nextStep': '承認一半，補一個畫面，再把球丟回她。',
                'suggestedLine': '被妳發現了。妳也是亂逛派嗎？',
                'rewriteDecision': 'light_edit',
                'rewriteReason': '保留原意，只補畫面與反問。',
                'boundaryReminder': '不要把一句觀察放大成考試。',
                'needsReflection': false,
                'reflectionQuestion': null,
                'costDeducted': 1,
              },
            ),
          ),
        ),
      );

      final result = await service.ask(
        conversationId: 'c-1',
        partnerId: 'p-1',
        question: '她是什麼意思？',
        recentMessages: const [],
        dataQualityFlagged: false,
      );

      expect(result.frictionType, 'unclearIntent');
    });

    test('throws quota exception on 429 and prefers server message', () async {
      final service = CoachChatApiService(
        invoker: _stub(
          const CoachChatInvokeResponse(
            status: 429,
            data: {
              'error': 'Daily limit exceeded',
              'message': 'server quota message',
              'used': 15,
              'limit': 15,
            },
          ),
        ),
      );

      expect(
        () => service.ask(
          conversationId: 'c-1',
          partnerId: 'p-1',
          question: '我還能問嗎？',
          recentMessages: const [],
          dataQualityFlagged: false,
        ),
        throwsA(isA<CoachChatQuotaExceededException>()),
      );
    });

    test('MODEL_RATE_LIMITED 429 不當 quota 例外（不得誤開 paywall）', () async {
      final service = CoachChatApiService(
        invoker: _stub(
          const CoachChatInvokeResponse(
            status: 429,
            data: {
              'error': 'Model rate limited',
              'code': 'MODEL_RATE_LIMITED',
              'message': '操作太頻繁，請稍等一分鐘再試。',
              'retryable': false,
            },
          ),
        ),
      );

      expect(
        () => service.ask(
          conversationId: 'c-1',
          partnerId: 'p-1',
          question: '我還能問嗎？',
          recentMessages: const [],
          dataQualityFlagged: false,
        ),
        throwsA(
          allOf(
            isNot(isA<CoachChatQuotaExceededException>()),
            isA<CoachChatApiException>()
                .having((e) => e.status, 'status', 429)
                .having((e) => e.message, 'message', contains('太頻繁')),
          ),
        ),
      );
    });

    test('quota exception exposes the server message', () async {
      final service = CoachChatApiService(
        invoker: _stub(
          const CoachChatInvokeResponse(
            status: 429,
            data: {
              'error': 'Daily limit exceeded',
              'message': 'server quota message',
              'used': 15,
              'limit': 15,
            },
          ),
        ),
      );

      try {
        await service.ask(
          conversationId: 'c-1',
          partnerId: 'p-1',
          question: 'should I reply?',
          recentMessages: const [],
          dataQualityFlagged: false,
        );
        fail('Expected CoachChatQuotaExceededException');
      } on CoachChatQuotaExceededException catch (e) {
        expect(e.message, 'server quota message');
        expect(e.code, 'DAILY_LIMIT_EXCEEDED');
        expect(e.used, 15);
        expect(e.limit, 15);
      }
    });

    test('throws generation failure when visible card contains banned token',
        () {
      final service = CoachChatApiService(
        invoker: _stub(
          _ok(
            _validResponse(
              card: <String, dynamic>{
                'mode': 'replyCraft',
                'headline': '不要用 PUA 框架',
                'answer': '這句不該出現在產品輸出。',
                'userState': '穩住。',
                'nextStep': '換成成熟語言。',
                'suggestedLine': null,
                'boundaryReminder': '尊重對方。',
                'needsReflection': false,
                'reflectionQuestion': null,
              },
            ),
          ),
        ),
      );

      expect(
        () => service.ask(
          conversationId: 'c-1',
          partnerId: 'p-1',
          question: '怎麼回？',
          recentMessages: const [],
          dataQualityFlagged: false,
        ),
        throwsA(isA<CoachChatGenerationFailedException>()),
      );
    });

    test('throws generation failure when required schema field is missing', () {
      final service = CoachChatApiService(
        invoker: _stub(
          _ok(
            _validResponse(
              card: <String, dynamic>{
                'mode': 'replyCraft',
                'headline': '缺欄位',
                'answer': '這張卡沒有邊界提醒。',
                'userState': '穩住。',
                'nextStep': '重試。',
                'needsReflection': false,
              },
            ),
          ),
        ),
      );

      expect(
        () => service.ask(
          conversationId: 'c-1',
          partnerId: 'p-1',
          question: '怎麼辦？',
          recentMessages: const [],
          dataQualityFlagged: false,
        ),
        throwsA(isA<CoachChatGenerationFailedException>()),
      );
    });
  });
}
