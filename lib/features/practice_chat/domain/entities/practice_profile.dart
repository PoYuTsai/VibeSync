import 'dart:math';

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

/// 本場已解析的角色＋難度（送出與持久化都用這組）。
class PracticeProfile {
  const PracticeProfile({
    required this.personaId,
    required this.personaLabel,
    required this.difficulty,
    required this.difficultyLabel,
  });

  final String personaId;
  final String personaLabel;
  final String difficulty;
  final String difficultyLabel;
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

/// 產生一場新的 profile：隨機抽角色；難度依偏好（`random` 時才在此抽 3 選 1）。
PracticeProfile createPracticeProfile({
  PracticeDifficultyPreference difficultyPreference =
      PracticeDifficultyPreference.normal,
  Random? random,
}) {
  final rng = random ?? Random();
  final persona = practicePersonas[rng.nextInt(practicePersonas.length)];
  const randomDifficulties = ['easy', 'normal', 'challenge'];
  final difficulty = difficultyPreference == PracticeDifficultyPreference.random
      ? randomDifficulties[rng.nextInt(randomDifficulties.length)]
      : practiceDifficultyId(difficultyPreference);

  return PracticeProfile(
    personaId: persona.id,
    personaLabel: persona.label,
    difficulty: difficulty,
    difficultyLabel: practiceDifficultyLabel(difficulty),
  );
}

/// 舊 local session 沒有 persona 時的兜底（與 Edge fallback 一致）。
PracticeProfile fallbackPracticeProfile() {
  return PracticeProfile(
    personaId: defaultPracticePersona.id,
    personaLabel: defaultPracticePersona.label,
    difficulty: 'normal',
    difficultyLabel: practiceDifficultyLabel('normal'),
  );
}
