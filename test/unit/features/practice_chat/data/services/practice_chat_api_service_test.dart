import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/practice_chat/data/services/practice_chat_api_service.dart';

PracticeChatApiService serviceReturning(int status, dynamic data) {
  return PracticeChatApiService(
    invoker: (fn, {required body}) async =>
        PracticeInvokeResponse(status: status, data: data),
  );
}

void main() {
  final turns = [const PracticeTurnDto(role: 'user', text: '嗨')];

  group('sendMessage', () {
    test('200 → 解析 reply / 計數 / 額度', () async {
      final svc = serviceReturning(200, {
        'reply': '嗯？幹嘛',
        'aiTurnCount': 1,
        'sessionComplete': false,
        'costDeducted': 1,
        'monthlyRemaining': 29,
        'dailyRemaining': 14,
      });
      final r = await svc.sendMessage(sessionId: 's', turns: turns);
      expect(r.reply, '嗯？幹嘛');
      expect(r.aiTurnCount, 1);
      expect(r.sessionComplete, false);
      expect(r.costDeducted, 1);
      expect(r.monthlyRemaining, 29);
      expect(r.dailyRemaining, 14);
    });

    test('429 → PracticeQuotaExceededException 帶剩餘額度', () async {
      final svc = serviceReturning(429, {
        'message': '本月額度已用完',
        'used': 30,
        'limit': 30,
        'monthlyRemaining': 0,
        'dailyRemaining': 0,
      });
      expect(
        () => svc.sendMessage(sessionId: 's', turns: turns),
        throwsA(isA<PracticeQuotaExceededException>()
            .having((e) => e.monthlyRemaining, 'monthlyRemaining', 0)),
      );
    });

    test('409 → PracticeSessionCompleteException', () async {
      final svc = serviceReturning(409, {'error': 'practice_session_complete'});
      expect(
        () => svc.sendMessage(sessionId: 's', turns: turns),
        throwsA(isA<PracticeSessionCompleteException>()),
      );
    });

    test('500 → PracticeGenerationFailedException（不扣額度語意）', () async {
      final svc = serviceReturning(500, {'error': 'practice_generation_failed'});
      expect(
        () => svc.sendMessage(sessionId: 's', turns: turns),
        throwsA(isA<PracticeGenerationFailedException>()),
      );
    });

    test('400 → PracticeApiException', () async {
      final svc = serviceReturning(400, {'error': 'invalid_mode'});
      expect(
        () => svc.sendMessage(sessionId: 's', turns: turns),
        throwsA(isA<PracticeApiException>()),
      );
    });

    test('200 但 data 非 map → generation failed', () async {
      final svc = serviceReturning(200, 'oops');
      expect(
        () => svc.sendMessage(sessionId: 's', turns: turns),
        throwsA(isA<PracticeGenerationFailedException>()),
      );
    });
  });

  group('requestDebrief', () {
    test('200 → 解析教練拆解卡', () async {
      final svc = serviceReturning(200, {
        'card': {
          'summary': '整體有來有往',
          'strengths': ['開場自然'],
          'watchouts': ['問句太密'],
          'suggestedLine': '週末一起去？',
          'vibe': '中性',
        },
        'costDeducted': 0,
        'monthlyRemaining': 29,
        'dailyRemaining': 14,
      });
      final d = await svc.requestDebrief(sessionId: 's', turns: turns);
      expect(d.summary, '整體有來有往');
      expect(d.strengths, ['開場自然']);
      expect(d.watchouts, ['問句太密']);
      expect(d.suggestedLine, '週末一起去？');
      expect(d.vibe, '中性');
    });

    test('200 但缺 card → generation failed', () async {
      final svc = serviceReturning(200, {'costDeducted': 0});
      expect(
        () => svc.requestDebrief(sessionId: 's', turns: turns),
        throwsA(isA<PracticeGenerationFailedException>()),
      );
    });
  });
}
