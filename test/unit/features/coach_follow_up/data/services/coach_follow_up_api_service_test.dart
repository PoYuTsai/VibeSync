// Spec 5 C19 — CoachFollowUpApiService TDD spec.
//
// Edge contract reference: supabase/functions/coach-follow-up/schemas.ts
//   - request: { phase, answers{q1, q2?, q3?}, partnerHint?, styleContext? }
//   - response 200: { phase, card, model, generatedAt }
//   - 400 invalid input / 429 quota / 5xx AI or deduct failure
//
// This service is the SOLE Flutter→Edge wire for coach-follow-up. It must:
//   1. consume the C17 partnerHint helper output verbatim (never rebuild inline)
//   2. send `phase` as stable English key (CoachFollowUpPhase.name)
//   3. inject partnerId + phase into the parsed CoachFollowUpResult client-side
//   4. enforce boundaryReminder non-null AND banned-token assertCardSafe as a
//      defense-in-depth guard (Edge already enforces, but client double-checks
//      so a corrupted/replayed response cannot reach the UI / Hive box)

import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/entities/game_stage.dart';
import 'package:vibesync/features/coach_follow_up/data/services/coach_follow_up_api_service.dart';
import 'package:vibesync/features/coach_follow_up/domain/entities/coach_follow_up_phase.dart';
import 'package:vibesync/features/coach_follow_up/domain/services/coach_follow_up_partner_hint_builder.dart';

// ── Test helpers ──────────────────────────────────────────────────────────

class _Recorded {
  final String fn;
  final Map<String, dynamic> body;
  _Recorded(this.fn, this.body);
}

CoachFollowUpInvoker _stub(
  CoachFollowUpInvokeResponse response, {
  List<_Recorded>? recorder,
}) {
  return (String fn, {required Map<String, dynamic> body}) async {
    recorder?.add(_Recorded(fn, body));
    return response;
  };
}

Map<String, dynamic> _validCardData({
  String phase = 'prepareInvite',
  String headline = '主動提一次',
  String observation = '她回應變短但仍在線',
  String task = '給一個輕量提案',
  String? suggestedLine = '週六下午這家咖啡廳？',
  String boundaryReminder = '若她沒回，48 小時內不再追問',
  String model = 'claude-sonnet-4-20250514',
  String generatedAt = '2026-05-02T18:30:00.000Z',
}) {
  return <String, dynamic>{
    'phase': phase,
    'card': <String, dynamic>{
      'headline': headline,
      'observation': observation,
      'task': task,
      'suggestedLine': suggestedLine,
      'boundaryReminder': boundaryReminder,
    },
    'model': model,
    'generatedAt': generatedAt,
  };
}

CoachFollowUpInvokeResponse _ok([Map<String, dynamic>? data]) =>
    CoachFollowUpInvokeResponse(status: 200, data: data ?? _validCardData());

CoachFollowUpAnswers _answers({
  String q1 = 'fuzzy',
  String? q2,
  String? q3,
}) =>
    CoachFollowUpAnswers(q1: q1, q2: q2, q3: q3);

// Build a hint via the C17 helper directly so the test asserts the wire
// payload comes from the helper, not a hand-rolled map.
CoachFollowUpPartnerHint _hintFromHelper(
    {GameStage? gameStage, int? heatScore}) {
  return CoachFollowUpPartnerHint(
    name: 'Mia',
    heatScore: heatScore,
    gameStage: gameStage?.name,
    lastConversationSummary: '上次聊到她想去九份',
  );
}

