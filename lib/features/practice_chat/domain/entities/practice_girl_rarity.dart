import 'practice_girl_catalog.dart';

/// 角色卡稀有度。每卡獨立指定（與 persona 解耦），鏡像自 server 真相源
/// `practice_persona.ts`；抽中機率由 server 加權（SR 10%／R 30%／N 60%），
/// client 只負責呈現（邊框／badge／星等），**不**影響扣費或 server 行為。
enum PracticeGirlRarity {
  sr(label: 'SR', stars: 4, drawOddsPercent: 10),
  r(label: 'R', stars: 3, drawOddsPercent: 30),
  n(label: 'N', stars: 2, drawOddsPercent: 60);

  const PracticeGirlRarity({
    required this.label,
    required this.stars,
    required this.drawOddsPercent,
  });

  /// 卡片左上 badge 文字。
  final String label;

  /// 星等（滿星 5）：SR=4、R=3、N=2。
  final int stars;

  /// 一般翻牌抽中這個稀有度的機率（%），只用來公開給使用者看。跟 server
  /// `practice_persona.ts` 的 `RARITY_WEIGHTS` 一致（測試讀 server 檔核對）。
  final int drawOddsPercent;
}

/// 翻牌機率那一行（圖鑑翻牌鈕下方、扣額度翻牌的確認窗、付費頁）：Apple 審核準則
/// 3.1.1 要求隨機取得的東西在付費前公開機率（送審前盤點 2026-10-30）。
String practiceDrawOddsLine() =>
    '翻牌機率：${PracticeGirlRarity.values.map((r) => '${r.label} ${r.drawOddsPercent}%').join('・')}';

/// profileId → rarity 查表（lazy 建一次；catalog 是 const，永不變動）。
final Map<String, PracticeGirlRarity> _rarityByProfileId = {
  for (final profile in practiceGirlProfiles) profile.profileId: profile.rarity,
};

/// profileId → 稀有度（查 catalog）。未知 id 一律兜底 N，絕不丟例外
/// （catalog 之外的新 profile 上線時圖鑑先當 N 顯示，不炸頁）。
PracticeGirlRarity practiceGirlRarityFor(String profileId) {
  return _rarityByProfileId[profileId] ?? PracticeGirlRarity.n;
}
