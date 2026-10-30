// lib/features/age_gate/domain/age_gate.dart
//
// 18+ 年齡確認（AGE-01；Eric 2026-08-21 DEC-08 要求 iOS 1.0.1 送審前完成，
// 2026-10-30 定最小可行版）。手機上用出生年月算出成年與否，伺服器只收結果
// （adult／minor），寫在帳號的 auth app_metadata.age_gate（只有伺服器寫得進去）；
// 生日不送出、不保存。伺服器端規則見 supabase/functions/_shared/age_gate.ts。

enum AgeGateResult { adult, minor }

/// 伺服器 `AGE_GATE_POLICY_VERSION`：送出時帶上，伺服器只收這個版本。
const kAgeGatePolicyVersion = 1;

const _adultAgeInMonths = 18 * 12;

int _monthIndex(int year, int month) => year * 12 + month;

/// 只知道出生年月：滿 18 歲的那個月就算成年。
bool isAdultByBirthMonth({
  required int birthYear,
  required int birthMonth,
  required DateTime now,
}) =>
    _monthIndex(now.year, now.month) - _monthIndex(birthYear, birthMonth) >=
    _adultAgeInMonths;

/// 出生年月還沒到（選錯）：不能送出。
bool isFutureBirthMonth({
  required int birthYear,
  required int birthMonth,
  required DateTime now,
}) =>
    _monthIndex(birthYear, birthMonth) > _monthIndex(now.year, now.month);

/// 帳號的年齡紀錄（auth `app_metadata.age_gate`）。
AgeGateResult? ageGateResultFromAppMetadata(
        Map<String, dynamic>? appMetadata) =>
    ageGateResultFromRecord(appMetadata?['age_gate']);

/// `{ result, policy, at }`：跟伺服器 `readAgeGateRecord` 一樣嚴格，形狀不對就當
/// 沒有。手機認、伺服器不認的話，全開之後會被伺服器擋住卻不再問年齡。
AgeGateResult? ageGateResultFromRecord(Object? raw) {
  if (raw is! Map) return null;
  final policy = raw['policy'];
  final at = raw['at'];
  if (policy is! int || policy < 1) return null;
  if (at is! String || DateTime.tryParse(at) == null) return null;
  return switch (raw['result']) {
    'adult' => AgeGateResult.adult,
    'minor' => AgeGateResult.minor,
    _ => null,
  };
}
