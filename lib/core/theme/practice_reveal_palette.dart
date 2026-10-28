import 'package:flutter/painting.dart';

/// 抽卡揭曉 V3 的色票（規格 `docs/plans/2026-10-15-card-draw-v3-luxury-reveal-spec.md` §7）。
///
/// DESIGN.md §11 的棘輪只豁免 `lib/core/theme/` 裡的 `Color(0x…)`，所以儀式用到的顏色
/// 全部集中在這裡；稀有度對應表在 feature 內的 `practice_reveal_theme.dart`。圖鑑卡的
/// 稀有度主色（`practiceRarityColor`）不動，揭曉時的 R 用較亮的電光藍（規格 D9=A）。
abstract final class PracticeRevealPalette {
  /// 揭曉背景的暗化底色（文字提案原值；想帶品牌紫調可換 `0xFF0A0612`，只改這一行）。
  static const Color dim = Color(0xFF08070F);

  // ── N：銀 ──
  static const Color nBackTint = Color(0xFFE2E8F0);
  static const Color nGlow = Color(0xFFCBD5E1);
  static const Color nBadgeLight = Color(0xFFF8FAFC);
  static const Color nBadgeDeep = Color(0xFFA9B0B8);
  static const Color nStar = Color(0xFFCBD5E1);
  static const Color nOrb = Color(0xFFE2E8F0);

  // ── R：電光藍（典藏材質 M9：照示意圖一的鈦藍取樣，比 V3 的天空藍再飽和一點）──
  static const Color rBackTint = Color(0xFF8BC5FC);
  static const Color rGlow = Color(0xFF4FB0FF);
  static const Color rBadgeLight = Color(0xFFBAE6FD);
  static const Color rBadgeDeep = Color(0xFF38BDF8);
  static const Color rStar = Color(0xFF7DD3FC);
  static const Color rOrb = Color(0xFF7DD3FC);

  // ── SR：香檳金 ──
  static const Color srBackTint = Color(0xFFFDE68A);
  static const Color srGlow = Color(0xFFF5C451);
  static const Color srBadgeLight = Color(0xFFFDE68A);
  static const Color srBadgeDeep = Color(0xFFF59E0B);
  static const Color srStar = Color(0xFFFFD166);
  static const Color srOrb = Color(0xFFF5D58D);

  // ── SR 卡面掃光的兩道細彩邊、粉色星塵 ──
  static const Color holoCyan = Color(0xFF22D3EE);
  static const Color holoPink = Color(0xFFEC4899);

  // ── 卡面 ──
  /// 全息掃光的中段暖金。
  static const Color sheenGold = Color(0xFFFFD778);

  /// 角色自介對話框的底色（×0.82）。資訊欄改用典藏材質的 [infoSmoke]。
  static const Color infoGlass = Color(0xFF0F0E16);

  // ── V3.1 六角金屬牌（規格 docs/plans/2026-10-17-card-draw-v3-1-polish-spec.md §5.10）──
  // 牌面 P2 起改用典藏材質的 badgeFace*；N／R 的銀倒角沿用這兩色：上緣亮銀 → 外緣深色金屬。
  static const Color badgeMetalLight = Color(0xFFF8FAFC);
  static const Color badgeBevelDeep = Color(0xFF475164);

  // ── V3.1 卡片厚度邊（§5.9）：側立時看得到的深色金屬 ──
  static const Color cardEdgeLight = Color(0xFF9AA3B2);
  static const Color cardEdgeDeep = Color(0xFF242833);

  // ── 典藏材質（規格 docs/plans/2026-10-28-card-collectible-material-spec.md §9）──
  // 拋光外框（暗／中／亮，§6.7）：SR 取自示意圖二的卡面外框。
  static const Color nRimDark = Color(0xFF3A3F47);
  static const Color nRimMid = Color(0xFF9AA4B1);
  static const Color nRimHi = Color(0xFFF4F7FA);
  static const Color rRimDark = Color(0xFF14284F);
  static const Color rRimMid = Color(0xFF4E86D6);
  static const Color rRimHi = Color(0xFFC6EBFF);
  static const Color srRimDark = Color(0xFF4A3618);
  static const Color srRimMid = Color(0xFFB8925A);
  static const Color srRimHi = Color(0xFFFDF2BA);

  /// 卡背素材還沒解碼好時的深色底（§6.8；示意圖一 N 底面的中間調）。
  static const Color cardBackField = Color(0xFF191A1E);

  // 六角牌（§7.3）：拉絲銀面上 → 下、壓印字；SR 金倒角上 → 下（示意圖取樣）。
  static const Color badgeFaceTop = Color(0xFFF6F6F6);
  static const Color badgeFaceMid = Color(0xFFC9CACC);
  static const Color badgeFaceBottom = Color(0xFF979798);
  static const Color badgeInk = Color(0xFF212021);
  static const Color srBadgeBevelHi = Color(0xFFFCEDBE);
  static const Color srBadgeBevelMid = Color(0xFFDCA658);
  static const Color srBadgeBevelDeep = Color(0xFF8E5731);
  static const Color srBadgeBevelLow = Color(0xFFAA8F5A);

  /// 煙燻玻璃資訊欄的底色（中性炭灰，§7.5）。
  static const Color infoSmoke = Color(0xFF141213);

  // 切面星（亮面／暗面／邊，§7.7）。
  static const Color nStarLit = Color(0xFFFFFFFF);
  static const Color nStarShade = Color(0xFFB8C2CE);
  static const Color nStarEdge = Color(0xFF6B7684);
  static const Color rStarLit = Color(0xFFEAF7FF);
  static const Color rStarShade = Color(0xFF7DB8F5);
  static const Color rStarEdge = Color(0xFF3F6FD6);
  static const Color srStarLit = Color(0xFFFDF6B2);
  static const Color srStarShade = Color(0xFFF8CE51);
  static const Color srStarEdge = Color(0xFFB7791F);

  // SR 全息色帶（示意圖取樣，§6.5）：玫瑰 → 洋紅 → 紫 → 天空藍 → 香檳。
  static const Color holoRose = Color(0xFFF6B0AC);
  static const Color holoMagenta = Color(0xFFF99EE6);
  static const Color holoPlum = Color(0xFF8B448F);
  static const Color holoSky = Color(0xFFB1DAFE);
  static const Color srHoloChampagne = Color(0xFFFDF2AE);
}
