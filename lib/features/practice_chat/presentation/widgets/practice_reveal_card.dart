// 抽卡揭曉 V3 的卡片外觀（規格 docs/plans/2026-10-15-card-draw-v3-luxury-reveal-spec.md
// §6.4–§6.6）：
// - 卡背：典藏材質（docs/plans/2026-10-28-card-collectible-material-spec.md §6）的 N／R／SR 成品圖，
//   執行時只做轉化擴散、跟著姿態走的光、SR 全息與額外發光（[PracticeCardBackPainter]）；徽記白光
//   沿用 V3.1（docs/plans/2026-10-17-card-draw-v3-1-polish-spec.md §5.2）。
// - 卡面：照片緩縮、全息掃光、六角金屬稀有度牌（V3.1 §5.10：從畫面外飛進來，出現前不存在）、
//   兩行資訊欄、只畫亮星（V3.1 §5.11 加四芒星光）。典藏材質（docs/plans/2026-10-28-card-collectible-
//   material-spec.md §7）：2 pt 拋光金屬外框、拉絲銀面＋拋光倒角的六角牌（收進卡片內）、煙燻玻璃
//   資訊欄（名字 24、基本資訊 15）、十面切面金屬星；外框受光點與玻璃反光跟著卡片姿態走。
// 動畫狀態全部由呼叫端算好傳進來（[PracticeRevealFaceState]、[PracticeCardLight]），這裡只負責畫。
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/practice_reveal_palette.dart';
import '../../domain/entities/practice_girl_profile.dart';
import '../../domain/entities/practice_girl_rarity.dart';
import 'practice_card_material.dart';
import 'practice_girl_photo.dart';
import 'practice_new_badge.dart';
import 'practice_reveal_painters.dart';
import 'practice_reveal_theme.dart';
import 'practice_reveal_timing.dart';

/// V3 卡背素材（`tools/practice-draw-card-back-v3/make_card_back_v3.py` 從原卡背離線產出）。典藏
/// 材質 P3 起執行時改用 [PracticeCardMaterialSlot] 的 v4 素材；這五張還是 v4 描圖與底面煙霧質感
/// 的來源，等真機驗收通過後的清理那一刀（規格 §13.3）連同檔案一起移走。
const String kPracticeRevealBackBaseAsset =
    'assets/images/practice/practice_draw_card_back_v3_base.webp';
const String kPracticeRevealBackEmblemMaskAsset =
    'assets/images/practice/practice_draw_card_back_v3_emblem_mask.webp';
const String kPracticeRevealBackFrameMaskAsset =
    'assets/images/practice/practice_draw_card_back_v3_frame_mask.webp';
const String kPracticeRevealBackGlowAsset =
    'assets/images/practice/practice_draw_card_back_v3_glow.webp';
const String kPracticeRevealBackLinesMaskAsset =
    'assets/images/practice/practice_draw_card_back_v3_lines_mask.webp';

/// 抽牌一開始就預快取的光效貼圖（卡背素材由 [PracticeCardMaterialLoader] 解碼）。
const List<String> kPracticeRevealSpriteAssets = [
  kPracticeRevealBloomAsset,
  kPracticeRevealSparkleAsset,
  kPracticeRevealParticleAsset,
];

/// 卡背、卡面的外圓角（DESIGN.md §4）。
const double kPracticeRevealCardRadius = 24;

/// 照片內圓角：外圓角 24 減掉 2 pt 拋光外框（典藏材質規格 §7.1）。
const double _kPhotoRadius = 22;

/// 揭曉當下最多幾顆亮星（SR 4 顆）。
const int _kMaxStars = 4;

/// 切面星的大小與間距（典藏材質規格 §7.7、M6：照示意圖 18＋6，中心距跟 V3.1 一樣是 24）。
const double _kStarSize = 18;
const double _kStarGap = 6;

/// 星星點亮時的四芒星光直徑。
const double _kStarSparkleSize = 28;

/// 六角牌（典藏材質規格 §7.3）：寬＝0.20×卡寬、夾在 60–80 pt；高＝0.62×牌寬。
const double kPracticeRevealBadgeWidthFactor = 0.20;
const double _kBadgeMinWidth = 60;
const double _kBadgeMaxWidth = 80;
const double _kBadgeHeightFactor = 0.62;

/// 六角牌落定的位置：收進卡片內，離左緣 12、上緣 16（M4 照示意圖；V3.1 K2 原本是超出卡片
/// 左上角 12 px）。
const Offset kPracticeRevealBadgeInset = Offset(12, 16);

/// 卡寬 [cardWidth] 對應的六角牌寬。
double practiceRevealBadgeWidth(double cardWidth) =>
    (cardWidth * kPracticeRevealBadgeWidthFactor)
        .clamp(_kBadgeMinWidth, _kBadgeMaxWidth);

/// 六角牌落定時的中心點（相對卡片左上角）：SR 落地的小光環以它為圓心。
Offset practiceRevealBadgeCenter(Size card) {
  final width = practiceRevealBadgeWidth(card.width);
  return kPracticeRevealBadgeInset +
      Offset(width / 2, width * _kBadgeHeightFactor / 2);
}

/// 徽記白光的泛光大小（相對卡寬）：徽記約 0.35×卡寬，泛光取 1.8 倍。
const double _kEmblemBloomFactor = 0.63;

