/// 對象作戰板 3D 階段物件的 label→asset 對照（單一真相源）。
/// 作戰板 dock 與六狀態預覽入口共用，避免兩份映射漂移。
library;

const kPartnerStageUnknownAsset = 'assets/images/partner_stage_unknown.webp';
const kPartnerStageUnknownShortLabel = '尚未分析';

const kPartnerStageAssetsByLabel = <String, String>{
  '破冰階段': 'assets/images/partner_stage_opening.webp',
  // 已是伴侶的 opening 可見語意（閉環規則 5）：同一顆冰塊，不同文案。
  '重新連線': 'assets/images/partner_stage_opening.webp',
  '建立男女感': 'assets/images/partner_stage_premise.webp',
  '互相評估': 'assets/images/partner_stage_qualification.webp',
  '展現個人魅力': 'assets/images/partner_stage_narrative.webp',
  '準備邀約': 'assets/images/partner_stage_close.webp',
};

/// 作戰板小卡使用的單行階段短標籤；詳細頁仍使用原始長文案。
///
/// 報告標籤偶爾會帶 emoji／狀態前綴，使用 contains 才不會因前綴而退回
/// 「尚未分析」。短標籤本身也接受，讓這個 helper 可安全重複套用。
const kPartnerStageShortLabelsByLabel = <String, String>{
  '破冰階段': '破冰',
  '破冰': '破冰',
  '重新連線': '重新連線',
  '建立男女感': '升溫',
  '升溫': '升溫',
  '互相評估': '深入',
  '深入': '深入',
  '展現個人魅力': '連結',
  '連結': '連結',
  '準備邀約': '邀約',
  '邀約': '邀約',
};

String partnerStageShortLabelFor(String? label) {
  if (label == null) return kPartnerStageUnknownShortLabel;
  for (final entry in kPartnerStageShortLabelsByLabel.entries) {
    if (label.contains(entry.key)) return entry.value;
  }
  return kPartnerStageUnknownShortLabel;
}

String partnerStageAssetFor(String? label) {
  if (label == null) return kPartnerStageUnknownAsset;
  for (final entry in kPartnerStageAssetsByLabel.entries) {
    // 報告標籤偶爾會帶 emoji／狀態前綴，使用 contains 才不會誤回未知圖。
    if (label.contains(entry.key)) return entry.value;
  }
  return kPartnerStageUnknownAsset;
}
