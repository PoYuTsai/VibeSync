// 18+ 年齡確認（AGE-01）：出生年月怎麼算成年、帳號紀錄怎麼讀（跟伺服器
// supabase/functions/_shared/age_gate.ts 的 readAgeGateRecord 一樣嚴格）。
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibesync/features/age_gate/data/age_gate_repository.dart';
import 'package:vibesync/features/age_gate/domain/age_gate.dart';

User _user(String id, Map<String, dynamic> appMetadata) => User(
      id: id,
      appMetadata: appMetadata,
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2026-10-30T00:00:00.000Z',
    );

void main() {
  final now = DateTime(2026, 10, 30);

  group('出生年月算成年：滿 18 歲的那個月就算', () {
    test('2008 年 10 月出生，2026 年 10 月滿 18 → 成年', () {
      expect(
        isAdultByBirthMonth(birthYear: 2008, birthMonth: 10, now: now),
        isTrue,
      );
    });

    test('2008 年 11 月出生，還差一個月 → 未成年', () {
      expect(
        isAdultByBirthMonth(birthYear: 2008, birthMonth: 11, now: now),
        isFalse,
      );
    });

    test('跨年：2009 年 1 月出生到 2027 年 1 月才成年', () {
      expect(
        isAdultByBirthMonth(
          birthYear: 2009,
          birthMonth: 1,
          now: DateTime(2026, 12, 31),
        ),
        isFalse,
      );
      expect(
        isAdultByBirthMonth(
          birthYear: 2009,
          birthMonth: 1,
          now: DateTime(2027, 1, 1),
        ),
        isTrue,
      );
    });

    test('出生年月還沒到 → 不能送出', () {
      expect(
        isFutureBirthMonth(birthYear: 2026, birthMonth: 11, now: now),
        isTrue,
      );
      expect(
        isFutureBirthMonth(birthYear: 2026, birthMonth: 10, now: now),
        isFalse,
      );
      expect(
        isFutureBirthMonth(birthYear: 1990, birthMonth: 12, now: now),
        isFalse,
      );
    });
  });

  group('帳號的年齡紀錄（app_metadata.age_gate）', () {
    const at = '2026-10-30T08:00:00.000Z';

    test('形狀對：adult／minor', () {
      expect(
        ageGateResultFromAppMetadata({
          'provider': 'apple',
          'age_gate': {'result': 'adult', 'policy': 1, 'at': at},
        }),
        AgeGateResult.adult,
      );
      expect(
        ageGateResultFromAppMetadata({
          'age_gate': {'result': 'minor', 'policy': 1, 'at': at},
        }),
        AgeGateResult.minor,
      );
    });

    test('沒有紀錄或形狀不對：當沒有', () {
      for (final metadata in <Map<String, dynamic>?>[
        null,
        const {},
        const {'provider': 'email'},
        const {'age_gate': 'adult'},
        const {
          'age_gate': {'result': 'grown', 'policy': 1, 'at': at},
        },
        const {
          'age_gate': {'result': 'adult', 'at': at},
        },
        const {
          'age_gate': {'result': 'adult', 'policy': 0, 'at': at},
        },
        const {
          'age_gate': {'result': 'adult', 'policy': '1', 'at': at},
        },
        const {
          'age_gate': {'result': 'adult', 'policy': 1},
        },
        const {
          'age_gate': {'result': 'adult', 'policy': 1, 'at': 'yesterday'},
        },
      ]) {
        expect(ageGateResultFromAppMetadata(metadata), isNull,
            reason: '$metadata');
      }
    });
  });

  group('AgeGateService：路由讀的確認狀態', () {
    tearDown(AgeGateService.debugReset);

    test('沒登入或沒紀錄：沒確認成年', () {
      expect(AgeGateService.isAdultConfirmed(null), isFalse);
      expect(AgeGateService.isAdultConfirmed(_user('u1', const {})), isFalse);
    });

    test('帳號紀錄是成年：確認；未成年：沒確認', () {
      const at = '2026-10-30T08:00:00.000Z';
      expect(
        AgeGateService.isAdultConfirmed(_user('u1', const {
          'age_gate': {'result': 'adult', 'policy': 1, 'at': at},
        })),
        isTrue,
      );
      expect(
        AgeGateService.isAdultConfirmed(_user('u1', const {
          'age_gate': {'result': 'minor', 'policy': 1, 'at': at},
        })),
        isFalse,
      );
    });

    test('這次執行剛寫成功的紀錄優先（session 還沒換新），只算同一個帳號', () {
      AgeGateService.remember('u1', AgeGateResult.adult);
      expect(AgeGateService.isAdultConfirmed(_user('u1', const {})), isTrue);
      expect(AgeGateService.isAdultConfirmed(_user('u2', const {})), isFalse);

      AgeGateService.remember('u1', AgeGateResult.minor);
      expect(
          AgeGateService.resultFor(_user('u1', const {})), AgeGateResult.minor);
    });
  });
}
