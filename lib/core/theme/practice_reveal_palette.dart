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
  static const Color nBackTintDeep = Color(0xFF94A3B8);
  static const Color nFrameLight = Color(0xFFF1F5F9);
  static const Color nFrameDeep = Color(0xFF94A3B8);
  static const Color nGlow = Color(0xFFCBD5E1);
  static const Color nBadgeLight = Color(0xFFF8FAFC);
  static const Color nBadgeDeep = Color(0xFFA9B0B8);
  static const Color nStar = Color(0xFFCBD5E1);
  static const Color nOrb = Color(0xFFE2E8F0);

  // ── R：電光藍 ──
  static const Color rBackTint = Color(0xFF38BDF8);
  static const Color rBackTintDeep = Color(0xFF818CF8);
  static const Color rFrameLight = Color(0xFF7DD3FC);
  static const Color rFrameDeep = Color(0xFF6366F1);
  static const Color rGlow = Color(0xFF38BDF8);
  static const Color rBadgeLight = Color(0xFFBAE6FD);
  static const Color rBadgeDeep = Color(0xFF38BDF8);
  static const Color rStar = Color(0xFF7DD3FC);
  static const Color rOrb = Color(0xFF7DD3FC);

  // ── SR：香檳金 ──
  static const Color srBackTint = Color(0xFFFDE68A);
  static const Color srBackTintDeep = Color(0xFFF59E0B);
  static const Color srFrameLight = Color(0xFFFDE68A);
  static const Color srFrameDeep = Color(0xFFB7791F);
  static const Color srGlow = Color(0xFFF5C451);
  static const Color srBadgeLight = Color(0xFFFDE68A);
  static const Color srBadgeDeep = Color(0xFFF59E0B);
  static const Color srStar = Color(0xFFFFD166);
  static const Color srOrb = Color(0xFFF5D58D);

  // ── SR 全息彩邊 ──
  static const Color holoCyan = Color(0xFF22D3EE);
  static const Color holoViolet = Color(0xFF8B5CF6);
  static const Color holoPink = Color(0xFFEC4899);

  // ── 卡面 ──
  /// 全息掃光的中段暖金。
  static const Color sheenGold = Color(0xFFFFD778);

  /// 資訊欄毛玻璃的底色（疊在模糊照片上，×0.68）。
  static const Color infoGlass = Color(0xFF0F0E16);
}