/// 卡背（典藏材質規格 §6）：離線渲染好的 N／R／SR 成品圖，加上執行時的轉化擴散、跟著姿態走的
/// 光、SR 全息與額外發光（[PracticeCardBackPainter]），圓角裁切後壓 2 pt 拋光外框（§6.7，顏色
/// 跟著染色走、SR 染金後加全息邊）；徽記白光另疊一張預先模糊好的泛光（V3.1 §5.2）。動畫狀態
/// 全部由呼叫端算好傳進來，這裡只負責畫。
class PracticeRevealCardBack extends StatelessWidget {
  const PracticeRevealCardBack({
    super.key,
    required this.width,
    required this.height,
    required this.images,
    this.dye = (blue: 0.0, gold: 0.0),
    this.light = PracticeCardLight.settled,
    this.energy = PracticeCardBackEnergy.none,
    this.emblemWhite = 0,
  });

  final double width;
  final double height;

  /// 解碼好的卡背素材；還沒好時畫深色底（§6.8），不留白、不丟例外。
  final PracticeCardMaterialImages images;

  /// 染色進度（[practiceRevealDye]）：銀 → 藍 → 金，只升到真實稀有度。等待期與 N 全程是 0。
  final ({double blue, double gold}) dye;

  /// 這一刻的光（卡片姿態算出來的，§6.4）；等待基準姿態算出來就是 [PracticeCardLight.settled]。
  final PracticeCardLight light;

  /// 靜止值以外的額外發光（§6.6）。
  final PracticeCardBackEnergy energy;

  /// 徽記白光（0..1，V3.1 §5.2）：徽記遮罩填白，再疊一張白色泛光。
  final double emblemWhite;

