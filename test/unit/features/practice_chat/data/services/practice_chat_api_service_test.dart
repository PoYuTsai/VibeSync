import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/practice_chat/data/services/practice_chat_api_service.dart';

PracticeChatApiService serviceReturning(int status, dynamic data) {
  return PracticeChatApiService(
    invoker: (fn, {required body}) async =>
        PracticeInvokeResponse(status: status, data: data),
  );
}

/// 攔截送出的 functionName 與 body，用來驗證有把 persona/difficulty 帶進請求。
class _CapturedInvoke {
  String? functionName;
  Map<String, dynamic>? body;

  Future<PracticeInvokeResponse> call(
    String fn, {
    required Map<String, dynamic> body,
  }) async {
    functionName = fn;
    this.body = body;
    if (body['mode'] == 'debrief') {
      return const PracticeInvokeResponse(
        status: 200,
        data: {
          'card': {
            'summary': '有來有回，但可以少一點查戶口。',
            'strengths': ['有接到她的情緒'],
            'watchouts': ['問題略連續'],
            'suggestedLine': '哈哈你今天感覺真的很滿，我先不吵你。',
            'vibe': '自然',
          },
          'costDeducted': 0,
        },
      );
    }
    return const PracticeInvokeResponse(
      status: 200,
      data: {
        'reply': '嗯？',
        'aiTurnCount': 1,
        'sessionComplete': false,
        'costDeducted': 1,
      },
    );
  }
}

