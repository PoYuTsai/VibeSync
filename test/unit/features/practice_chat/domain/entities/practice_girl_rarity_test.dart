import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_girl_catalog.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_girl_rarity.dart';

void main() {
  group('practiceGirlRarityFor（查 catalog，profileId → 稀有度）', () {
    test('已知 profileId → 回該卡在 catalog 的 rarity（逐位一致）', () {
      for (final profile in practiceGirlProfiles) {
        expect(practiceGirlRarityFor(profile.profileId), profile.rarity,
            reason: '${profile.profileId} 查表結果與 catalog rarity 欄位不一致');
      }
    });

    test('錨點：001 Alice=N、004 Mia=SR（與 server 指定、圖鑑測試同錨）', () {
      expect(practiceGirlRarityFor('practice_girl_001'), PracticeGirlRarity.n);
      expect(practiceGirlRarityFor('practice_girl_004'), PracticeGirlRarity.sr);
    });

    test('未知 id → fallback N（絕不丟例外）', () {
      expect(practiceGirlRarityFor('practice_girl_999'), PracticeGirlRarity.n);
      expect(practiceGirlRarityFor('bogus_id'), PracticeGirlRarity.n);
      expect(practiceGirlRarityFor(''), PracticeGirlRarity.n);
    });

    test('星等：SR=4、R=3、N=2；label 對應', () {
      expect(PracticeGirlRarity.sr.stars, 4);
      expect(PracticeGirlRarity.r.stars, 3);
      expect(PracticeGirlRarity.n.stars, 2);
      expect(PracticeGirlRarity.sr.label, 'SR');
      expect(PracticeGirlRarity.r.label, 'R');
      expect(PracticeGirlRarity.n.label, 'N');
    });

    test('catalog 總量：SR=20、R=40、N=40', () {
      final counts = <PracticeGirlRarity, int>{};
      for (final profile in practiceGirlProfiles) {
        counts[profile.rarity] = (counts[profile.rarity] ?? 0) + 1;
      }
      expect(counts[PracticeGirlRarity.sr], 20);
      expect(counts[PracticeGirlRarity.r], 40);
      expect(counts[PracticeGirlRarity.n], 40);
    });

    test('每 persona 20 位 = 4 SR / 8 R / 8 N（稀有度與 persona 解耦後仍守配比）',
        () {
      final perPersona = <String, Map<PracticeGirlRarity, int>>{};
      for (final profile in practiceGirlProfiles) {
        final counts = perPersona.putIfAbsent(profile.personaId, () => {});
        counts[profile.rarity] = (counts[profile.rarity] ?? 0) + 1;
      }
      expect(perPersona.length, 5);
      perPersona.forEach((personaId, counts) {
        expect(counts[PracticeGirlRarity.sr], 4,
            reason: 'persona $personaId 的 SR 數不對');
        expect(counts[PracticeGirlRarity.r], 8,
            reason: 'persona $personaId 的 R 數不對');
        expect(counts[PracticeGirlRarity.n], 8,
            reason: 'persona $personaId 的 N 數不對');
      });
    });
  });
}