  @override
  Widget build(BuildContext context) {
    const n = PracticeRevealTheme.n;
    const r = PracticeRevealTheme.r;
    const sr = PracticeRevealTheme.sr;
    Color mix(Color silver, Color blue, Color gold) =>
        Color.lerp(Color.lerp(silver, blue, dye.blue), gold, dye.gold)!;
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    return CustomPaint(
      foregroundPainter: PracticeCardRimPainter(
        dark: mix(n.rimDark, r.rimDark, sr.rimDark),
        mid: mix(n.rimMid, r.rimMid, sr.rimMid),
        hi: mix(n.rimHi, r.rimHi, sr.rimHi),
        light: light,
        holo: dye.gold > 0,
        holoStrength: dye.gold,
        // 成品圖自己有一圈槍鐵暗帶，拋光框壓在它最外側（§6.7），不另畫內緣暗線。
        innerLine: false,
        radius: kPracticeRevealCardRadius,
      ),
      child: SizedBox(
        key: const ValueKey('practice-draw-ceremony-back'),
        width: width,
        height: height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(kPracticeRevealCardRadius),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                painter: PracticeCardBackPainter(
                  images: images,
                  dye: dye,
                  light: light,
                  energy: energy,
                  emblemWhite: emblemWhite,
                  tier: practiceRevealEffectTier,
                  grainScale: 1 / dpr,
                ),
              ),
              if (emblemWhite > 0.01)
                Center(
                  child: Image.asset(
                    kPracticeRevealBloomAsset,
                    key: const ValueKey('practice-draw-ceremony-emblem-white'),
                    width: width * _kEmblemBloomFactor,
                    height: width * _kEmblemBloomFactor,
                    fit: BoxFit.fill,
                    gaplessPlayback: true,
                    excludeFromSemantics: true,
                    color: Colors.white.withValues(alpha: 0.9 * emblemWhite),
                    colorBlendMode: BlendMode.srcIn,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 卡面在揭曉／收卡時間軸上某一刻的狀態。
@immutable
class PracticeRevealFaceState {
  const PracticeRevealFaceState({
    required this.photoScale,
    required this.infoAppear,
    required this.sheenX,
    required this.stamped,
    required this.stampScale,
    required this.stampOffset,
    required this.newTagAppear,
    required this.starScales,
    required this.starPulses,
    required this.starMs,
    required this.overlayOpacity,
    required this.light,
  });

  /// [revealMs]＝揭曉經過的毫秒；收卡中再給 [archiveMs]。[stampFrom]＝稀有度牌飛入的起點
  /// 相對落點的位移（卡片座標；儀式依螢幕位置算好傳進來，預設不飛）。
  factory PracticeRevealFaceState.at(
    double revealMs, {
    double? archiveMs,
    Offset stampFrom = Offset.zero,
  }) {
    return PracticeRevealFaceState(
      photoScale: practiceRevealPhotoScale(revealMs),
      infoAppear: practiceRevealInfoAppear(revealMs),
      sheenX: practiceRevealSheenX(revealMs),
      stamped: practiceRevealStamped(revealMs),
      stampScale: practiceRevealStampScale(revealMs),
      stampOffset: stampFrom * (1 - practiceRevealStampFlight(revealMs)),
      newTagAppear: practiceRevealNewTagAppear(revealMs),
      starScales: [
        for (var i = 0; i < _kMaxStars; i++)
          practiceRevealStarScale(revealMs, i),
      ],
      starPulses: [
        for (var i = 0; i < _kMaxStars; i++)
          practiceRevealStarPulse(revealMs, i),
      ],
      starMs: revealMs,
      overlayOpacity:
          archiveMs == null ? 1 : practiceArchiveInfoOpacity(archiveMs),
      light: archiveMs == null ? 0 : practiceArchiveCardLight(archiveMs),
    );
  }

  /// 揭曉走完、停住時的樣子。
  static final PracticeRevealFaceState settled =
      PracticeRevealFaceState.at(PracticeRevealTiming.revealMs);

  final double photoScale;

  /// 資訊欄浮出（0..1）。
  final double infoAppear;

  /// 全息掃光位置；null＝不畫。
  final double? sheenX;

  /// 稀有度牌已出現（之前不存在）。
  final bool stamped;
  final double stampScale;

  /// 稀有度牌離落點還有多遠（飛行中；落地後是 0）。
  final Offset stampOffset;

  /// NEW 小標浮現（0..1）；只有新卡會畫。
  final double newTagAppear;

  /// 每顆亮星的縮放與點亮脈衝（只取前 `rarity.stars` 顆）。
  final List<double> starScales;
  final List<double> starPulses;

  /// 星星的四芒星光與小光點用的揭曉時間（ms）。
  final double starMs;

  /// 收卡時資訊欄、稀有度牌、星星一起淡掉（1 → 0）。
  final double overlayOpacity;

  /// 收卡時卡面疊上的稀有度色光（0 → 1）。
  final double light;
}

/// 卡面：2 pt 拋光金屬外框＋外光、照片緩縮、全息掃光、稀有度牌、煙燻玻璃資訊欄。
/// 名字單獨成行、基本資訊用「 · 」串：刻意避開練習室 hero 的「名字，年齡」字串。
/// 稀有度牌落在卡片左上角內（[kPracticeRevealBadgeInset]），飛入時從畫面外進來，所以畫在
/// 卡片的圓角裁切外面。
class PracticeRevealCardFront extends StatelessWidget {
  const PracticeRevealCardFront({
    super.key,
    required this.girl,
    required this.width,
    required this.height,
    required this.state,
    this.isNew,
    this.light = PracticeCardLight.settled,
  });

  final PracticeGirlProfile girl;
  final double width;
  final double height;
  final PracticeRevealFaceState state;

  /// 這一刻的光（卡片姿態算出來的，典藏材質規格 §6.4）：外框受光點、SR 全息邊、玻璃反光
  /// 跟著它走；停住時是 [PracticeCardLight.settled]。
  final PracticeCardLight light;

  /// 這次抽到的是不是新角色（V3.1 規格 §5.14）：true 在稀有度牌旁掛 NEW；false＝重複
  /// 角色，資訊欄寫「已收藏」；null＝不知道（抽牌中離開圖鑑又回來），兩個都不畫。
  final bool? isNew;

  @override
  Widget build(BuildContext context) {
    final theme = PracticeRevealTheme.of(girl.rarity);
    final inner = Size(
      width - 2 * kPracticeCardRimWidth,
      height - 2 * kPracticeCardRimWidth,
    );
    final innerRadius = BorderRadius.circular(_kPhotoRadius);
    final infoRise = 12 * (1 - state.infoAppear);
    final infoOpacity = state.infoAppear * state.overlayOpacity;

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          _card(theme, inner, innerRadius, infoRise, infoOpacity),
          if (state.stamped && state.overlayOpacity > 0) _stamp(),
        ],
      ),
    );
  }

  Widget _card(
    PracticeRevealTheme theme,
    Size inner,
    BorderRadius innerRadius,
    double infoRise,
    double infoOpacity,
  ) {
    // 拋光外框畫在照片外圈（典藏材質規格 §6.7、§7.1）；外光照舊。
    return CustomPaint(
      foregroundPainter: PracticeCardRimPainter(
        dark: theme.rimDark,
        mid: theme.rimMid,
        hi: theme.rimHi,
        light: light,
        holo: theme.holo,
      ),
      child: Container(
        key: const ValueKey('practice-draw-ceremony-front'),
        width: width,
        height: height,
        padding: const EdgeInsets.all(kPracticeCardRimWidth),
        decoration: BoxDecoration(
          color: theme.rimDark,
          borderRadius: BorderRadius.circular(kPracticeRevealCardRadius),
          boxShadow: [
            BoxShadow(
              color: theme.glow.withValues(alpha: 0.35),
              blurRadius: 24,
            ),
          ],
        ),
        child: _content(theme, inner, innerRadius, infoRise, infoOpacity),
      ),
    );
  }

  Widget _content(
    PracticeRevealTheme theme,
    Size inner,
    BorderRadius innerRadius,
    double infoRise,
    double infoOpacity,
  ) {
    return ClipRRect(
      borderRadius: innerRadius,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _photo(inner, innerRadius),
          if (state.sheenX != null)
            CustomPaint(
              key: const ValueKey('practice-draw-ceremony-sheen'),
              painter: PracticeRevealSheenPainter(
                x: state.sheenX!,
                strength: theme.sheenStrength,
                holo: theme.holo,
              ),
            ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Transform.translate(
              offset: Offset(0, infoRise),
              child: Opacity(
                opacity: infoOpacity,
                child: PracticeRevealInfoBar(
                  girl: girl,
                  theme: theme,
                  photo: _photo(inner, BorderRadius.zero),
                  photoSize: inner,
                  photoShift: infoRise,
                  starScales: state.starScales,
                  starPulses: state.starPulses,
                  starMs: state.starMs,
                  collected: isNew == false,
                  reflection: practiceInfoBarReflection(light),
                ),
              ),
            ),
          ),
          if (state.light > 0.001)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  radius: 0.9,
                  colors: [
                    Colors.white.withValues(alpha: state.light),
                    theme.orb.withValues(alpha: state.light),
                    theme.glow.withValues(alpha: 0.85 * state.light),
                  ],
                  stops: const [0.0, 0.45, 1.0],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 六角牌＋（新卡）NEW：飛行中帶著位移，落地後收在卡片左上角內；NEW 掛在牌右邊 6 px、
  /// 跟牌垂直置中。
  Widget _stamp() {
    return Positioned(
      left: kPracticeRevealBadgeInset.dx + state.stampOffset.dx,
      top: kPracticeRevealBadgeInset.dy + state.stampOffset.dy,
      child: Opacity(
        opacity: state.overlayOpacity,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.scale(
              scale: state.stampScale,
              child: PracticeRevealRarityBadge(
                rarity: girl.rarity,
                width: practiceRevealBadgeWidth(width),
              ),
            ),
            if (isNew == true && state.newTagAppear > 0) ...[
              const SizedBox(width: 6),
              Opacity(
                opacity: state.newTagAppear,
                child: Transform.scale(
                  scale: 0.6 + 0.4 * state.newTagAppear,
                  child: const PracticeNewBadge(
                    key: ValueKey('practice-draw-ceremony-new-tag'),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // 照片緩縮只作用在照片本身（clip 內），卡框不動；縮放中心偏上保住臉。
  Widget _photo(Size size, BorderRadius radius) => Transform.scale(
        scale: state.photoScale,
        alignment: const Alignment(0, -0.3),
        child: PracticeGirlPhoto(
          profile: girl,
          width: size.width,
          height: size.height,
          borderRadius: radius,
        ),
      );
}

/// 稀有度牌（典藏材質規格 §7.3；V3.1 §5.10 K1 的六角牌改版）：拉絲銀面上亮下暗、2 pt 拋光
/// 倒角（SR 金、N／R 銀）、深色壓印字；寬 0.20×卡寬（夾在 60–80 pt）、高 0.62×寬。用路徑與
/// 漸層畫，不加素材；包一層 RepaintBoundary，飛入時只動圖層、不重畫。圖鑑卡的膠囊牌不動。
class PracticeRevealRarityBadge extends StatelessWidget {
  const PracticeRevealRarityBadge({
    super.key,
    required this.rarity,
    required this.width,
  });

  final PracticeGirlRarity rarity;
  final double width;

  @override
  Widget build(BuildContext context) {
    final height = width * _kBadgeHeightFactor;
    return SizedBox(
      key: const ValueKey('practice-draw-ceremony-rarity-badge'),
      width: width,
      height: height,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _HexBadgePainter(gold: rarity == PracticeGirlRarity.sr),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: height * 0.45,
              vertical: height * 0.18,
            ),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  rarity.label,
                  style: AppTypography.headlineMedium.copyWith(
                    color: PracticeRevealPalette.badgeInk,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                    height: 1,
                    // 壓印：字的下緣接到一點光。
                    shadows: [
                      Shadow(
                        color: Colors.white.withValues(alpha: 0.5),
                        offset: const Offset(0, 0.75),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 牌左右兩個尖角往內收的距離（相對牌高）：0.27 照示意圖。
const double _kHexPointInset = 0.27;

/// 拋光倒角的寬度（§7.3）。
const double _kHexBevel = 2;

/// 牌面拉絲的線距。
const double _kBrushPitch = 0.5;

Path _hexPath(Rect r) {
  final inset = r.height * _kHexPointInset;
  return Path()
    ..moveTo(r.left + inset, r.top)
    ..lineTo(r.right - inset, r.top)
    ..lineTo(r.right, r.center.dy)
    ..lineTo(r.right - inset, r.bottom)
    ..lineTo(r.left + inset, r.bottom)
    ..lineTo(r.left, r.center.dy)
    ..close();
}

/// 0..1 的固定雜湊：拉絲每一條的深淺由序號決定，零 Random、每次畫都一樣。
double _brushNoise(int i) {
  final x = math.sin(i * 12.9898) * 43758.5453;
  return x - x.floorToDouble();
}

class _HexBadgePainter extends CustomPainter {
  const _HexBadgePainter({required this.gold});

  /// SR：倒角是拋光香檳金，上緣中央一個受光點。
  final bool gold;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = Offset.zero & size;
    final outerPath = _hexPath(outer);
    canvas.drawShadow(outerPath, Colors.black, 3, false);
    // 倒角：SR 金（示意圖取樣：上亮、左右尖角那個高度最暗、下緣回一點），N／R 銀。
    canvas.drawPath(
      outerPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: gold
              ? const [
                  PracticeRevealPalette.srBadgeBevelHi,
                  PracticeRevealPalette.srBadgeBevelMid,
                  PracticeRevealPalette.srBadgeBevelDeep,
                  PracticeRevealPalette.srBadgeBevelLow,
                ]
              : const [
                  PracticeRevealPalette.badgeMetalLight,
                  PracticeRevealPalette.badgeBevelDeep,
                ],
          stops: gold ? const [0.0, 0.2, 0.55, 1.0] : null,
        ).createShader(outer),
    );
    final face = outer.deflate(_kHexBevel);
    final facePath = _hexPath(face);
    canvas.drawPath(
      facePath,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            PracticeRevealPalette.badgeFaceTop,
            PracticeRevealPalette.badgeFaceMid,
            PracticeRevealPalette.badgeFaceBottom,
          ],
          stops: [0.0, 0.55, 1.0],
        ).createShader(face),
    );
    // 水平拉絲：一條條很淡的亮線與暗線交錯。
    canvas.save();
    canvas.clipPath(facePath);
    var i = 0;
    for (var y = face.top + _kBrushPitch / 2;
        y < face.bottom;
        y += _kBrushPitch, i++) {
      canvas.drawLine(
        Offset(face.left, y),
        Offset(face.right, y),
        Paint()
          ..strokeWidth = _kBrushPitch * 0.6
          ..color = (i.isEven ? Colors.white : Colors.black)
              .withValues(alpha: 0.02 + 0.05 * _brushNoise(i)),
      );
    }
    canvas.restore();
    // 牌面上緣接光的那一道反光：左尖角 → 上緣 → 右尖角。
    final inset = face.height * _kHexPointInset;
    canvas.drawPath(
      Path()
        ..moveTo(face.left + 0.5, face.center.dy)
        ..lineTo(face.left + inset, face.top + 0.5)
        ..lineTo(face.right - inset, face.top + 0.5)
        ..lineTo(face.right - 0.5, face.center.dy),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.85),
    );
    if (gold) {
      // 受光點只落在金屬上（裁在牌的外形裡），不飄到牌外。
      final glint = Offset(outer.center.dx, outer.top + _kHexBevel / 2);
      const radius = 6.0;
      canvas.save();
      canvas.clipPath(outerPath);
      canvas.drawCircle(
        glint,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              Colors.white.withValues(alpha: 0.9),
              Colors.white.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: glint, radius: radius)),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_HexBadgePainter old) => old.gold != gold;
}

/// 煙燻玻璃上那道斜向反光的中心（欄寬比例，典藏材質規格 §7.5）：停住時在 0.72；卡片落定
/// 的過程中從右邊滑進來（跟外框受光點同一個 [PracticeCardLight.band]）。
double practiceInfoBarReflection(PracticeCardLight light) =>
    0.72 + (light.band - PracticeCardLight.settled.band);

/// 資訊欄（D6=A 兩行；典藏材質規格 §7.5–§7.6）：名字一行（24）；基本資訊（15）＋右側亮星
/// 一行。煙燻玻璃不用 BackdropFilter：在資訊欄範圍內墊一份同位置、同緩縮的照片再模糊，
/// 3D transform 裡也正確，也不會和全螢幕模糊搶 backdrop（V3 規格 §6.6）；上面疊中性炭灰、
/// 上緣受光、斜向反光、底部厚度陰影與 1 pt 斜邊。
class PracticeRevealInfoBar extends StatelessWidget {
  const PracticeRevealInfoBar({
    super.key,
    required this.girl,
    required this.theme,
    required this.photo,
    required this.photoSize,
    required this.photoShift,
    required this.starScales,
    required this.starPulses,
    this.starMs,
    this.collected = false,
    this.reflection = 0.72,
  });

  final PracticeGirlProfile girl;
  final PracticeRevealTheme theme;

  /// 揭曉經過的毫秒：給星星點亮時的四芒星光與小光點；null＝不畫。
  final double? starMs;

  /// 重複角色：基本資訊那行最後加「已收藏」（V3.1 規格 §5.14）。基本資訊太長時
  /// （小螢幕、系統字放大）先省略前面，「已收藏」一定整個看得到。
  final bool collected;

  /// 和卡面同一張、同緩縮的照片（模糊後當玻璃後面的底）。
  final Widget photo;
  final Size photoSize;

  /// 資訊欄浮出時往下偏移的距離；照片副本反向補回，才會和卡面照片對齊。
  final double photoShift;
  final List<double> starScales;
  final List<double> starPulses;

  /// 斜向反光的中心（欄寬比例），見 [practiceInfoBarReflection]。
  final double reflection;

  @override
  Widget build(BuildContext context) {
    final meta = <String>[
      '${girl.age}',
      if (girl.city.isNotEmpty) girl.city,
      if (girl.professionLabel.isNotEmpty) girl.professionLabel,
    ].join(' · ');
    final metaStyle = AppTypography.bodyMedium.copyWith(
      color: Colors.white.withValues(alpha: 0.88),
      fontWeight: FontWeight.w500,
    );
    final radius = BorderRadius.circular(18);
    // 不設 liveRegion：停住時整層已主動唸出抽到誰（儀式的讀屏按鈕），這裡再唸會連唸兩次。
    // 只有玻璃底裁在圓角裡；文字與星星不裁，星星點亮的星光可以略超出欄位。
    return Stack(
      key: const ValueKey('practice-draw-ceremony-info'),
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: ClipRRect(
            borderRadius: radius,
            child: Stack(
              children: [
                // 資訊欄在卡面內左右下各內縮 12：照片副本反推回卡面照片的位置。
                Positioned(
                  left: -12,
                  bottom: -12 + photoShift,
                  width: photoSize.width,
                  height: photoSize.height,
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: photo,
                  ),
                ),
                Positioned.fill(
                  child: ColoredBox(
                    color:
                        PracticeRevealPalette.infoSmoke.withValues(alpha: 0.80),
                  ),
                ),
                Positioned.fill(
                  child: CustomPaint(
                    painter: _SmokedGlassPainter(reflection: reflection),
                  ),
                ),
              ],
            ),
          ),
        ),
        const Positioned.fill(
          child: CustomPaint(painter: _GlassEdgePainter()),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                girl.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.headlineMedium.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            meta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: metaStyle,
                          ),
                        ),
                        if (collected)
                          Text(' · 已收藏', maxLines: 1, style: metaStyle),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  PracticeRevealStars(
                    count: girl.rarity.stars,
                    color: theme.star,
                    lit: theme.starLit,
                    shade: theme.starShade,
                    edge: theme.starEdge,
                    scales: starScales,
                    pulses: starPulses,
                    ms: starMs,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 煙燻玻璃的光（§7.5）：上緣受光（白 0.07 → 0，到 45% 高）、115° 斜向反光（白 0.05、寬 30%
/// 欄寬，中心在 [reflection]×欄寬）、底部 6 pt 的厚度陰影（黑 0.22 → 0）。全用漸層。
class _SmokedGlassPainter extends CustomPainter {
  const _SmokedGlassPainter({required this.reflection});

  final double reflection;

  static const double _angle = 115 * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.07),
            Colors.white.withValues(alpha: 0),
          ],
          stops: const [0, 0.45],
        ).createShader(rect),
    );
    if (reflection > -0.3 && reflection < 1.3) {
      final dir = Offset(math.sin(_angle), -math.cos(_angle));
      final center = Offset(reflection * size.width, size.height / 2);
      final half = 0.15 * size.width;
      canvas.drawRect(
        rect,
        Paint()
          ..shader = ui.Gradient.linear(
            center - dir * half,
            center + dir * half,
            [
              Colors.white.withValues(alpha: 0),
              Colors.white.withValues(alpha: 0.05),
              Colors.white.withValues(alpha: 0),
            ],
            const [0, 0.5, 1],
          ),
      );
    }
    final shadow = Rect.fromLTRB(0, size.height - 6, size.width, size.height);
    canvas.drawRect(
      shadow,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.22),
            Colors.black.withValues(alpha: 0),
          ],
        ).createShader(shadow),
    );
  }

  @override
  bool shouldRepaint(_SmokedGlassPainter old) => old.reflection != reflection;
}

/// 煙燻玻璃的斜邊：1 pt 描邊，左上白 0.32 → 右下白 0.10（玻璃厚度朝左上受光）。
class _GlassEdgePainter extends CustomPainter {
  const _GlassEdgePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(18)).deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.32),
            Colors.white.withValues(alpha: 0.10),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_GlassEdgePainter old) => false;
}

/// 亮星（只畫亮的，D6=A；典藏材質規格 §7.7 改成十面切面金屬星）：18 pt、間距 6；每顆有自己的
/// 點亮縮放與發光脈衝，點亮時在星星後面閃一個四芒星光、往外噴 6 顆小光點（V3.1 §5.11）。
class PracticeRevealStars extends StatelessWidget {
  const PracticeRevealStars({
    super.key,
    required this.count,
    required this.color,
    required this.lit,
    required this.shade,
    required this.edge,
    required this.scales,
    required this.pulses,
    this.ms,
  });

