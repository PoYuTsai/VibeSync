// 年齡確認的紀錄送到伺服器（sync-subscription `record_age_gate`）：伺服器回的紀錄
// 才算數；寫失敗不放行；寫成功後換一次 token，換不成功不影響結果。
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibesync/features/age_gate/data/age_gate_repository.dart';
import 'package:vibesync/features/age_gate/domain/age_gate.dart';

const _at = '2026-10-30T08:00:00.000Z';

class _Harness {
  _Harness(this.respond, {this.userId = 'u1', this.refreshFails = false});

  final FutureOr<FunctionResponse> Function() respond;
  final String? userId;
  final bool refreshFails;
  final calls = <(String, Map<String, dynamic>?)>[];
  var refreshes = 0;

  AgeGateRepository build() => AgeGateRepository(
        invoke: (fn, {body}) async {
          calls.add((fn, body));
          return respond();
        },
        refreshSession: () async {
          refreshes += 1;
          if (refreshFails) throw Exception('offline');
        },
        currentUserId: () => userId,
      );
}

User _user(String id) => User(
      id: id,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: _at,
    );

void main() {
  tearDown(AgeGateService.debugReset);

  test('送出結果與版本，不送生日；伺服器記下成年 → 回成年、路由放行、換 token', () async {
    final harness = _Harness(() => FunctionResponse(status: 200, data: {
          'ageGate': {'result': 'adult', 'policy': 1, 'at': _at},
        }));

    final result = await harness.build().record(AgeGateResult.adult);

    expect(result, AgeGateResult.adult);
    final (functionName, body) = harness.calls.single;
    expect(functionName, 'sync-subscription');
    expect(body, {'mode': 'record_age_gate', 'result': 'adult', 'policy': 1});
    expect(harness.refreshes, 1);
    expect(AgeGateService.isAdultConfirmed(_user('u1')), isTrue);
  });

  test('未成年鎖住（409）：照伺服器的未成年紀錄走', () async {
    final harness = _Harness(
      () => throw const FunctionException(status: 409, details: {
        'error': 'AGE_GATE_LOCKED',
        'ageGate': {'result': 'minor', 'policy': 1, 'at': _at},
      }),
    );

    final result = await harness.build().record(AgeGateResult.adult);

    expect(result, AgeGateResult.minor);
    expect(AgeGateService.resultFor(_user('u1')), AgeGateResult.minor);
  });

  test('伺服器回的紀錄跟送出的不同：照伺服器', () async {
    final harness = _Harness(() => FunctionResponse(status: 200, data: {
          'ageGate': {'result': 'minor', 'policy': 1, 'at': _at},
        }));

    expect(
      await harness.build().record(AgeGateResult.adult),
      AgeGateResult.minor,
    );
  });

  test('換 token 失敗：結果照算，路由靠這次記下的放行', () async {
    final harness = _Harness(
      () => FunctionResponse(status: 200, data: {
        'ageGate': {'result': 'adult', 'policy': 1, 'at': _at},
      }),
      refreshFails: true,
    );

    expect(
      await harness.build().record(AgeGateResult.adult),
      AgeGateResult.adult,
    );
    expect(AgeGateService.isAdultConfirmed(_user('u1')), isTrue);
  });

  for (final (label, respond)
      in <(String, FutureOr<FunctionResponse> Function())>[
    ('伺服器錯誤', () => throw const FunctionException(status: 500)),
    ('連不上', () => throw TimeoutException('offline')),
    (
      '舊版伺服器回訂閱同步的結果',
      () => FunctionResponse(status: 200, data: {'tier': 'free'})
    ),
    (
      '紀錄形狀不對',
      () => FunctionResponse(status: 200, data: {
            'ageGate': {'result': 'adult'},
          }),
    ),
    ('回應不是 JSON 物件', () => FunctionResponse(status: 200, data: 'ok')),
  ]) {
    test('沒寫成功（$label）：丟錯、不放行、不換 token', () async {
      final harness = _Harness(respond);

      await expectLater(
        harness.build().record(AgeGateResult.adult),
        throwsA(isA<AgeGateRecordException>()),
      );
      expect(AgeGateService.isAdultConfirmed(_user('u1')), isFalse);
      expect(harness.refreshes, 0);
    });
  }

  test('沒登入：不打伺服器', () async {
    final harness = _Harness(
      () => FunctionResponse(status: 200, data: const {}),
      userId: null,
    );

    await expectLater(
      harness.build().record(AgeGateResult.adult),
      throwsA(isA<AgeGateRecordException>()),
    );
    expect(harness.calls, isEmpty);
  });
}