void main() {
  group('CoachFollowUpApiService — request shape', () {
    test('calls the coach-follow-up Edge function name', () async {
      final calls = <_Recorded>[];
      final service =
          CoachFollowUpApiService(invoker: _stub(_ok(), recorder: calls));

      await service.generate(
        partnerId: 'p-1',
        phase: CoachFollowUpPhase.prepareInvite,
        answers: _answers(),
      );

      expect(calls, hasLength(1));
      expect(calls.single.fn, 'coach-follow-up');
    });

    test('sends phase as stable English key (.name), not 繁中 displayLabel',
        () async {
      final calls = <_Recorded>[];
      final service =
          CoachFollowUpApiService(invoker: _stub(_ok(), recorder: calls));

      await service.generate(
        partnerId: 'p-1',
        phase: CoachFollowUpPhase.preDateReminder,
        answers: _answers(),
      );

      expect(calls.single.body['phase'], 'preDateReminder');
      expect(calls.single.body['phase'], isNot(contains('提醒')));
    });

    test('sends q1 always, omits q2/q3 keys entirely when null', () async {
      final calls = <_Recorded>[];
      final service =
          CoachFollowUpApiService(invoker: _stub(_ok(), recorder: calls));

      await service.generate(
        partnerId: 'p-1',
        phase: CoachFollowUpPhase.prepareInvite,
        answers: _answers(q1: 'fuzzy'),
      );

      final body = calls.single.body;
      expect(body['answers'], {'q1': 'fuzzy'});
      expect((body['answers'] as Map).containsKey('q2'), isFalse);
      expect((body['answers'] as Map).containsKey('q3'), isFalse);
    });

    test('sends q2 + q3 when caller provides them', () async {
      final calls = <_Recorded>[];
      final service =
          CoachFollowUpApiService(invoker: _stub(_ok(), recorder: calls));

      await service.generate(
        partnerId: 'p-1',
        phase: CoachFollowUpPhase.postDateReflection,
        answers: _answers(q1: 'proactive', q2: 'meta', q3: '想再見一次'),
      );

      expect(calls.single.body['answers'], {
        'q1': 'proactive',
        'q2': 'meta',
        'q3': '想再見一次',
      });
    });

    test('forwards partnerHint helper output verbatim (no inline rebuild)',
        () async {
      final calls = <_Recorded>[];
      final service =
          CoachFollowUpApiService(invoker: _stub(_ok(), recorder: calls));

      final hint = _hintFromHelper(
        gameStage: GameStage.qualification,
        heatScore: 72,
      );

      await service.generate(
        partnerId: 'p-1',
        phase: CoachFollowUpPhase.prepareInvite,
        answers: _answers(),
        partnerHint: hint,
      );

      // The wire body MUST be a 1:1 mirror of the C17 helper's value object.
      // Any divergence here means the API service rebuilt the hint inline,
      // breaking the privacy contract that says the helper is the only place
      // allowed to shape this payload.
      expect(calls.single.body['partnerHint'], {
        'name': 'Mia',
        'heatScore': 72,
        'gameStage': 'qualification',
        'lastConversationSummary': '上次聊到她想去九份',
      });
    });

    test(
        'omits null fields from partnerHint payload (Edge schema is .optional)',
        () async {
      final calls = <_Recorded>[];
      final service =
          CoachFollowUpApiService(invoker: _stub(_ok(), recorder: calls));

      const hint = CoachFollowUpPartnerHint(
        name: 'Mia',
      );

      await service.generate(
        partnerId: 'p-1',
        phase: CoachFollowUpPhase.prepareInvite,
        answers: _answers(),
        partnerHint: hint,
      );

      expect(calls.single.body['partnerHint'], {'name': 'Mia'});
    });

    test('omits partnerHint key entirely when caller passes null', () async {
      final calls = <_Recorded>[];
      final service =
          CoachFollowUpApiService(invoker: _stub(_ok(), recorder: calls));

      await service.generate(
        partnerId: 'p-1',
        phase: CoachFollowUpPhase.prepareInvite,
        answers: _answers(),
      );

      expect(calls.single.body.containsKey('partnerHint'), isFalse);
    });

    test('sends non-empty styleContext when Spec 2.5 context is provided',
        () async {
      final calls = <_Recorded>[];
      final service =
          CoachFollowUpApiService(invoker: _stub(_ok(), recorder: calls));

      await service.generate(
        partnerId: 'p-1',
        phase: CoachFollowUpPhase.prepareInvite,
        answers: _answers(),
        effectiveStyleContext: '  - Preferred voice: 溫柔；不催促  ',
      );

      expect(
        calls.single.body['styleContext'],
        '- Preferred voice: 溫柔；不催促',
      );
    });

    test('omits blank styleContext', () async {
      final calls = <_Recorded>[];
      final service =
          CoachFollowUpApiService(invoker: _stub(_ok(), recorder: calls));

      await service.generate(
        partnerId: 'p-1',
        phase: CoachFollowUpPhase.prepareInvite,
        answers: _answers(),
        effectiveStyleContext: '   ',
      );

      expect(calls.single.body.containsKey('styleContext'), isFalse);
    });

    test(
        'GameStage round-trip — all 5 stage names survive helper → wire payload',
        () async {
      // Silent-break guard: if anyone renames a GameStage value, this test
      // fails loudly instead of the wire format breaking in production.
      final stageWireKeys = <GameStage, String>{
        GameStage.opening: 'opening',
        GameStage.premise: 'premise',
        GameStage.qualification: 'qualification',
        GameStage.narrative: 'narrative',
        GameStage.close: 'close',
      };

      for (final entry in stageWireKeys.entries) {
        final calls = <_Recorded>[];
        final service =
            CoachFollowUpApiService(invoker: _stub(_ok(), recorder: calls));

        await service.generate(
          partnerId: 'p-${entry.key.name}',
          phase: CoachFollowUpPhase.prepareInvite,
          answers: _answers(),
          partnerHint: _hintFromHelper(gameStage: entry.key),
        );

        expect(
          (calls.single.body['partnerHint'] as Map)['gameStage'],
          entry.value,
          reason:
              'GameStage.${entry.key.name} must serialize to "${entry.value}" on the wire',
        );
      }
    });
  });

  group('CoachFollowUpApiService — success-path parsing', () {
    test(
        'parses 200 response into CoachFollowUpResult with partnerId + phase '
        'injected client-side', () async {
      final service = CoachFollowUpApiService(
        invoker: _stub(_ok(_validCardData(
          phase: 'prepareInvite',
          headline: '主動提一次',
          observation: '她回應仍在線但變短',
          task: '丟一個輕量提案',
          suggestedLine: '週六下午咖啡？',
          boundaryReminder: '48 小時內不追',
          model: 'claude-sonnet-4-20250514',
          generatedAt: '2026-05-02T18:30:00.000Z',
        ))),
      );

      final result = await service.generate(
        partnerId: 'p-42',
        phase: CoachFollowUpPhase.prepareInvite,
        answers: _answers(),
      );

      expect(result.partnerId, 'p-42');
      expect(result.phase, 'prepareInvite');
      expect(result.headline, '主動提一次');
      expect(result.observation, '她回應仍在線但變短');
      expect(result.task, '丟一個輕量提案');
      expect(result.suggestedLine, '週六下午咖啡？');
      expect(result.boundaryReminder, '48 小時內不追');
      expect(result.modelUsed, 'claude-sonnet-4-20250514');
      expect(result.generatedAt.toUtc().year, 2026);
      expect(result.generatedAt.toUtc().month, 5);
    });

    test('preserves null suggestedLine through to result', () async {
      final service = CoachFollowUpApiService(
        invoker: _stub(_ok(_validCardData(suggestedLine: null))),
      );

      final result = await service.generate(
        partnerId: 'p-1',
        phase: CoachFollowUpPhase.prepareInvite,
        answers: _answers(),
      );

      expect(result.suggestedLine, isNull);
    });

    test(
        'partnerId + phase come from caller, NOT from response body — even if '
        'response body claims a different phase', () async {
      // Defense: if Edge regresses and echoes a wrong phase, client-injected
      // values win. The client is the source of truth for partnerId/phase.
      final service = CoachFollowUpApiService(
        invoker: _stub(_ok(_validCardData(phase: 'preDateReminder'))),
      );

      final result = await service.generate(
        partnerId: 'p-99',
        phase: CoachFollowUpPhase.prepareInvite,
        answers: _answers(),
      );

      expect(result.partnerId, 'p-99');
      expect(result.phase, 'prepareInvite');
    });
  });

  group('CoachFollowUpApiService — error mapping', () {
    test('400 invalid_input_for_mode → ApiException', () async {
      final service = CoachFollowUpApiService(
        invoker: _stub(const CoachFollowUpInvokeResponse(
          status: 400,
          data: {'error': 'invalid_input_for_mode'},
        )),
      );

      await expectLater(
        service.generate(
          partnerId: 'p-1',
          phase: CoachFollowUpPhase.prepareInvite,
          answers: _answers(),
        ),
        throwsA(isA<ApiException>()),
      );
    });

    test('429 → QuotaExceededException with used + limit propagated', () async {
      final service = CoachFollowUpApiService(
        invoker: _stub(const CoachFollowUpInvokeResponse(
          status: 429,
          data: {
            'error': 'Daily limit exceeded',
            'used': 15,
            'limit': 15,
            'quotaNeeded': 1,
          },
        )),
      );

      try {
        await service.generate(
          partnerId: 'p-1',
          phase: CoachFollowUpPhase.prepareInvite,
          answers: _answers(),
        );
        fail('Expected QuotaExceededException');
      } on QuotaExceededException catch (e) {
        expect(e.used, 15);
        expect(e.limit, 15);
      }
    });

    test('500 AI generation failure → GenerationFailedException', () async {
      final service = CoachFollowUpApiService(
        invoker: _stub(const CoachFollowUpInvokeResponse(
          status: 500,
          data: {'error': 'AI 生成失敗：upstream_timeout'},
        )),
      );

      await expectLater(
        service.generate(
          partnerId: 'p-1',
          phase: CoachFollowUpPhase.prepareInvite,
          answers: _answers(),
        ),
        throwsA(isA<GenerationFailedException>()),
      );
    });

    test('500 schema_invalid → GenerationFailedException', () async {
      final service = CoachFollowUpApiService(
        invoker: _stub(const CoachFollowUpInvokeResponse(
          status: 500,
          data: {'error': 'schema_invalid'},
        )),
      );

      await expectLater(
        service.generate(
          partnerId: 'p-1',
          phase: CoachFollowUpPhase.prepareInvite,
          answers: _answers(),
        ),
        throwsA(isA<GenerationFailedException>()),
      );
    });

    test('500 credit_deduct_failed → GenerationFailedException', () async {
      // Codex P1 #1: deduct failure is a 500 with a stable bucket name. From
      // the client's perspective it's a generation failure (user wasn't
      // charged AND didn't get a card).
      final service = CoachFollowUpApiService(
        invoker: _stub(const CoachFollowUpInvokeResponse(
          status: 500,
          data: {'error': 'credit_deduct_failed'},
        )),
      );

      await expectLater(
        service.generate(
          partnerId: 'p-1',
          phase: CoachFollowUpPhase.prepareInvite,
          answers: _answers(),
        ),
        throwsA(isA<GenerationFailedException>()),
      );
    });
  });

  group('CoachFollowUpApiService — client-side card guards', () {
    test(
        'rejects 200 response with null boundaryReminder → '
        'GenerationFailedException', () async {
      // boundaryReminder is REQUIRED by the Edge schema (Codex P1 #3 boundary
      // contract). The client double-checks because a corrupted / replayed
      // response without it would otherwise silently produce a Hive entity
      // with an empty required field.
      final card = _validCardData()['card'] as Map<String, dynamic>;
      card['boundaryReminder'] = null;

      final service = CoachFollowUpApiService(
        invoker: _stub(_ok(_validCardData()..['card'] = card)),
      );

      await expectLater(
        service.generate(
          partnerId: 'p-1',
          phase: CoachFollowUpPhase.prepareInvite,
          answers: _answers(),
        ),
        throwsA(isA<GenerationFailedException>()),
      );
    });

    test('rejects 200 response with empty boundaryReminder', () async {
      final data = _validCardData();
      (data['card'] as Map<String, dynamic>)['boundaryReminder'] = '';

      final service = CoachFollowUpApiService(invoker: _stub(_ok(data)));

      await expectLater(
        service.generate(
          partnerId: 'p-1',
          phase: CoachFollowUpPhase.prepareInvite,
          answers: _answers(),
        ),
        throwsA(isA<GenerationFailedException>()),
      );
    });

    test('rejects 200 response containing banned token PUA in headline',
        () async {
      final data = _validCardData(headline: 'PUA 教戰');
      final service = CoachFollowUpApiService(invoker: _stub(_ok(data)));

      await expectLater(
        service.generate(
          partnerId: 'p-1',
          phase: CoachFollowUpPhase.prepareInvite,
          answers: _answers(),
        ),
        throwsA(isA<GenerationFailedException>()),
      );
    });

    test('rejects 200 response with banned token 收割 in observation', () async {
      final data = _validCardData(observation: '可以收割了');
      final service = CoachFollowUpApiService(invoker: _stub(_ok(data)));

      await expectLater(
        service.generate(
          partnerId: 'p-1',
          phase: CoachFollowUpPhase.prepareInvite,
          answers: _answers(),
        ),
        throwsA(isA<GenerationFailedException>()),
      );
    });

    test('rejects 200 response with banned token 攻略 in suggestedLine',
        () async {
      final data = _validCardData(suggestedLine: '攻略她的下一步');
      final service = CoachFollowUpApiService(invoker: _stub(_ok(data)));

      await expectLater(
        service.generate(
          partnerId: 'p-1',
          phase: CoachFollowUpPhase.prepareInvite,
          answers: _answers(),
        ),
        throwsA(isA<GenerationFailedException>()),
      );
    });

    test(
        'accepts 200 response when banned token only appears in caller-side '
        'fields (defense scope is response card only)', () async {
      // Sanity check on the assertion scope — we guard the visible CARD
      // fields, not arbitrary response keys. The banned-token check has
      // semantic meaning ("don't render this to the user"); applying it
      // outside visible fields would be pointless.
      final data = _validCardData();
      data['model'] = 'claude-sonnet-PUA-test'; // contrived: not a card field
      final service = CoachFollowUpApiService(invoker: _stub(_ok(data)));

      final result = await service.generate(
        partnerId: 'p-1',
        phase: CoachFollowUpPhase.prepareInvite,
        answers: _answers(),
      );

      expect(result.modelUsed, 'claude-sonnet-PUA-test');
    });
  });
}