  final int count;

  /// 光暈、四芒星光、小光點的顏色。
  final Color color;

  /// 切面的亮面／暗面／邊。
  final Color lit;
  final Color shade;
  final Color edge;
  final List<double> scales;
  final List<double> pulses;

  /// 揭曉經過的毫秒：給四芒星光與小光點；null＝不畫。
  final double? ms;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const ValueKey('practice-draw-ceremony-rarity-stars'),
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: _kStarGap),
          SizedBox(
            key: ValueKey('practice-draw-ceremony-star-$i'),
            width: _kStarSize,
            height: _kStarSize,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                if (_sparkle(i) case final sparkle?)
                  OverflowBox(
                    maxWidth: _kStarSparkleSize,
                    maxHeight: _kStarSparkleSize,
                    child: Transform.rotate(
                      angle: sparkle.turnDeg * math.pi / 180,
                      child: Transform.scale(
                        scale: sparkle.scale,
                        child: Image.asset(
                          kPracticeRevealSparkleAsset,
                          key: ValueKey(
                              'practice-draw-ceremony-star-sparkle-$i'),
                          width: _kStarSparkleSize,
                          height: _kStarSparkleSize,
                          gaplessPlayback: true,
                          excludeFromSemantics: true,
                          color: color.withValues(alpha: sparkle.alpha),
                          colorBlendMode: BlendMode.modulate,
                        ),
                      ),
                    ),
                  ),
                Transform.scale(
                  scale: i < scales.length ? scales[i] : 1,
                  child: CustomPaint(
                    size: const Size.square(_kStarSize),
                    painter: _FacetStarPainter(
                      lit: lit,
                      shade: shade,
                      edge: edge,
                      glow: color,
                      pulse: i < pulses.length ? pulses[i] : 0,
                    ),
                  ),
                ),
                if (ms != null && practiceRevealStarDot(ms!, i, 0) != null)
                  Positioned.fill(
                    child: CustomPaint(
                      painter:
                          _StarDotsPainter(ms: ms!, index: i, color: color),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  ({double alpha, double turnDeg, double scale})? _sparkle(int index) {
    final at = ms;
    return at == null ? null : practiceRevealStarSparkle(at, index);
  }
}

/// 五角星的內外半徑比。
const double _kStarInnerRatio = 0.45;

/// 星心抬高（相對外半徑），讓十個切面有斜度。
const double _kStarLift = 0.35;

/// 主光方向（左上、偏向鏡頭），跟卡面其他材質同一個光。
const List<double> _kStarLight = [-0.5, -0.6, 0.62];

/// 切面星的十個面（典藏材質規格 §7.7）：五個尖角各從星心切成左右兩面。[light] 是這一面
/// 對左上主光的亮度，已拉成 0（最暗的面）..1（最亮的面）。
@visibleForTesting
List<({List<Offset> points, double light})> practiceFacetStar(
  Offset center,
  double radius,
) {
  final lightLen = math.sqrt(_kStarLight.fold<double>(0, (s, v) => s + v * v));
  final l = [for (final v in _kStarLight) v / lightLen];
  final lift = _kStarLift * radius;
  Offset at(double r, double deg) =>
      center +
      Offset(math.cos(deg * math.pi / 180), math.sin(deg * math.pi / 180)) * r;
  final faces = <({List<Offset> points, double raw})>[];
  for (var k = 0; k < 5; k++) {
    final tipDeg = -90.0 + 72 * k;
    final tip = at(radius, tipDeg);
    for (final side in [
      at(radius * _kStarInnerRatio, tipDeg - 36),
      at(radius * _kStarInnerRatio, tipDeg + 36),
    ]) {
      // 星心（抬高）、尖角、內角三點的面法線，朝向鏡頭那一側。
      final ax = tip.dx - center.dx, ay = tip.dy - center.dy, az = -lift;
      final bx = side.dx - center.dx, by = side.dy - center.dy, bz = -lift;
      var nx = ay * bz - az * by;
      var ny = az * bx - ax * bz;
      var nz = ax * by - ay * bx;
      if (nz < 0) {
        nx = -nx;
        ny = -ny;
        nz = -nz;
      }
      final len = math.sqrt(nx * nx + ny * ny + nz * nz);
      faces.add((
        points: [center, tip, side],
        raw: (nx * l[0] + ny * l[1] + nz * l[2]) / len,
      ));
    }
  }
  final lo = faces.map((f) => f.raw).reduce(math.min);
  final hi = faces.map((f) => f.raw).reduce(math.max);
  return [
    for (final f in faces)
      (
        points: f.points,
        light: hi - lo < 1e-9 ? 1.0 : (f.raw - lo) / (hi - lo)
      ),
  ];
}

class _FacetStarPainter extends CustomPainter {
  const _FacetStarPainter({
    required this.lit,
    required this.shade,
    required this.edge,
    required this.glow,
    required this.pulse,
  });

  final Color lit;
  final Color shade;
  final Color edge;
  final Color glow;

  /// 點亮那一下的發光脈衝（0..1）。
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    // 光暈：星星後面一個徑向漸層（半徑 0.9×星寬，不用 MaskFilter.blur）。
    final glowRadius = radius * 1.8;
    canvas.drawCircle(
      center,
      glowRadius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            glow.withValues(alpha: 0.25 + 0.35 * pulse),
            glow.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: glowRadius)),
    );
    final outline = Path();
    for (final face in practiceFacetStar(center, radius)) {
      final path = Path()..addPolygon(face.points, true);
      canvas.drawPath(
          path, Paint()..color = Color.lerp(shade, lit, face.light)!);
    }
    for (var k = 0; k < 10; k++) {
      final r = k.isEven ? radius : radius * _kStarInnerRatio;
      final deg = -90.0 + 36 * k;
      final p = center +
          Offset(math.cos(deg * math.pi / 180), math.sin(deg * math.pi / 180)) *
              r;
      k == 0 ? outline.moveTo(p.dx, p.dy) : outline.lineTo(p.dx, p.dy);
    }
    outline.close();
    canvas.drawPath(
      outline,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.75
        ..strokeJoin = StrokeJoin.round
        ..color = edge.withValues(alpha: 0.6),
    );
    canvas.drawCircle(
      center + Offset(-0.06, -0.08) * radius,
      radius * 0.14,
      Paint()..color = Colors.white.withValues(alpha: 0.7),
    );
  }

