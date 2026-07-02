/// 角色圖鑑稀有度（display-only）。
///
/// 由 personaId 決定，純前端呈現用：**不**影響翻牌機率、扣費或 server 行為。
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

/// personaId → 稀有度。未知 personaId 一律兜底 N，絕不丟例外
/// （catalog 之外的新 persona 上線時圖鑑先當 N 顯示，不炸頁）。
PracticeGirlRarity practiceGirlRarityFor(String personaId) {
  switch (personaId) {
    case 'teasing_humor':
      return PracticeGirlRarity.sr;
    case 'cool_rational':
    case 'clear_boundaries':
      return PracticeGirlRarity.r;
    case 'playful_extrovert':
    case 'slow_worker':
      return PracticeGirlRarity.n;
    default:
      return PracticeGirlRarity.n;
  }
}
