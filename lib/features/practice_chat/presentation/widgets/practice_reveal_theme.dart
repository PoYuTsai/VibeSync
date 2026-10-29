// 抽卡揭曉 V3 的稀有度主題（規格 docs/plans/2026-10-15-card-draw-v3-luxury-reveal-spec.md §7）。
// 色值本體在 lib/core/theme/practice_reveal_palette.dart；這裡只負責「哪個稀有度用哪組」，
// 以及卡背染色當下（銀 → 藍 → 金）的顏色插值。圖鑑卡的配色（practice_rarity_style.dart）不動。
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../../../core/theme/practice_reveal_palette.dart';
import '../../domain/entities/practice_girl_rarity.dart';
import 'practice_reveal_timing.dart';

/// 光效檔位（V3.1 規格 §9）：泛光層數與同一幀粒子上限。高＝V3 在真機上很順，中＝偶爾掉幀，
/// 低＝V3 本身就會卡。
enum PracticeRevealEffectTier { high, medium, low }

/// 目前的檔位：Eric 2026-10-18 回報 TestFlight 536 的 V3「目前還行」，預設中檔，真機再調
/// （只改這一行）。
const PracticeRevealEffectTier kPracticeRevealEffectTier =
    PracticeRevealEffectTier.medium;

/// 測試 seam：覆寫檔位（null＝[kPracticeRevealEffectTier]）。production 不碰。
@visibleForTesting
PracticeRevealEffectTier? debugPracticeRevealEffectTierOverride;

/// 實際用的檔位。
PracticeRevealEffectTier get practiceRevealEffectTier =>
    debugPracticeRevealEffectTierOverride ?? kPracticeRevealEffectTier;

/// 泛光畫幾層（§9）：高、中檔卡片前後兩層，低檔只畫後層。
int practiceRevealBloomLayers(PracticeRevealEffectTier tier) =>
    tier == PracticeRevealEffectTier.low ? 1 : 2;

@immutable
class PracticeRevealTheme {
  const PracticeRevealTheme._({
    required this.backTint,
    required this.rimDark,
    required this.rimMid,
    required this.rimHi,
    required this.backSpecular,
    required this.glow,
    required this.shockwave,
    required this.ambientAlpha,
    required this.burstCounts,
    required this.burstSpeed,
    required this.bladeWidth,
    required this.sheenStrength,
    required this.badgeLight,
    required this.badgeDeep,
    required this.star,
    required this.starLit,
    required this.starShade,
    required this.starEdge,
    required this.orb,
    required this.holo,
  });

  /// 稀有度的主色（衝擊波光環的顏色）。
  final Color backTint;

  /// 卡面拋光外框的暗／中／亮（典藏材質規格 §6.7）：截面外暗、中亮、內暗，亮度隨受光角變化。
  final Color rimDark;
  final Color rimMid;
  final Color rimHi;

  /// 卡背高光帶的強度（典藏材質規格 §6.4：N 0.26、R 0.30、SR 0.34）。
  final double backSpecular;

  /// 環境光、卡面外光、光刃外暈的顏色。
  final Color glow;

  /// 翻牌峰值衝擊波光環的顏色（V3.1 §5.6；N 沒有衝擊波）。R 跟環境光、光刃同色（典藏材質 M9
  /// 的 `#4FB0FF`），SR 維持香檳金。
  final Color shockwave;

  /// 卡片背後環境光的不透明度。
  final double ambientAlpha;

  /// 翻牌峰值爆發的星塵顆數，依檔位（高、中、低）：V3.1 §5.7 N 24、R 48、SR 160 是高檔，
  /// 中檔 SR 80、低檔上限 48（§9）。
  final ({int high, int medium, int low}) burstCounts;

  /// 爆發星塵的初速倍率：SR 散得最遠（滿畫面）。
  final double burstSpeed;

  /// 光刃外暈最寬是幾倍卡寬（V3.1 §5.5：N 0.6、R 0.7、SR 0.8）。
  final double bladeWidth;

  /// 目前檔位的爆發星塵顆數。
  int get burstCount => switch (practiceRevealEffectTier) {
        PracticeRevealEffectTier.high => burstCounts.high,
        PracticeRevealEffectTier.medium => burstCounts.medium,
        PracticeRevealEffectTier.low => burstCounts.low,
      };

  /// 全息掃光強度。
  final double sheenStrength;

  /// 稀有度牌的底色漸層（上 → 下）。
  final Color badgeLight;
  final Color badgeDeep;

  /// 亮星的光暈色；星塵、星光、小光點也用它（另一半是白）。
  final Color star;

  /// 切面星的亮面／暗面／邊（典藏材質規格 §7.7）。
  final Color starLit;
  final Color starShade;
  final Color starEdge;

  /// 收卡光球、落點光環、圖鑑那一格發光的顏色。
  final Color orb;

  /// SR 才有：卡背外框的全息彩邊、卡面掃光的兩道細彩邊、粉色星塵。
  final bool holo;

