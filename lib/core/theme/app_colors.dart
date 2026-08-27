import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Primary
  static const primary = Color(0xFF6B4EE6);
  static const primaryLight = Color(0xFF9D8DF7);
  static const primaryDark = Color(0xFF4527A0);

  // Enthusiasm levels
  // frozen 比 cold 更冷：偏白的冰藍，練習室溫度計 frozen band 專用。
  static const frozen = Color(0xFF9BE7FF);
  static const cold = Color(0xFF64B5F6);
  static const warm = Color(0xFFD4A574);
  static const hot = Color(0xFFE57373);
  static const veryHot = Color(0xFFFF6B9D);

  // 投入度光球（HeatOrb）的三顆銜接色。
  //
  // 五段光球的兩端直接用上面的 cold/frozen 與下面的 brandBlush/brandFlame，
  // 但紫不能一步跳到橘——中間需要調和色，否則換段會看到色相硬切。這三顆是
  // 為了那個過渡而存在的，不是既有色的重複，刪掉會讓色帶斷開。
  //
  // heatOrbLift 是 primaryLight 的提亮版（第 2 段內核）；heatOrbBridge 是
  // 紫→粉的橋（第 4 段外暈）；heatOrbEmber 是第 5 段外圈刻意保留的紫暈——
  // 燒到最熱時外圈仍要有紫透出來，純橘的球會變成一張貼紙。
  static const heatOrbLift = Color(0xFFB9A9FF);
  static const heatOrbBridge = Color(0xFFB274E2);
  static const heatOrbEmber = Color(0xFFB06EEB);

  // Neutral
  static const background = Color(0xFF121212);
  static const surface = Color(0xFF1E1E1E);
  static const surfaceVariant = Color(0xFF2D2D2D);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFFB3B3B3);
  static const divider = Color(0xFF3D3D3D);

  // Semantic
  static const success = Color(0xFF4CAF50);
  static const error = Color(0xFFE57373);

  /// 白玻璃（glassWhite）底上的警示紅：error 是深底用的淺紅，
  /// 放白底只有 ~2.5:1，這顆在 glassWhite 上約 7:1。
  static const errorOnGlass = Color(0xFFC62828);
  static const warning = Color(0xFFFFB74D);
  static const info = Color(0xFF64B5F6);

  // Warm theme backgrounds
  static const brandInk = Color(0xFF150C24);

  /// 橘色主 CTA 上的字色單一開關（2026-08-10 Eric 拍板試行深墨字：
  /// 白字對比 2.86:1 戶外弱，深墨 6.62:1）。想改回白字只動這一行。
  static const onCta = brandInk;
  static const brandSurface = Color(0xFF1F1330);
  static const brandSurface2 = Color(0xFF2A1840);
  static const brandFlame = Color(0xFFFF6A2B);
  static const brandFlameDark = Color(0xFFE85A1E);
  static const brandBlush = Color(0xFFFF2D8B);

  // Coach insight surfaces
  //
  // Shared by Analyze Chat records and the Opener / New Topic workflow.
  // Purple communicates selection and interpretation; pink is reserved for an
  // AI recommendation. Orange remains the action color (generate/copy/upgrade).
  static const coachBackgroundWarm = Color(0xFF2A1831);
  static const coachBackgroundMid = Color(0xFF111329);
  static const coachBackgroundInk = Color(0xFF090C1B);
  static const coachSurface = Color(0xFF15152A);
  static const coachSurfaceRaised = Color(0xFF24172F);
  static const coachAccent = Color(0xFF9D78F5);
  static const coachAccentBright = Color(0xFFC68BFF);
  static const coachRecommendation = Color(0xFFFF5DA8);

  static const backgroundGradientStart = brandInk;
  static const backgroundGradientMid = brandSurface;
  static const backgroundGradientEnd = brandSurface2;

  // Warm theme bokeh
  static const bokehPink = brandBlush;
  static const bokehCoral = brandFlame;
  static const bokehYellow = Color(0xFFFFB34D);

  // Warm theme glass surfaces
  static const glassWhite = Color(0xFFF5F0F8);
  static const glassBorder = Color(0xFFE8E0F0);

  // Warm theme text on glass
  static const glassTextPrimary = Color(0xFF4A3548);
  static const glassTextSecondary = Color(0xFF6C5A6B);
  static const glassTextHint = Color(0xFF8B4557);

  // Text on dark gradient
  static const onBackgroundPrimary = Color(0xFFFFFFFF);
  static const onBackgroundSecondary = Color(0xFFE0D0E8);

  // Supporting text
  static const unselectedText = Color(0xFF5D4E6B);

  // Selected gradients
  static const selectedStart = Color(0xFFFF6B9D);
  static const selectedEnd = Color(0xFFFF8A65);

  // CTA gradients
  static const ctaStart = brandFlame;
  static const ctaEnd = brandFlameDark;

  // 對象作戰板身份色（2026-08-15 對標夥伴示意稿）：低飽和霧感四色，
  // 刻意不用品牌螢光色票——螢光色在深玻璃卡上會太跳。
  static const partnerRoseStart = Color(0xFFE99AA6);
  static const partnerRoseEnd = Color(0xFFD97F92);
  static const partnerGoldStart = Color(0xFFC9A75F);
  static const partnerGoldEnd = Color(0xFFB08F4C);
  static const partnerOrangeStart = Color(0xFFF4913F);
  static const partnerOrangeEnd = Color(0xFFE4611C);
  static const partnerOrchidStart = Color(0xFFE98BBB);
  static const partnerOrchidEnd = Color(0xFFDB6FA6);

  // Avatar gradients
  static const avatarHerStart = Color(0xFFFFD54F);
  static const avatarHerEnd = Color(0xFFFFC107);
  static const avatarMeStart = Color(0xFF9D8DF7);
  static const avatarMeEnd = Color(0xFF6B4EE6);

  // Partner detail dark backdrop (post-A2 visual polish 2026-04-28).
  // Darker than the AddPartner gradient on purpose: detail page is
  // "深夜陪你讀懂這段關係" mood, not action mood.
  static const partnerDetailBgTop = Color(0xFF070812);
  static const partnerDetailBgBottom = Color(0xFF0B0A14);
}
