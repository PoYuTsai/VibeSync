import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_girl_catalog.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_profile.dart';

void main() {
  bool isInCatalog(String profileId) =>
      practiceGirlProfiles.any((g) => g.profileId == profileId);

  String personaLabelOf(String personaId) =>
      practicePersonas.firstWhere((p) => p.id == personaId).label;

  test('createPracticeProfile 從 catalog 抽一位、persona 綁定該位', () {
    final p = createPracticeProfile(random: Random(0));
    expect(isInCatalog(p.girl.profileId), true);
    // server 帶 profileId 時 persona 綁定該 profile；client 也須一致。
    expect(p.personaId, p.girl.personaId);
    expect(p.personaLabel, personaLabelOf(p.girl.personaId));
  });

  test('createPracticeProfile 難度依偏好（random 解析成三選一）', () {
    final easy = createPracticeProfile(
      difficultyPreference: PracticeDifficultyPreference.easy,
      random: Random(1),
    );
    expect(easy.difficulty, 'easy');
    final rand = createPracticeProfile(
      difficultyPreference: PracticeDifficultyPreference.random,
      random: Random(1),
    );
    expect(['easy', 'normal', 'challenge'].contains(rand.difficulty), true);
  });

  test('withDifficulty 只改難度、不換 girl', () {
    final p1 = createPracticeProfile(random: Random(5));
    final p2 = p1.withDifficulty(PracticeDifficultyPreference.challenge);
    expect(p2.girl.profileId, p1.girl.profileId); // 同一位
    expect(p2.personaId, p1.personaId);
    expect(p2.difficulty, 'challenge');
    expect(p2.difficultyLabel, '挑戰');
  });

  test('withNewGirl 換整包 profile、保留難度', () {
    final p1 = createPracticeProfile(
      difficultyPreference: PracticeDifficultyPreference.challenge,
      random: Random(7),
    );
    final p2 = p1.withNewGirl(random: Random(8));
    expect(p2.girl.profileId == p1.girl.profileId, false); // 換了人
    expect(p2.difficulty, p1.difficulty); // 難度保留
    expect(p2.personaId, p2.girl.personaId); // persona 跟新 girl
  });

  test('fallbackPracticeProfile 回傳完整一位（practice_girl_001）', () {
    final f = fallbackPracticeProfile();
    expect(f.girl.profileId, 'practice_girl_001');
    expect(f.personaId, f.girl.personaId);
  });
}
