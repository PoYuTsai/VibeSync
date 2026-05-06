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
          'headline': '接住她的觀察',
          'answer': '她是在丟一個觀察，不是要你立刻證明自己。',
          'userState': '你可能急著解釋，反而把輕鬆感弄重。',
          'nextStep': '承認一半，補一個畫面，再把球丟回她。',
          'suggestedLine': '被妳發現了，我會在飲料櫃前思考人生。妳也是亂逛派嗎？',
          'boundaryReminder': '不要把一句觀察放大成考試。',
          'needsReflection': false,
          'reflectionQuestion': null,
        },
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
        question: ' 她這句話是真的有興趣嗎？ ',
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
      expect(calls.single.body['userQuestion'], '她這句話是真的有興趣嗎？');
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
  });

  group('CoachChatApiService response contract', () {
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
      expect(result.provider, 'claude');
      expect(result.modelUsed, 'claude-sonnet-4-20250514');
      expect(result.generatedAt, DateTime.parse('2026-05-07T12:00:00.000Z'));
    });

    test('throws quota exception on 429', () async {
      final service = CoachChatApiService(
        invoker: _stub(
          const CoachChatInvokeResponse(
            status: 429,
            data: {'error': 'quota_exceeded', 'used': 15, 'limit': 15},
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
