// 年齡確認的紀錄送到伺服器（sync-subscription `record_age_gate`）：伺服器回的紀錄
// 才算數；寫失敗不放行；寫成功後換一次 token，換成功（session 帶著新紀錄）路由才
// 放行。不另外記在記憶體（主審第 1 輪 P2）。
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

User _sessionUser(Map<String, dynamic> appMetadata) => User(
      id: 'u1',
      appMetadata: appMetadata,
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: _at,
    );

FunctionResponse _recorded(String result) => FunctionResponse(
      status: 200,
      data: {
        'ageGate': {'result': result, 'policy': 1, 'at': _at},
      },
    );

void main() {
  test('送出結果與版本，不送生日；伺服器記下成年 → 回成年、換 token', () async {
    final harness = _Harness(() => _recorded('adult'));

    final outcome = await harness.build().record(AgeGateResult.adult);

    expect(outcome.result, AgeGateResult.adult);
    expect(outcome.sessionUpdated, isTrue);
    final (functionName, body) = harness.calls.single;
    expect(functionName, 'sync-subscription');
    expect(body, {'mode': 'record_age_gate', 'result': 'adult', 'policy': 1});
    expect(harness.refreshes, 1);
  });

  test('不另外記在記憶體：寫成功後，路由還是只看 session 裡的紀錄', () async {
    final harness = _Harness(() => _recorded('adult'));

    await harness.build().record(AgeGateResult.adult);

    expect(AgeGateService.isAdultConfirmed(_sessionUser(const {})), isFalse);
    expect(
      AgeGateService.isAdultConfirmed(_sessionUser(const {
        'age_gate': {'result': 'adult', 'policy': 1, 'at': _at},
      })),
      isTrue,
    );
  });

  test('未成年鎖住（409）：照伺服器的未成年紀錄走', () async {
    final harness = _Harness(
      () => throw const FunctionException(status: 409, details: {
        'error': 'AGE_GATE_LOCKED',
        'ageGate': {'result': 'minor', 'policy': 1, 'at': _at},
      }),
    );

    final outcome = await harness.build().record(AgeGateResult.adult);

    expect(outcome.result, AgeGateResult.minor);
  });

  test('伺服器回的紀錄跟送出的不同：照伺服器', () async {
    final harness = _Harness(() => _recorded('minor'));

    expect(
      (await harness.build().record(AgeGateResult.adult)).result,
      AgeGateResult.minor,
    );
  });

  test('換 token 失敗：結果照伺服器，但標成 session 還沒更新（畫面請他再按）', () async {
    final harness = _Harness(() => _recorded('adult'), refreshFails: true);

    final outcome = await harness.build().record(AgeGateResult.adult);

    expect(outcome.result, AgeGateResult.adult);
    expect(outcome.sessionUpdated, isFalse);
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
    test('沒寫成功（$label）：丟錯、不換 token', () async {
      final harness = _Harness(respond);

      await expectLater(
        harness.build().record(AgeGateResult.adult),
        throwsA(isA<AgeGateRecordException>()),
      );
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