  static const PracticeRevealTheme n = PracticeRevealTheme._(
    backTint: PracticeRevealPalette.nBackTint,
    rimDark: PracticeRevealPalette.nRimDark,
    rimMid: PracticeRevealPalette.nRimMid,
    rimHi: PracticeRevealPalette.nRimHi,
    backSpecular: 0.26,
    glow: PracticeRevealPalette.nGlow,
    shockwave: PracticeRevealPalette.nBackTint,
    ambientAlpha: 0.22,
    burstCounts: (high: 24, medium: 24, low: 24),
    burstSpeed: 1.0,
    bladeWidth: 0.6,
    sheenStrength: 0.35,
    badgeLight: PracticeRevealPalette.nBadgeLight,
    badgeDeep: PracticeRevealPalette.nBadgeDeep,
    star: PracticeRevealPalette.nStar,
    starLit: PracticeRevealPalette.nStarLit,
    starShade: PracticeRevealPalette.nStarShade,
    starEdge: PracticeRevealPalette.nStarEdge,
    orb: PracticeRevealPalette.nOrb,
    holo: false,
  );

  static const PracticeRevealTheme r = PracticeRevealTheme._(
    backTint: PracticeRevealPalette.rBackTint,
    rimDark: PracticeRevealPalette.rRimDark,
    rimMid: PracticeRevealPalette.rRimMid,
    rimHi: PracticeRevealPalette.rRimHi,
    backSpecular: 0.30,
    glow: PracticeRevealPalette.rGlow,
    shockwave: PracticeRevealPalette.rGlow,
    ambientAlpha: 0.32,
    burstCounts: (high: 48, medium: 48, low: 48),
    burstSpeed: 1.2,
    bladeWidth: 0.7,
    sheenStrength: 0.55,
    badgeLight: PracticeRevealPalette.rBadgeLight,
    badgeDeep: PracticeRevealPalette.rBadgeDeep,
    star: PracticeRevealPalette.rStar,
    starLit: PracticeRevealPalette.rStarLit,
    starShade: PracticeRevealPalette.rStarShade,
    starEdge: PracticeRevealPalette.rStarEdge,
    orb: PracticeRevealPalette.rOrb,
    holo: false,
  );

  static const PracticeRevealTheme sr = PracticeRevealTheme._(
    backTint: PracticeRevealPalette.srBackTint,
    rimDark: PracticeRevealPalette.srRimDark,
    rimMid: PracticeRevealPalette.srRimMid,
    rimHi: PracticeRevealPalette.srRimHi,
    backSpecular: 0.34,
    glow: PracticeRevealPalette.srGlow,
    shockwave: PracticeRevealPalette.srBackTint,
    ambientAlpha: 0.45,
    burstCounts: (high: 160, medium: 80, low: 48),
    burstSpeed: 1.7,
    bladeWidth: 0.8,
    sheenStrength: 0.85,
    badgeLight: PracticeRevealPalette.srBadgeLight,
    badgeDeep: PracticeRevealPalette.srBadgeDeep,
    star: PracticeRevealPalette.srStar,
    starLit: PracticeRevealPalette.srStarLit,
    starShade: PracticeRevealPalette.srStarShade,
    starEdge: PracticeRevealPalette.srStarEdge,
    orb: PracticeRevealPalette.srOrb,
    holo: true,
  );

  static PracticeRevealTheme of(PracticeGirlRarity rarity) {
    switch (rarity) {
      case PracticeGirlRarity.n:
        return n;
      case PracticeGirlRarity.r:
        return r;
      case PracticeGirlRarity.sr:
        return sr;
    }
  }
}

/// 環境光、環境星塵跟著卡背染色走的顏色（典藏材質 P3 起卡背本身由 `PracticeCardBackPainter`
/// 畫，這裡只剩卡外光效用的顏色）。等待期與 N 全程是銀；R 只會銀 → 藍；SR 才會再藍 → 金
/// （[practiceRevealDye] 保證只升到真實稀有度）。
@immutable
class PracticeRevealBackColors {
  const PracticeRevealBackColors({
    required this.glow,
    required this.ambientAlpha,
  });

  /// 還沒染色的銀（等待期、N）。
  static final PracticeRevealBackColors silver = PracticeRevealBackColors(
    glow: PracticeRevealTheme.n.glow,
    ambientAlpha: PracticeRevealTheme.n.ambientAlpha,
  );

  /// [ms]＝揭曉經過的毫秒。
  factory PracticeRevealBackColors.at(double ms, PracticeGirlRarity rarity) {
    final dye = practiceRevealDye(ms, rarity);
    const silverTheme = PracticeRevealTheme.n;
    const blueTheme = PracticeRevealTheme.r;
    const goldTheme = PracticeRevealTheme.sr;
    double mix(double a, double b, double c) =>
        (a + (b - a) * dye.blue) * (1 - dye.gold) + c * dye.gold;
    return PracticeRevealBackColors(
      glow: Color.lerp(
        Color.lerp(silverTheme.glow, blueTheme.glow, dye.blue),
        goldTheme.glow,
        dye.gold,
      )!,
      ambientAlpha: mix(
        silverTheme.ambientAlpha,
        blueTheme.ambientAlpha,
        goldTheme.ambientAlpha,
      ),
    );
  }

  final Color glow;
  final double ambientAlpha;
}
