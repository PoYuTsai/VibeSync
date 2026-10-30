import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_girl_rarity.dart';

/// 公開給使用者看的翻牌機率（Apple 審核準則 3.1.1）必須跟伺服器真的抽法一致：讀
/// server `practice_persona.ts` 的 `RARITY_WEIGHTS` 逐項核對，改了一邊沒改另一邊就失敗。
void main() {
  test('公開的翻牌機率跟 server RARITY_WEIGHTS 一致，加起來 100%', () {
    final source = File(
      'supabase/functions/practice-chat/practice_persona.ts',
    ).readAsStringSync();
    final matches = RegExp(
      r'\{\s*rarity:\s*"(sr|r|n)",\s*weight:\s*(\d+)\s*\}',
    ).allMatches(source).toList();
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

  test('翻牌機率那一行', () {
    expect(practiceDrawOddsLine(), '翻牌機率：SR 10%・R 30%・N 60%');
  });
}