  @override
  bool shouldRepaint(_FacetStarPainter old) =>
      old.lit != lit ||
      old.shade != shade ||
      old.edge != edge ||
      old.glow != glow ||
      old.pulse != pulse;
}

/// 星星點亮時往外噴的 6 顆小光點（直徑 3 px）。
class _StarDotsPainter extends CustomPainter {
  const _StarDotsPainter({
    required this.ms,
    required this.index,
    required this.color,
  });

  final double ms;
  final int index;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    for (var dot = 0; dot < PracticeRevealTiming.starDotCount; dot++) {
      final d = practiceRevealStarDot(ms, index, dot);
      if (d == null) continue;
      canvas.drawCircle(
        center + d.offset,
        1.5,
        Paint()..color = color.withValues(alpha: d.alpha),
      );
    }
  }

  @override
  bool shouldRepaint(_StarDotsPainter old) =>
      old.ms != ms || old.index != index || old.color != color;
}

// 角色第一句話對話框的尺寸（版面計算與 widget 共用單一真相）。字級用內文 15
// （`AppTypography.bodyMedium`，行高 1.4），內距照 DESIGN.md §3、§5 的尺度。
const double _kIntroNibWidth = 14;
const double _kIntroNibHeight = 6;
const double _kIntroPaddingH = 16;
const double _kIntroPaddingV = 8;
const double _kIntroRadius = 18;
const TextStyle _kIntroTextStyle = AppTypography.bodyMedium;

