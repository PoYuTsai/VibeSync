import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_girl_catalog.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_girl_rarity.dart';

void main() {
  group('practiceGirlRarityFor', () {
    test('teasing_humor → SR', () {
      expect(practiceGirlRarityFor('teasing_humor'), PracticeGirlRarity.sr);
    });

    test('cool_rational / clear_boundaries → R', () {
      expect(practiceGirlRarityFor('cool_rational'), PracticeGirlRarity.r);
      expect(practiceGirlRarityFor('clear_boundaries'), PracticeGirlRarity.r);
    });

    test('playful_extrovert / slow_worker → N', () {
      expect(practiceGirlRarityFor('playful_extrovert'), PracticeGirlRarity.n);
      expect(practiceGirlRarityFor('slow_worker'), PracticeGirlRarity.n);
    });

    test('未知 personaId → fallback N（絕不丟例外）', () {
      expect(practiceGirlRarityFor('bogus_persona'), PracticeGirlRarity.n);
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

    test('60 位 catalog 全員 personaId 都在已知映射內（不靠 fallback）', () {
      const known = {
        'teasing_humor',
        'cool_rational',
        'clear_boundaries',
        'playful_extrovert',
        'slow_worker',
      };
      expect(practiceGirlProfiles, hasLength(60));
      for (final profile in practiceGirlProfiles) {
        expect(known, contains(profile.personaId),
            reason: '${profile.profileId} 的 personaId=${profile.personaId} '
                '不在已知映射，會靜默 fallback N');
      }
    });

    test('catalog SR 數量 = 9', () {
      final srCount = practiceGirlProfiles
          .where((p) => practiceGirlRarityFor(p.personaId) ==
              PracticeGirlRarity.sr)
          .length;
      expect(srCount, 9);
    });
  });
}
