import 'dart:math';

import 'practice_girl_catalog.dart';
import 'practice_girl_profile.dart';

export 'practice_girl_profile.dart';

/// 練習室難度的「使用者偏好」。`random` 只是進場前的選擇，
/// 一旦開場就會被解析成 easy / normal / challenge 其中之一。
enum PracticeDifficultyPreference { easy, normal, challenge, random }

/// 練習室模擬對象（與 Edge `practice_persona.ts` 的 id/label 對齊）。
/// 注意：client 端只保留 id 與 label，prompt 內文只存在於 server。
class PracticePersona {
  const PracticePersona({
    required this.id,
    required this.label,
  });

  final String id;
  final String label;
}

/// 本場已解析的「對象＋難度」（送出與持久化都用這組）。
/// persona 綁定 [girl]（與 server resolvePracticeProfile 帶 profileId 時一致）。
class PracticeProfile {
  const PracticeProfile({
    required this.girl,
    required this.personaId,
    required this.personaLabel,
    required this.difficulty,
    required this.difficultyLabel,
  });

  final PracticeGirlProfile girl;
  final String personaId;
  final String personaLabel;
  final String difficulty;
  final String difficultyLabel;

  /// 只換難度、保留同一位對象（送出第一則前的難度控制）。
  PracticeProfile withDifficulty(
    PracticeDifficultyPreference preference, {
    Random? random,
  }) {
    return _profileFromGirl(
      girl,
      _resolveDifficulty(preference, random ?? Random()),
    );
  }

  /// 換一位：整包對象換掉、保留目前難度（兩個控制各自獨立）。
  PracticeProfile withNewGirl({Random? random}) {
    final rng = random ?? Random();
    PracticeGirlProfile next;
    do {
      next = practiceGirlProfiles[rng.nextInt(practiceGirlProfiles.length)];
    } while (
        next.profileId == girl.profileId && practiceGirlProfiles.length > 1);
    return _profileFromGirl(next, difficulty);
  }
}

const practicePersonas = <PracticePersona>[
  PracticePersona(id: 'slow_worker', label: '慢熱上班族'),
  PracticePersona(id: 'playful_extrovert', label: '外向愛玩型'),
  PracticePersona(id: 'cool_rational', label: '高冷理性型'),
  PracticePersona(id: 'teasing_humor', label: '幽默吐槽型'),
  PracticePersona(id: 'clear_boundaries', label: '邊界感強型'),
];

final defaultPracticePersona = practicePersonas.first;

String practiceDifficultyId(PracticeDifficultyPreference preference) {
  return switch (preference) {
    PracticeDifficultyPreference.easy => 'easy',
    PracticeDifficultyPreference.normal => 'normal',
    PracticeDifficultyPreference.challenge => 'challenge',
    PracticeDifficultyPreference.random => 'normal',
  };
}

String practiceDifficultyLabel(String difficulty) {
  return switch (difficulty) {
    'easy' => '輕鬆',
    'challenge' => '挑戰',
    _ => '一般',
  };
}

/// beginner 溫度計開場 fallback。鏡像 server `practice_persona.ts` 的
/// `DIFFICULTY_TUNING[difficulty].startTemperature`——真相源在 server，
/// 這裡只查表，改值必兩邊同步，否則開場 meter 會先顯示舊值再跳到 server 值。
int initialPracticeTemperatureScore(String difficulty) {
  return switch (difficulty) {
    'easy' => 35,
    'challenge' => 20,
    _ => 28,
  };
}

const _randomDifficulties = ['easy', 'normal', 'challenge'];

String _resolveDifficulty(PracticeDifficultyPreference preference, Random rng) {
  return preference == PracticeDifficultyPreference.random
      ? _randomDifficulties[rng.nextInt(_randomDifficulties.length)]
      : practiceDifficultyId(preference);
}

/// personaId → 顯示 label（找不到回預設 persona 的 label）。
String practicePersonaLabel(String personaId) {
  return practicePersonas
      .firstWhere(
        (p) => p.id == personaId,
        orElse: () => defaultPracticePersona,
      )
      .label;
}

/// 由一位 girl + 已解析難度組出 PracticeProfile；persona 一律綁定該位。
PracticeProfile _profileFromGirl(PracticeGirlProfile girl, String difficulty) {
  return PracticeProfile(
    girl: girl,
    personaId: girl.personaId,
    personaLabel: practicePersonaLabel(girl.personaId),
    difficulty: difficulty,
    difficultyLabel: practiceDifficultyLabel(difficulty),
  );
}

/// 產生一場新的 profile：從 catalog 隨機抽一位；難度依偏好
/// （`random` 時才在此抽 3 選 1）。persona 綁定該位。
PracticeProfile createPracticeProfile({
  PracticeDifficultyPreference difficultyPreference =
      PracticeDifficultyPreference.normal,
  Random? random,
}) {
  final rng = random ?? Random();
  final girl = practiceGirlProfiles[rng.nextInt(practiceGirlProfiles.length)];
  return _profileFromGirl(girl, _resolveDifficulty(difficultyPreference, rng));
}

/// 舊 local session 沒有 profileId 時的兜底（與 Edge DEFAULT_PROFILE_ID 一致）。
PracticeProfile fallbackPracticeProfile() {
  return _profileFromGirl(practiceGirlProfiles.first, 'normal');
}

/// 依 profileId 取回 catalog 中那位；找不到（舊場／未知 id）回 null。
PracticeGirlProfile? girlProfileById(String? profileId) {
  if (profileId == null) return null;
  for (final g in practiceGirlProfiles) {
    if (g.profileId == profileId) return g;
  }
  return null;
}