/// 卡片下緣到提示字之間的 [available] 高度放得下幾行第一句話：0＝不顯示，最多 2 行
/// （V3.1 規格 §5.13）。字級跟著系統字級放大，行高用 [scaler] 換算。
int practiceIntroBubbleLines(double available, TextScaler scaler) {
  final line =
      scaler.scale(_kIntroTextStyle.fontSize!) * _kIntroTextStyle.height!;
  final chrome = _kIntroNibHeight + 2 * _kIntroPaddingV;
  return ((available - chrome) / line).floor().clamp(0, 2);
}

/// 兩行時把字的寬度收到「還是兩行」的最窄寬度：兩行差不多長，不會只剩一兩個字掉到第二行
/// （同 CSS 的 `text-wrap: balance`）。一行放得下，或兩行也放不下要省略時，照 [maxWidth]。
/// [style]、[locale] 要跟實際畫字的 `Text` 一樣（合併過 DefaultTextStyle），折行才會一致。
double practiceIntroBalancedWidth({
  required String text,
  required TextStyle style,
  required TextScaler textScaler,
  required TextDirection textDirection,
  required int maxLines,
  required double maxWidth,
  Locale? locale,
}) {
  if (maxLines < 2 || !maxWidth.isFinite) return maxWidth;
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textAlign: TextAlign.center,
    textDirection: textDirection,
    textScaler: textScaler,
    maxLines: maxLines,
    locale: locale,
  );
  try {
    painter.layout(maxWidth: maxWidth);
    final lines = painter.computeLineMetrics().length;
    if (lines < 2 || painter.didExceedMaxLines) return maxWidth;
    // 寬度砍半一定排不下（整句比 maxWidth 長才會折行），在兩者之間找最窄的寬度。
    var narrow = maxWidth / lines;
    var wide = maxWidth;
    while (wide - narrow > 0.5) {
      final mid = (narrow + wide) / 2;
      painter.layout(maxWidth: mid);
      if (painter.didExceedMaxLines ||
          painter.computeLineMetrics().length > lines) {
        narrow = mid;
      } else {
        wide = mid;
      }
    }
    // 多留 1 px，逐字打出時兩段文字排版的些微誤差不會讓它多折一行。
    return math.min(wide + 1, maxWidth);
  } finally {
    painter.dispose();
  }
}

