import 'practice_girl_profile.dart';
import 'practice_girl_rarity.dart';

/// 翻牌機率公開給使用者看（Apple 審核準則 3.1.1：隨機取得的東西在付費前公開機率；
/// 送審前盤點 2026-10-30）。抽法鏡像 server `practice_persona.ts`：
/// `selectPracticeDrawProfile` 先排除收藏過的（全歷史永久去重）與目前這位，全被
/// 排除就退回只避開目前這位、再不行用整池；`pickWeightedByRarity` 照 SR 10／R 30
/// ／N 60 擲稀有度，擲中的稀有度沒有候選就依 SR→R→N 的順序補位。
/// （`test/unit/features/practice_chat/practice_draw_odds_test.dart` 讀 server 檔
/// 核對權重與補位順序。）

/// 擲中的稀有度沒有新角色時的補位順序（server `RARITY_FALLBACK_ORDER`）。
const kPracticeDrawFallbackOrder = [
  PracticeGirlRarity.sr,
  PracticeGirlRarity.r,
  PracticeGirlRarity.n,
];

/// 機率怎麼隨收藏改變（擲中的稀有度沒有新角色，就依 SR、R、N 的順序找還有新角色
/// 的稀有度）：付費頁、圖鑑翻牌鈕這一區、扣額度確認窗在還沒集滿時都寫。
const kPracticeDrawOddsFallbackNote = '某個稀有度收藏完後，它的機率依 SR、R、N 的順序轉給還有新角色的稀有度';

/// 基本機率（每個稀有度都還有新角色時）：SR 10%、R 30%、N 60%。
Map<PracticeGirlRarity, int> practiceDrawBaseOdds() => {
      for (final rarity in PracticeGirlRarity.values)
        rarity: rarity.drawOddsPercent,
    };

/// 「翻牌機率：SR 10%・R 30%・N 60%」；給 [odds] 就照它寫（這一次實際的機率）。
String practiceDrawOddsLine([Map<PracticeGirlRarity, int>? odds]) {
  final values = odds ?? practiceDrawBaseOdds();
  return '翻牌機率：${PracticeGirlRarity.values.map((r) => '${r.label} ${values[r] ?? 0}%').join('・')}';
}

/// 這一次翻牌各稀有度實際的機率（%），照 server 的排除與補位規則算：
/// [excludedProfileIds] 是收藏過的角色，[currentProfileId] 是目前這位。
Map<PracticeGirlRarity, int> practiceDrawEffectiveOdds({
  required List<PracticeGirlProfile> catalog,
  required Set<String> excludedProfileIds,
  String? currentProfileId,
}) {
  final exclude = {
    ...excludedProfileIds,
    if (currentProfileId != null) currentProfileId,
  };
  var pool = catalog.where((g) => !exclude.contains(g.profileId)).toList();
  if (pool.isEmpty) {
    pool = catalog.where((g) => g.profileId != currentProfileId).toList();
    if (pool.isEmpty) pool = [...catalog];
  }
  final available = {for (final g in pool) g.rarity};
  final odds = {for (final rarity in PracticeGirlRarity.values) rarity: 0};
  for (final rolled in PracticeGirlRarity.values) {
    final order = [
      rolled,
      ...kPracticeDrawFallbackOrder.where((r) => r != rolled),
    ];
    final landed = order.firstWhere(available.contains, orElse: () => rolled);
    odds[landed] = odds[landed]! + rolled.drawOddsPercent;
  }
  return odds;
}
