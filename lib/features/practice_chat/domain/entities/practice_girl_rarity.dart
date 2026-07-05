import 'practice_girl_catalog.dart';

/// 角色卡稀有度。每卡獨立指定（與 persona 解耦），鏡像自 server 真相源
/// `practice_persona.ts`；抽中機率由 server 加權（SR 10%／R 30%／N 60%），
/// client 只負責呈現（邊框／badge／星等），**不**影響扣費或 server 行為。
enum PracticeGirlRarity {
  sr(label: 'SR', stars: 4),
  r(label: 'R', stars: 3),
  n(label: 'N', stars: 2);

  const PracticeGirlRarity({required this.label, required this.stars});

  /// 卡片左上 badge 文字。
  final String label;

  /// 星等（滿星 5）：SR=4、R=3、N=2。
  final int stars;
}

/// profileId → rarity 查表（lazy 建一次；catalog 是 const，永不變動）。
final Map<String, PracticeGirlRarity> _rarityByProfileId = {
  for (final profile in practiceGirlProfiles) profile.profileId: profile.rarity,
};

/// profileId → 稀有度（查 catalog）。未知 id 一律兜底 N，絕不丟例外
/// （catalog 之外的新 profile 上線時圖鑑先當 N 顯示，不炸頁）。
PracticeGirlRarity practiceGirlRarityFor(String profileId) {
  return _rarityByProfileId[profileId] ?? PracticeGirlRarity.n;
}