/// 角色第一句話（V3.1 規格 §5.13）：卡片下方的半透明深色小對話框，上緣尖角指向卡片；
/// 外框跟資訊欄同一圈淡白邊，N／R 的深色背景上才看得出是對話框。
/// 逐字打出時整句先排好、還沒打到的字透明，換行位置從頭到尾不跳；兩行時兩行等長。
/// 讀屏不另外唸：停住時儀式的讀屏按鈕已經接上這句話。
class PracticeRevealIntroBubble extends StatefulWidget {
  const PracticeRevealIntroBubble({
    super.key,
    required this.text,
    required this.typed,
    required this.maxLines,
  });

  final String text;

  /// 打出來的比例（0..1），以字形叢集計，emoji 不會被切半。
  final double typed;
  final int maxLines;

  @override
  State<PracticeRevealIntroBubble> createState() =>
      _PracticeRevealIntroBubbleState();
}

class _PracticeRevealIntroBubbleState extends State<PracticeRevealIntroBubble> {
  static final TextStyle _style = _kIntroTextStyle.copyWith(
    color: Colors.white.withValues(alpha: 0.92),
    fontWeight: FontWeight.w600,
  );

  // 逐字打出時每一幀都會重建；兩行等長的寬度只在字、可用寬度、字樣或行數變了才重算。
  Object? _widthKey;
  double _textWidth = 0;

