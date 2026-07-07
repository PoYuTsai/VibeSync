import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;
import 'package:vibesync/features/practice_chat/data/services/practice_chat_api_service.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_girl_catalog.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_hint.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_learning_mode.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_temperature.dart';

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

  /// 翻牌成功回應（draw 測試設定後由 mode==draw_profile 分支回傳）。
  Map<String, dynamic>? drawBody;
  Map<String, dynamic>? hintBody;

  Future<PracticeInvokeResponse> call(
    String fn, {
    required Map<String, dynamic> body,
  }) async {
    functionName = fn;
    this.body = body;
    if (body['mode'] == 'draw_profile') {
      return PracticeInvokeResponse(status: 200, data: drawBody ?? const {});
    }
    if (body['mode'] == 'hint') {
      return PracticeInvokeResponse(status: 200, data: hintBody ?? const {});
    }
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

  group('PracticeLearningMode', () {
    test('standard/beginner expose wireName and Traditional Chinese labels',
        () {
      expect(PracticeLearningMode.standard.wireName, 'standard');
      expect(PracticeLearningMode.standard.label, '練習');
      expect(PracticeLearningMode.beginner.wireName, 'beginner');
      expect(PracticeLearningMode.beginner.label, '新手');
    });

    test('fromWire falls back to standard for null or unknown values', () {
      expect(
          PracticeLearningMode.fromWire(null), PracticeLearningMode.standard);
      expect(
        PracticeLearningMode.fromWire('expert'),
        PracticeLearningMode.standard,
      );
      expect(
        PracticeLearningMode.fromWire('beginner'),
        PracticeLearningMode.beginner,
      );
    });
  });

  group('PracticeTemperature', () {
    test('wentUp and wentDown reflect delta direction', () {
      const warmer = PracticeTemperature(
        score: 38,
        delta: 8,
        band: 'cold',
        reason: '有接住話題',
      );
      const cooler = PracticeTemperature(
        score: 28,
        delta: -2,
        band: 'cold',
        reason: '回覆太短',
      );
      const flat = PracticeTemperature(
        score: 30,
        delta: 0,
        band: 'cold',
        reason: '維持',
      );

      expect(warmer.wentUp, true);
      expect(warmer.wentDown, false);
      expect(cooler.wentUp, false);
      expect(cooler.wentDown, true);
      expect(flat.wentUp, false);
      expect(flat.wentDown, false);
    });
  });

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
      expect(r.temperature, isNull);
    });

    test('sendMessage parses partnerState tracker payload', () async {
      final svc = serviceReturning(200, {
        'reply': '嗯？聽起來你今天很忙。',
        'aiTurnCount': 1,
        'sessionComplete': false,
        'costDeducted': 1,
        'partnerState': {
          'mood': 'curious',
          'innerThought': '他有回到我的情緒，我想多問一點。',
        },
      });

      final r =
          await svc.sendMessage(sessionId: 's', profile: profile, turns: turns);

      expect(r.partnerState?.mood, 'curious');
      expect(r.partnerState?.innerThought, '他有回到我的情緒，我想多問一點。');
    });

    test('sendMessage body includes default standard practiceMode', () async {
      final captured = _CapturedInvoke();
      final svc = PracticeChatApiService(invoker: captured.call);

      await svc.sendMessage(sessionId: 's', profile: profile, turns: turns);

      expect(captured.body?['practiceMode'], 'standard');
      expect(captured.body?.containsKey('temperatureScore'), false);
    });

    test('beginner sendMessage sends temperatureScore and parses temperature',
        () async {
      final captured = _CapturedInvoke();
      final svc = PracticeChatApiService(
        invoker: (fn, {required body}) async {
          captured.functionName = fn;
          captured.body = body;
          return const PracticeInvokeResponse(
            status: 200,
            data: {
              'reply': '可以先輕鬆接住她的關鍵字。',
              'aiTurnCount': 2,
              'sessionComplete': false,
              'costDeducted': 1,
              'hintUsedCount': 1,
              'temperature': {
                'score': 38,
                'delta': 8,
                'band': 'cold',
                'reason': '有具體延伸話題',
                'familiarityScore': 10,
                'familiarityDelta': 10,
                'stageLabel': '建立熟悉中',
              },
            },
          );
        },
      );

      final result = await svc.sendMessage(
        sessionId: 's',
        profile: profile,
        turns: turns,
        practiceMode: PracticeLearningMode.beginner,
        temperatureScore: 30,
        familiarityScore: 0,
      );

      expect(captured.body?['practiceMode'], 'beginner');
      expect(captured.body?['temperatureScore'], 30);
      expect(captured.body?['familiarityScore'], 0);
      expect(result.hintUsedCount, 1);
      expect(result.temperature?.score, 38);
      expect(result.temperature?.delta, 8);
      expect(result.temperature?.band, 'cold');
      expect(result.temperature?.reason, '有具體延伸話題');
      expect((result.temperature as dynamic).familiarityScore, 10);
      expect((result.temperature as dynamic).familiarityDelta, 10);
      expect((result.temperature as dynamic).stageLabel, '建立熟悉中');
    });

    test('sendMessage includes applied hint source when hint reply is used',
        () async {
      final captured = _CapturedInvoke();
      final svc = PracticeChatApiService(invoker: captured.call);

      await svc.sendMessage(
        sessionId: 's',
        profile: profile,
        turns: turns,
        practiceMode: PracticeLearningMode.beginner,
        temperatureScore: 30,
        appliedHintType: PracticeHintReplyType.warmUp,
        appliedHintText: 'original hint reply',
      );

      expect(captured.body?['appliedHintType'], 'warm_up');
      expect(captured.body?['appliedHintText'], 'original hint reply');
    });

    test('sendMessage trims appliedHintText before sending', () async {
      final captured = _CapturedInvoke();
      final svc = PracticeChatApiService(invoker: captured.call);

      await svc.sendMessage(
        sessionId: 's',
        profile: profile,
        turns: turns,
        practiceMode: PracticeLearningMode.beginner,
        temperatureScore: 30,
        appliedHintType: PracticeHintReplyType.steady,
        appliedHintText: '  original hint reply  ',
      );

      expect(captured.body?['appliedHintType'], 'steady');
      expect(captured.body?['appliedHintText'], 'original hint reply');
    });

    test('sendMessage omits blank appliedHintText', () async {
      final captured = _CapturedInvoke();
      final svc = PracticeChatApiService(invoker: captured.call);

      await svc.sendMessage(
        sessionId: 's',
        profile: profile,
        turns: turns,
        practiceMode: PracticeLearningMode.beginner,
        temperatureScore: 30,
        appliedHintType: PracticeHintReplyType.warmUp,
        appliedHintText: '   ',
      );

      expect(captured.body?['appliedHintType'], 'warm_up');
      expect(captured.body?.containsKey('appliedHintText'), false);
    });

    test('sendMessage omits appliedHintText without appliedHintType', () async {
      final captured = _CapturedInvoke();
      final svc = PracticeChatApiService(invoker: captured.call);

      await svc.sendMessage(
        sessionId: 's',
        profile: profile,
        turns: turns,
        practiceMode: PracticeLearningMode.beginner,
        temperatureScore: 30,
        appliedHintText: 'original hint reply',
      );

      expect(captured.body?.containsKey('appliedHintType'), false);
      expect(captured.body?.containsKey('appliedHintText'), false);
    });

    test('sendMessage omits appliedHintType when user did not apply hint',
        () async {
      final captured = _CapturedInvoke();
      final svc = PracticeChatApiService(invoker: captured.call);

      await svc.sendMessage(
        sessionId: 's',
        profile: profile,
        turns: turns,
        practiceMode: PracticeLearningMode.beginner,
        temperatureScore: 30,
      );

      expect(captured.body?.containsKey('appliedHintType'), false);
      expect(captured.body?.containsKey('appliedHintText'), false);
    });

    test('sendMessage omits appliedHintType outside beginner mode', () async {
      final captured = _CapturedInvoke();
      final svc = PracticeChatApiService(invoker: captured.call);

      await svc.sendMessage(
        sessionId: 's',
        profile: profile,
        turns: turns,
        practiceMode: PracticeLearningMode.standard,
        appliedHintType: PracticeHintReplyType.warmUp,
        appliedHintText: 'original hint reply',
      );

      expect(captured.body?.containsKey('appliedHintType'), false);
      expect(captured.body?.containsKey('appliedHintText'), false);
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

    test('MODEL_RATE_LIMITED 429 不當 quota 例外（不得誤導升級）', () async {
      final svc = serviceReturning(429, {
        'error': 'Model rate limited',
        'code': 'MODEL_RATE_LIMITED',
        'message': '操作太頻繁，請稍等一分鐘再試。',
        'retryable': false,
      });
      expect(
        () => svc.sendMessage(sessionId: 's', profile: profile, turns: turns),
        throwsA(
          allOf(
            isNot(isA<PracticeQuotaExceededException>()),
            isA<PracticeApiException>()
                .having((e) => e.status, 'status', 429)
                .having((e) => e.message, 'message', contains('太頻繁')),
          ),
        ),
      );
    });

    test('409 → PracticeSessionCompleteException', () async {
      final svc = serviceReturning(409, {'error': 'practice_session_complete'});
      expect(
        () => svc.sendMessage(sessionId: 's', profile: profile, turns: turns),
        throwsA(isA<PracticeSessionCompleteException>()),
      );
    });

    test('409 practice_mode_locked → PracticeModeLockedException（不是場次已滿）',
        () async {
      final svc = serviceReturning(409, {'error': 'practice_mode_locked'});
      expect(
        () => svc.sendMessage(sessionId: 's', profile: profile, turns: turns),
        throwsA(isA<PracticeModeLockedException>()),
      );
    });

    test('409 讀不到 body → 維持 PracticeSessionCompleteException', () async {
      final svc = serviceReturning(409, null);
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
      final svc =
          serviceReturning(500, {'error': 'practice_generation_failed'});
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
          'dateChance': 'high',
          'dateChanceReason': '她已經主動接住話題。',
          'nextInviteMove': '用模糊邀約測窗口。',
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
      expect(d.dateChance, 'high');
      expect(d.dateChanceReason, '她已經主動接住話題。');
      expect(d.nextInviteMove, '用模糊邀約測窗口。');
    });

    test('200 但缺 card → generation failed', () async {
      final svc = serviceReturning(200, {'costDeducted': 0});
      expect(
        () =>
            svc.requestDebrief(sessionId: 's', profile: profile, turns: turns),
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

  group('drawProfile', () {
    Map<String, dynamic> okBody() => {
          'profile': {
            'profileId': 'practice_girl_007',
            'nameId': 'mia',
            'professionId': 'nurse',
            'photoId': 'practice_girl_007',
            'personaId': 'cool_rational',
          },
          'draw': {
            'costMessages': 0,
            'freeAllowance': 3,
            'freeUsed': 1,
            'freeRemaining': 2,
            'extraCostMessages': 5,
            'nextResetAt': '2026-06-27T04:00:00.000Z',
          },
          'usage': {
            'monthlyUsed': 12,
            'monthlyLimit': 500,
            'dailyUsed': 3,
            'dailyLimit': 30,
          },
        };

    test('body 帶 mode/requestId/currentProfileId/visiblePracticeThreadId',
        () async {
      final captured = _CapturedInvoke();
      final svc = PracticeChatApiService(invoker: captured.call);
      captured.drawBody = okBody();

      await svc.drawProfile(
        requestId: 'req-1',
        currentProfileId: 'practice_girl_001',
        visiblePracticeThreadId: 'thread-9',
      );

      expect(captured.functionName, 'practice-chat');
      expect(captured.body?['mode'], 'draw_profile');
      expect(captured.body?['requestId'], 'req-1');
      expect(captured.body?['currentProfileId'], 'practice_girl_001');
      expect(captured.body?['visiblePracticeThreadId'], 'thread-9');
    });

    test('currentProfileId / visiblePracticeThreadId 為 null 時不放進 body',
        () async {
      final captured = _CapturedInvoke();
      final svc = PracticeChatApiService(invoker: captured.call);
      captured.drawBody = okBody();

      await svc.drawProfile(requestId: 'req-2');

      expect(captured.body?['requestId'], 'req-2');
      expect(captured.body?.containsKey('currentProfileId'), false);
      expect(captured.body?.containsKey('visiblePracticeThreadId'), false);
    });

    test('body 一律帶 catalogSize = client catalog 人數（server 切池相容 gate）',
        () async {
      final captured = _CapturedInvoke();
      final svc = PracticeChatApiService(invoker: captured.call);
      captured.drawBody = okBody();

      await svc.drawProfile(requestId: 'req-cs-1');

      // 不可硬編 100：catalog 擴充/回滾時 client 宣告值必須自動跟上。
      expect(captured.body?['catalogSize'], practiceGirlProfiles.length);
      expect(captured.body?['catalogSize'], isA<int>());
    });

    test('200 → 解析 profile / draw / usage', () async {
      final svc = serviceReturning(200, okBody());
      final r = await svc.drawProfile(requestId: 'req-3');

      expect(r.profile.profileId, 'practice_girl_007');
      expect(r.profile.nameId, 'mia');
      expect(r.profile.professionId, 'nurse');
      expect(r.profile.photoId, 'practice_girl_007');
      expect(r.profile.personaId, 'cool_rational');

      expect(r.draw.costMessages, 0);
      expect(r.draw.freeAllowance, 3);
      expect(r.draw.freeUsed, 1);
      expect(r.draw.freeRemaining, 2);
      expect(r.draw.extraCostMessages, 5);
      expect(r.draw.nextResetAt, '2026-06-27T04:00:00.000Z');

      expect(r.usage.monthlyUsed, 12);
      expect(r.usage.monthlyLimit, 500);
      expect(r.usage.dailyUsed, 3);
      expect(r.usage.dailyLimit, 30);
    });

    test('200 但缺 profile → generation failed', () async {
      final svc = serviceReturning(200, {'draw': {}, 'usage': {}});
      expect(
        () => svc.drawProfile(requestId: 'req-4'),
        throwsA(isA<PracticeGenerationFailedException>()),
      );
    });

    test('402 → PracticeDrawUpgradeRequiredException 帶 allowance/成本/重置時間',
        () async {
      final svc = serviceReturning(402, {
        'error': 'practice_draw_upgrade_required',
        'message': '升級後每天可以翻更多陪練女孩。',
        'draw': {
          'freeAllowance': 1,
          'freeUsed': 1,
          'freeRemaining': 0,
          'extraCostMessages': 5,
          'nextResetAt': '2026-06-27T04:00:00.000Z',
        },
      });
      expect(
        () => svc.drawProfile(requestId: 'req-5'),
        throwsA(isA<PracticeDrawUpgradeRequiredException>()
            .having((e) => e.freeAllowance, 'freeAllowance', 1)
            .having((e) => e.extraCostMessages, 'extraCostMessages', 5)
            .having((e) => e.nextResetAt, 'nextResetAt',
                '2026-06-27T04:00:00.000Z')),
      );
    });

    test('429 → PracticeQuotaExceededException 帶剩餘額度', () async {
      final svc = serviceReturning(429, {
        'message': '本月額度已用完',
        'used': 500,
        'limit': 500,
        'monthlyRemaining': 0,
        'dailyRemaining': 0,
      });
      expect(
        () => svc.drawProfile(requestId: 'req-6'),
        throwsA(isA<PracticeQuotaExceededException>()
            .having((e) => e.monthlyRemaining, 'monthlyRemaining', 0)),
      );
    });

    test('500 → PracticeGenerationFailedException', () async {
      final svc = serviceReturning(500, {'error': 'draw_failed'});
      expect(
        () => svc.drawProfile(requestId: 'req-7'),
        throwsA(isA<PracticeGenerationFailedException>()),
      );
    });

    test('403 無訂閱 → PracticeApiException', () async {
      final svc = serviceReturning(403, {'error': 'No subscription found'});
      expect(
        () => svc.drawProfile(requestId: 'req-8'),
        throwsA(isA<PracticeApiException>()),
      );
    });
  });

  // functions_client 2.5.0 的 invoke 對非 2xx 一律 throw FunctionException
  // （status + details＝decode 後的 body），不會回 FunctionResponse。service 必須
  // 接住並餵進既有 status→typed exception 映射，否則 402/429 分支是死碼、
  // 一律落到 catch-all 顯示通用錯誤。
  group('FunctionException（functions_client 非 2xx throw）映射', () {
    PracticeChatApiService serviceThrowing(FunctionException e) {
      return PracticeChatApiService(
        invoker: (fn, {required body}) async => throw e,
      );
    }

    test(
        'drawProfile：402 practice_draw_upgrade_required → PracticeDrawUpgradeRequiredException',
        () async {
      final svc = serviceThrowing(const FunctionException(
        status: 402,
        details: {
          'error': 'practice_draw_upgrade_required',
          'message': '升級後每天可以翻更多陪練女孩。',
          'draw': {
            'freeAllowance': 1,
            'freeUsed': 1,
            'freeRemaining': 0,
            'extraCostMessages': 0,
            'nextResetAt': '2026-07-05T04:00:00.000Z',
          },
        },
      ));
      await expectLater(
        svc.drawProfile(requestId: 'req-fx-1'),
        throwsA(isA<PracticeDrawUpgradeRequiredException>()
            .having((e) => e.freeAllowance, 'freeAllowance', 1)
            .having((e) => e.extraCostMessages, 'extraCostMessages', 0)
            .having((e) => e.nextResetAt, 'nextResetAt',
                '2026-07-05T04:00:00.000Z')),
      );
    });

    test('drawProfile：429 quota body → PracticeQuotaExceededException',
        () async {
      final svc = serviceThrowing(const FunctionException(
        status: 429,
        details: {
          'error': 'Daily limit exceeded',
          'message': '今日額度已用完',
          'used': 50,
          'limit': 50,
          'monthlyRemaining': 10,
          'dailyRemaining': 0,
        },
      ));
      await expectLater(
        svc.drawProfile(requestId: 'req-fx-2'),
        throwsA(isA<PracticeQuotaExceededException>()
            .having((e) => e.dailyRemaining, 'dailyRemaining', 0)
            .having((e) => e.message, 'message', '今日額度已用完')),
      );
    });

    test('drawProfile：details 非 Map（如純文字 body）→ 仍走 402 映射不炸', () async {
      final svc = serviceThrowing(const FunctionException(
        status: 402,
        details: 'Payment Required',
      ));
      await expectLater(
        svc.drawProfile(requestId: 'req-fx-3'),
        throwsA(isA<PracticeDrawUpgradeRequiredException>()),
      );
    });

    test('drawProfile：500 → PracticeGenerationFailedException（不 rotate 語意不變）',
        () async {
      final svc = serviceThrowing(const FunctionException(status: 500));
      await expectLater(
        svc.drawProfile(requestId: 'req-fx-4'),
        throwsA(isA<PracticeGenerationFailedException>()),
      );
    });

    test('sendMessage：402 upgrade_required → PracticeUpgradeRequiredException',
        () async {
      final svc = serviceThrowing(const FunctionException(
        status: 402,
        details: {'error': 'upgrade_required'},
      ));
      await expectLater(
        svc.sendMessage(sessionId: 's1', profile: profile, turns: turns),
        throwsA(isA<PracticeUpgradeRequiredException>()),
      );
    });

    test(
        'sendMessage：429 MODEL_RATE_LIMITED → PracticeApiException（絕不誤標 quota）',
        () async {
      final svc = serviceThrowing(const FunctionException(
        status: 429,
        details: {
          'code': 'MODEL_RATE_LIMITED',
          'message': '請求太頻繁，請稍後再試。',
        },
      ));
      await expectLater(
        svc.sendMessage(sessionId: 's1', profile: profile, turns: turns),
        throwsA(isA<PracticeApiException>()
            .having((e) => e.status, 'status', 429)
            .having((e) => e.message, 'message', '請求太頻繁，請稍後再試。')),
      );
    });
  });

  group('requestHint', () {
    Map<String, dynamic> okHintBody() => {
          'replies': [
            {
              'type': 'warm_up',
              'label': '升溫回覆',
              'text': '那我先查朧月。你如果只推一道，會推熟成魚還是酒單？',
            },
            {
              'type': 'steady',
              'label': '穩住回覆',
              'text': '好，我自己查。你剛剛提到酒單，看起來你蠻懂這類店。',
            },
          ],
          'coaching': '先接住資訊，再問一個具體但低壓力的問題。',
          'costDeducted': 1,
          'hintUsedCount': 2,
          'monthlyRemaining': 28,
          'dailyRemaining': 13,
        };

    test('sends hint mode, beginner practiceMode, turns/profile/metadata',
        () async {
      final captured = _CapturedInvoke();
      final svc = PracticeChatApiService(invoker: captured.call);
      captured.hintBody = okHintBody();

      await svc.requestHint(
        sessionId: 'session-1',
        profile: const PracticeProfileDto(
          personaId: 'cool_rational',
          difficulty: 'challenge',
          profileId: 'practice_girl_007',
          nameId: 'mia',
          professionId: 'nurse',
          photoId: 'practice_girl_007',
        ),
        turns: turns,
        roundIndex: 4,
        visiblePracticeThreadId: 'thread-abc',
      );

      expect(captured.functionName, 'practice-chat');
      expect(captured.body?['mode'], 'hint');
      expect(captured.body?['practiceMode'], 'beginner');
      expect(captured.body?['sessionId'], 'session-1');
      expect(captured.body?['personaId'], 'cool_rational');
      expect(captured.body?['difficulty'], 'challenge');
      expect(captured.body?['profileId'], 'practice_girl_007');
      expect(captured.body?['nameId'], 'mia');
      expect(captured.body?['professionId'], 'nurse');
      expect(captured.body?['photoId'], 'practice_girl_007');
      expect(captured.body?['turns'], [
        {'role': 'user', 'text': '嗨'},
      ]);
      expect(captured.body?['roundIndex'], 4);
      expect(captured.body?['visiblePracticeThreadId'], 'thread-abc');
    });

    test('sendMessage body includes memorySummary when provided', () async {
      final captured = _CapturedInvoke();
      final svc = PracticeChatApiService(invoker: captured.call);

      await svc.sendMessage(
        sessionId: 's',
        profile: profile,
        turns: turns,
        memorySummary: '更早聊過咖啡、論文與朋友聚餐',
      );

      expect(captured.body?['memorySummary'], '更早聊過咖啡、論文與朋友聚餐');
    });

    test('body 帶 client 產的 requestId（扣費 idempotency）', () async {
      final captured = _CapturedInvoke();
      final svc = PracticeChatApiService(invoker: captured.call);
      captured.hintBody = okHintBody();

      await svc.requestHint(
        sessionId: 'session-1',
        requestId: 'hint-req-1',
        profile: profile,
        turns: turns,
      );

      expect(captured.body?['requestId'], 'hint-req-1');
    });

    test('parses two replies, coaching, cost, hint count, and remaining counts',
        () async {
      final svc = serviceReturning(200, okHintBody());

      final result = await svc.requestHint(
        sessionId: 'session-1',
        profile: profile,
        turns: turns,
      );

      expect(result.replies, hasLength(2));
      expect(result.replies[0].type, PracticeHintReplyType.warmUp);
      expect(result.replies[0].label, '升溫回覆');
      expect(result.replies[0].text, contains('朧月'));
      expect(result.replies[1].type, PracticeHintReplyType.steady);
      expect(result.replies[1].label, '穩住回覆');
      expect(result.replies[1].text, contains('酒單'));
      expect(result.coaching, '先接住資訊，再問一個具體但低壓力的問題。');
      expect(result.costDeducted, 1);
      expect(result.hintUsedCount, 2);
      expect(result.monthlyRemaining, 28);
      expect(result.dailyRemaining, 13);
    });

    test('429 maps to PracticeQuotaExceededException', () async {
      final svc = serviceReturning(429, {
        'message': '本月額度已用完',
        'monthlyRemaining': 0,
        'dailyRemaining': 0,
      });

      expect(
        () => svc.requestHint(
          sessionId: 'session-1',
          profile: profile,
          turns: turns,
        ),
        throwsA(isA<PracticeQuotaExceededException>()),
      );
    });

    test('409 practice_mode_locked maps to PracticeModeLockedException',
        () async {
      final svc = serviceReturning(409, {'error': 'practice_mode_locked'});

      expect(
        () => svc.requestHint(
          sessionId: 'session-1',
          profile: profile,
          turns: turns,
        ),
        throwsA(isA<PracticeModeLockedException>()),
      );
    });

    test('403 practice_hint_limit maps to PracticeHintLimitException',
        () async {
      final svc = serviceReturning(403, {'error': 'practice_hint_limit'});

      expect(
        () => svc.requestHint(
          sessionId: 'session-1',
          profile: profile,
          turns: turns,
        ),
        throwsA(isA<PracticeHintLimitException>()),
      );
    });

    test('500 keeps hint readiness error code for controller copy', () async {
      final svc = serviceReturning(500, {'error': 'practice_hint_not_ready'});

      expect(
        () => svc.requestHint(
          sessionId: 'session-1',
          profile: profile,
          turns: turns,
        ),
        throwsA(
          isA<PracticeGenerationFailedException>()
              .having((e) => e.message, 'message', 'practice_hint_not_ready'),
        ),
      );
    });

    test('malformed response maps to PracticeGenerationFailedException',
        () async {
      final svc = serviceReturning(200, {
        'replies': [
          {'type': 'warmUp', 'label': '升溫回覆', 'text': '只有一則'},
        ],
        'coaching': '少一則回覆',
      });

      expect(
        () => svc.requestHint(
          sessionId: 'session-1',
          profile: profile,
          turns: turns,
        ),
        throwsA(isA<PracticeGenerationFailedException>()),
      );
    });
  });

  group('continuation metadata (roundIndex / visiblePracticeThreadId)', () {
    test('sendMessage body includes continuationPartnerState when provided',
        () async {
      final captured = _CapturedInvoke();
      final svc = PracticeChatApiService(invoker: captured.call);

      await svc.sendMessage(
        sessionId: 's',
        profile: profile,
        turns: turns,
        continuationPartnerState: const PracticePartnerState(
          mood: 'guarded',
          innerThought: '他剛剛有點急，我想先看他穩不穩。',
        ),
      );

      expect(captured.body?['continuationPartnerState'], {
        'mood': 'guarded',
        'innerThought': '他剛剛有點急，我想先看他穩不穩。',
      });
    });

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

    test('hint and debrief body include memorySummary when provided', () async {
      final captured = _CapturedInvoke();
      final svc = PracticeChatApiService(invoker: captured.call);
      captured.hintBody = {
        'replies': [
          {
            'type': 'warm_up',
            'label': '升溫回覆',
            'text': '先接住她的狀態。',
          },
          {
            'type': 'steady',
            'label': '穩住回覆',
            'text': '延續前面咖啡話題。',
          },
        ],
        'coaching': '用舊脈絡做自然承接',
        'costDeducted': 1,
        'hintUsedCount': 1,
      };

      await svc.requestHint(
        sessionId: 's',
        profile: profile,
        turns: const [
          PracticeTurnDto(role: 'user', text: 'hi'),
          PracticeTurnDto(role: 'ai', text: 'hello'),
        ],
        memorySummary: '更早她說喜歡巷口咖啡',
      );
      expect(captured.body?['memorySummary'], '更早她說喜歡巷口咖啡');

      await svc.requestDebrief(
        sessionId: 's',
        profile: profile,
        turns: const [
          PracticeTurnDto(role: 'user', text: 'hi'),
          PracticeTurnDto(role: 'ai', text: 'hello'),
        ],
        memorySummary: '更早她說喜歡巷口咖啡',
      );
      expect(captured.body?['memorySummary'], '更早她說喜歡巷口咖啡');
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
