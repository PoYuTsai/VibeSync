import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_draw_odds.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_girl_catalog.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_girl_rarity.dart';

/// 公開給使用者看的翻牌機率（Apple 審核準則 3.1.1）必須跟伺服器真的抽法一致：讀
/// server `practice_persona.ts` 的 `RARITY_WEIGHTS` 與 `RARITY_FALLBACK_ORDER`
/// 核對，改了一邊沒改另一邊就失敗；「這一次實際的機率」照 server 的排除與補位
/// 規則逐一驗情境。
void main() {
  final serverSource = File(
    'supabase/functions/practice-chat/practice_persona.ts',
  ).readAsStringSync();

  test('基本機率跟 server RARITY_WEIGHTS 一致，加起來 100%', () {
    final matches = RegExp(
      r'\{\s*rarity:\s*"(sr|r|n)",\s*weight:\s*(\d+)\s*\}',
    ).allMatches(serverSource).toList();
    expect(matches, hasLength(3), reason: 'RARITY_WEIGHTS 要剛好三筆');
    final weights = {
      for (final m in matches) m.group(1)!: int.parse(m.group(2)!),
    };
    final total = weights.values.fold<int>(0, (sum, w) => sum + w);

    for (final rarity in PracticeGirlRarity.values) {
      final weight = weights[rarity.name]!;
      expect(weight * 100 % total, 0, reason: '${rarity.label} 要能寫成整數百分比');
      expect(rarity.drawOddsPercent, weight * 100 ~/ total,
          reason: rarity.label);
    }
    expect(
      PracticeGirlRarity.values
          .fold<int>(0, (sum, r) => sum + r.drawOddsPercent),
      100,
    );
  });

  test('補位順序跟 server RARITY_FALLBACK_ORDER 一致', () {
    final match = RegExp(
      r'RARITY_FALLBACK_ORDER[^=]*=\s*\[([^\]]*)\]',
    ).firstMatch(serverSource);
    expect(match, isNotNull);
    final order = RegExp(r'"(sr|r|n)"')
        .allMatches(match!.group(1)!)
        .map((m) => m.group(1))
        .toList();
    expect(order, kPracticeDrawFallbackOrder.map((r) => r.name).toList());
  });

  test('翻牌機率那一行', () {
    expect(practiceDrawOddsLine(), '翻牌機率：SR 10%・R 30%・N 60%');
    expect(
      practiceDrawOddsLine({
        PracticeGirlRarity.sr: 0,
        PracticeGirlRarity.r: 40,
        PracticeGirlRarity.n: 60,
      }),
      '翻牌機率：SR 0%・R 40%・N 60%',
    );
  });

  group('這一次實際的機率（照 server 的排除與補位）', () {
    Set<String> idsOf(Iterable<PracticeGirlRarity> rarities) => {
          for (final g in practiceGirlProfiles)
            if (rarities.contains(g.rarity)) g.profileId,
        };
    Map<PracticeGirlRarity, int> odds(int sr, int r, int n) => {
          PracticeGirlRarity.sr: sr,
          PracticeGirlRarity.r: r,
          PracticeGirlRarity.n: n,
        };

    test('每個稀有度都還有新角色 → 基本機率', () {
      final result = practiceDrawEffectiveOdds(
        catalog: practiceGirlProfiles,
        excludedProfileIds: const {},
      );
      expect(result, odds(10, 30, 60));
    });

    test('SR 都收藏過了 → SR 的 10% 轉給 R', () {
      final result = practiceDrawEffectiveOdds(
        catalog: practiceGirlProfiles,
        excludedProfileIds: idsOf([PracticeGirlRarity.sr]),
      );
      expect(result, odds(0, 40, 60));
    });

    test('N 都收藏過了 → N 的 60% 依 SR→R→N 先轉給 SR', () {
      expect(
        practiceDrawEffectiveOdds(
          catalog: practiceGirlProfiles,
          excludedProfileIds: idsOf([PracticeGirlRarity.n]),
        ),
        odds(70, 30, 0),
      );
    });

    test('SR、R 都收藏過了 → N 100%', () {
      expect(
        practiceDrawEffectiveOdds(
          catalog: practiceGirlProfiles,
          excludedProfileIds:
              idsOf([PracticeGirlRarity.sr, PracticeGirlRarity.r]),
        ),
        odds(0, 0, 100),
      );
    });

    test('全部收藏過了 → 改成可能重複，回到基本機率', () {
      expect(
        practiceDrawEffectiveOdds(
          catalog: practiceGirlProfiles,
          excludedProfileIds: idsOf(PracticeGirlRarity.values),
          currentProfileId: practiceGirlProfiles.first.profileId,
        ),
        odds(10, 30, 60),
      );
    });

    test('目前這位也算排除：她是最後一位沒收藏的 SR → 跟 SR 收齊一樣', () {
      final srs = [
        for (final g in practiceGirlProfiles)
          if (g.rarity == PracticeGirlRarity.sr) g.profileId,
      ];
      expect(
        practiceDrawEffectiveOdds(
          catalog: practiceGirlProfiles,
          excludedProfileIds: srs.skip(1).toSet(),
          currentProfileId: srs.first,
        ),
        odds(0, 40, 60),
      );
    });
  });
}