  double _balancedWidth(BuildContext context, double maxWidth) {
    // 跟底下的 Text 取一樣的字樣、字級縮放、方向與語系（含系統「粗體文字」）。
    var style = DefaultTextStyle.of(context).style.merge(_style);
    if (MediaQuery.boldTextOf(context)) {
      style = style.merge(const TextStyle(fontWeight: FontWeight.bold));
    }
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final locale = Localizations.maybeLocaleOf(context);
    final key = (
      widget.text,
      maxWidth,
      style,
      scaler,
      direction,
      locale,
      widget.maxLines
    );
    if (key != _widthKey) {
      _widthKey = key;
      _textWidth = practiceIntroBalancedWidth(
        text: widget.text,
        style: style,
        textScaler: scaler,
        textDirection: direction,
        maxLines: widget.maxLines,
        maxWidth: maxWidth,
        locale: locale,
      );
    }
    return _textWidth;
  }

  @override
  Widget build(BuildContext context) {
    final chars = widget.text.characters;
    final shown = (widget.typed * chars.length).ceil().clamp(0, chars.length);
    return ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, constraints) => CustomPaint(
          painter: const _IntroBubblePainter(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              _kIntroPaddingH,
              _kIntroNibHeight + _kIntroPaddingV,
              _kIntroPaddingH,
              _kIntroPaddingV,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: _balancedWidth(
                  context,
                  math.max(0.0, constraints.maxWidth - 2 * _kIntroPaddingH),
                ),
              ),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: chars.take(shown).toString()),
                    TextSpan(
                      text: chars.skip(shown).toString(),
                      style: const TextStyle(color: Colors.transparent),
                    ),
                  ],
                ),
                key: const ValueKey('practice-draw-ceremony-intro-text'),
                maxLines: widget.maxLines,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: _style,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 對話框外形：圓角框加上緣置中的小尖角畫成同一條路徑，先填色再描邊，
/// 尖角跟框之間不會有接縫線。
class _IntroBubblePainter extends CustomPainter {
  const _IntroBubblePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    const top = _kIntroNibHeight;
    // 一行字時框高不到 36，圓角收成一半高（膠囊），跟 BoxDecoration 的圓角一樣。
    final r = math.min(_kIntroRadius, math.min((h - top) / 2, w / 2));
    final corner = Radius.circular(r);
    final cx = w / 2;
    final nib = math.min(_kIntroNibWidth / 2, math.max(0.0, cx - r));
    final path = Path()
      ..moveTo(cx - nib, top)
      ..lineTo(cx, 0)
      ..lineTo(cx + nib, top)
      ..lineTo(w - r, top)
      ..arcToPoint(Offset(w, top + r), radius: corner)
      ..lineTo(w, h - r)
      ..arcToPoint(Offset(w - r, h), radius: corner)
      ..lineTo(r, h)
      ..arcToPoint(Offset(0, h - r), radius: corner)
      ..lineTo(0, top + r)
      ..arcToPoint(Offset(r, top), radius: corner)
      ..close();
    canvas.drawPath(
      path,
      Paint()..color = PracticeRevealPalette.infoGlass.withValues(alpha: 0.82),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.12),
    );
  }

  @override
  bool shouldRepaint(_IntroBubblePainter old) => false;
}