void main() {
  final turns = [const PracticeTurnDto(role: 'user', text: '嗨')];
  const profile =
      PracticeProfileDto(personaId: 'slow_worker', difficulty: 'normal');

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
      final r =
          await svc.sendMessage(sessionId: 's', profile: profile, turns: turns);
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
        () => svc.sendMessage(sessionId: 's', profile: profile, turns: turns),
        throwsA(isA<PracticeQuotaExceededException>()
            .having((e) => e.monthlyRemaining, 'monthlyRemaining', 0)),
      );
    });

    test('409 → PracticeSessionCompleteException', () async {
      final svc = serviceReturning(409, {'error': 'practice_session_complete'});
      expect(
        () => svc.sendMessage(sessionId: 's', profile: profile, turns: turns),
        throwsA(isA<PracticeSessionCompleteException>()),
      );
    });

    test('402 upgrade_required → PracticeUpgradeRequiredException（導向付費牆）',
        () async {
      final svc = serviceReturning(402, {'error': 'upgrade_required'});
      expect(
        () => svc.sendMessage(sessionId: 's', profile: profile, turns: turns),
        throwsA(isA<PracticeUpgradeRequiredException>()),
      );
    });

    test('500 → PracticeGenerationFailedException（不扣額度語意）', () async {
      final svc = serviceReturning(500, {'error': 'practice_generation_failed'});
      expect(
        () => svc.sendMessage(sessionId: 's', profile: profile, turns: turns),
        throwsA(isA<PracticeGenerationFailedException>()),
      );
    });

    test('400 → PracticeApiException', () async {
      final svc = serviceReturning(400, {'error': 'invalid_mode'});
      expect(
        () => svc.sendMessage(sessionId: 's', profile: profile, turns: turns),
        throwsA(isA<PracticeApiException>()),
      );
    });

    test('200 但 data 非 map → generation failed', () async {
      final svc = serviceReturning(200, 'oops');
      expect(
        () => svc.sendMessage(sessionId: 's', profile: profile, turns: turns),
        throwsA(isA<PracticeGenerationFailedException>()),
      );
    });

    test('200 但 reply 空白字串 → generation failed（不渲染空泡泡）', () async {
      final svc = serviceReturning(200, {
        'reply': '   ',
        'aiTurnCount': 1,
        'sessionComplete': false,
        'costDeducted': 1,
      });
      expect(
        () => svc.sendMessage(sessionId: 's', profile: profile, turns: turns),
        throwsA(isA<PracticeGenerationFailedException>()),
      );
    });

    test('200 但 reply 非字串 → generation failed', () async {
      final svc = serviceReturning(200, {'reply': 42, 'aiTurnCount': 1});
      expect(
        () => svc.sendMessage(sessionId: 's', profile: profile, turns: turns),
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
      final d = await svc.requestDebrief(
          sessionId: 's', profile: profile, turns: turns);
      expect(d.summary, '整體有來有往');
      expect(d.strengths, ['開場自然']);
      expect(d.watchouts, ['問句太密']);
      expect(d.suggestedLine, '週末一起去？');
      expect(d.vibe, '中性');
    });

    test('200 但缺 card → generation failed', () async {
      final svc = serviceReturning(200, {'costDeducted': 0});
      expect(
        () => svc.requestDebrief(
            sessionId: 's', profile: profile, turns: turns),
        throwsA(isA<PracticeGenerationFailedException>()),
      );
    });
  });

  group('profile metadata', () {
    test('sendMessage body includes personaId and difficulty', () async {
      final captured = _CapturedInvoke();
      final svc = PracticeChatApiService(invoker: captured.call);

      await svc.sendMessage(
        sessionId: 's',
        profile: const PracticeProfileDto(
          personaId: 'teasing_humor',
          difficulty: 'challenge',
        ),
        turns: turns,
      );

      expect(captured.functionName, 'practice-chat');
      expect(captured.body?['personaId'], 'teasing_humor');
      expect(captured.body?['difficulty'], 'challenge');
    });

    test('requestDebrief body includes personaId and difficulty', () async {
      final captured = _CapturedInvoke();
      final svc = PracticeChatApiService(invoker: captured.call);

      await svc.requestDebrief(
        sessionId: 's',
        profile: const PracticeProfileDto(
          personaId: 'cool_rational',
          difficulty: 'normal',
        ),
        turns: turns,
      );

      expect(captured.functionName, 'practice-chat');
      expect(captured.body?['mode'], 'debrief');
      expect(captured.body?['personaId'], 'cool_rational');
      expect(captured.body?['difficulty'], 'normal');
    });

    test('帶身份時 body 含 profileId/nameId/professionId/photoId', () async {
      final captured = _CapturedInvoke();
      final svc = PracticeChatApiService(invoker: captured.call);

      await svc.sendMessage(
        sessionId: 's',
        profile: const PracticeProfileDto(
          personaId: 'slow_worker',
          difficulty: 'normal',
          profileId: 'practice_girl_001',
          nameId: 'alice',
          professionId: 'flight_attendant',
          photoId: 'practice_girl_001',
        ),
        turns: turns,
      );

      expect(captured.body?['profileId'], 'practice_girl_001');
      expect(captured.body?['nameId'], 'alice');
      expect(captured.body?['professionId'], 'flight_attendant');
      expect(captured.body?['photoId'], 'practice_girl_001');
    });

    test('未帶身份（舊路徑）→ body 不含 profileId 等鍵', () async {
      final captured = _CapturedInvoke();
      final svc = PracticeChatApiService(invoker: captured.call);

      await svc.sendMessage(sessionId: 's', profile: profile, turns: turns);

      expect(captured.body?.containsKey('profileId'), false);
      expect(captured.body?.containsKey('nameId'), false);
      expect(captured.body?.containsKey('professionId'), false);
      expect(captured.body?.containsKey('photoId'), false);
    });
  });

  group('continuation metadata (roundIndex / visiblePracticeThreadId)', () {
    test('sendMessage body includes roundIndex and visiblePracticeThreadId',
        () async {
      final captured = _CapturedInvoke();
      final svc = PracticeChatApiService(invoker: captured.call);

      await svc.sendMessage(
        sessionId: 's',
        profile: profile,
        turns: turns,
        roundIndex: 2,
        visiblePracticeThreadId: 'thread-abc',
      );

      expect(captured.body?['roundIndex'], 2);
      expect(captured.body?['visiblePracticeThreadId'], 'thread-abc');
    });

    test('requestDebrief body includes roundIndex and visiblePracticeThreadId',
        () async {
      final captured = _CapturedInvoke();
      final svc = PracticeChatApiService(invoker: captured.call);

      await svc.requestDebrief(
        sessionId: 's',
        profile: profile,
        turns: turns,
        roundIndex: 3,
        visiblePracticeThreadId: 'thread-xyz',
      );

      expect(captured.body?['roundIndex'], 3);
      expect(captured.body?['visiblePracticeThreadId'], 'thread-xyz');
    });

    test('roundIndex 缺值 → 預設 1；visiblePracticeThreadId 為 null 時不放進 body',
        () async {
      final captured = _CapturedInvoke();
      final svc = PracticeChatApiService(invoker: captured.call);

      await svc.sendMessage(sessionId: 's', profile: profile, turns: turns);

      expect(captured.body?['roundIndex'], 1);
      expect(captured.body?.containsKey('visiblePracticeThreadId'), false);
    });
  });
}
