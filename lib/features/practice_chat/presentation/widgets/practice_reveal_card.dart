// 抽卡揭曉 V3 的卡片外觀（規格 docs/plans/2026-10-15-card-draw-v3-luxury-reveal-spec.md
// §6.4–§6.6）：
// - 卡背：中性石墨銀底圖＋執行時依稀有度染色的徽記／外框遮罩＋預先模糊好的光暈。
// - 卡面：漸層倒角框、照片緩縮、全息掃光、膠囊稀有度牌（烙印前不存在）、兩行毛玻璃
//   資訊欄、只畫亮星。
// 動畫狀態全部由呼叫端算好傳進來（[PracticeRevealFaceState]），這裡只負責畫。
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/practice_reveal_palette.dart';
import '../../domain/entities/practice_girl_profile.dart';
import '../../domain/entities/practice_girl_rarity.dart';
import 'practice_girl_photo.dart';
import 'practice_new_badge.dart';
import 'practice_reveal_painters.dart';
import 'practice_reveal_theme.dart';
import 'practice_reveal_timing.dart';

/// 卡背四張素材（由 `tools/practice-draw-card-back-v3/make_card_back_v3.py` 從原卡背離線產出）。
const String kPracticeRevealBackBaseAsset =
    'assets/images/practice/practice_draw_card_back_v3_base.webp';
const String kPracticeRevealBackEmblemMaskAsset =
    'assets/images/practice/practice_draw_card_back_v3_emblem_mask.webp';
const String kPracticeRevealBackFrameMaskAsset =
    'assets/images/practice/practice_draw_card_back_v3_frame_mask.webp';
const String kPracticeRevealBackGlowAsset =
    'assets/images/practice/practice_draw_card_back_v3_glow.webp';

/// 抽牌一開始就預快取的卡背素材。
const List<String> kPracticeRevealBackAssets = [
  kPracticeRevealBackBaseAsset,
  kPracticeRevealBackEmblemMaskAsset,
  kPracticeRevealBackFrameMaskAsset,
  kPracticeRevealBackGlowAsset,
];

/// 卡背、卡面的外圓角（DESIGN.md §4）。
const double kPracticeRevealCardRadius = 24;

/// 卡面外框粗細與照片內圓角：內圓角取尺度內的 22（≈ 24 − 1.5）。
const double _kFrameWidth = 1.5;
const double _kPhotoRadius = 22;

/// 揭曉當下最多幾顆亮星（SR 4 顆）。
const int _kMaxStars = 4;

/// 卡背：中性石墨銀底圖上，徽記與外框遮罩套稀有度漸層（亮度＝不透明度），光暈圖
/// 染色後墊在線條下面。全部預先做好，執行時只染色、不做模糊（規格 §6.5、§12）。
class PracticeRevealCardBack extends StatelessWidget {
  const PracticeRevealCardBack({
    super.key,
    required this.width,
    required this.height,
    required this.colors,
    required this.emblemGlow,
    required this.frameGlow,
    this.goldFlash = 0,
  });

  final double width;
  final double height;

  /// 染色當下的顏色（銀 → 藍 → 金）。
  final PracticeRevealBackColors colors;

  /// 徽記與星軌線條亮度（0..1）。
  final double emblemGlow;

  /// 外框亮度（0..1）。
  final double frameGlow;

  /// SR 染金那一刻的徽記白色爆閃（0..1）。
  final double goldFlash;

  @override
  Widget build(BuildContext context) {
    final glowAlpha = (0.15 + 0.65 * emblemGlow).clamp(0.0, 1.0);
    return SizedBox(
      key: const ValueKey('practice-draw-ceremony-back'),
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(kPracticeRevealCardRadius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _layer(kPracticeRevealBackBaseAsset),
            _layer(
              kPracticeRevealBackGlowAsset,
              color: colors.glow.withValues(alpha: glowAlpha),
            ),
            ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (rect) => LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [colors.tint, colors.tintDeep],
              ).createShader(rect),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _layer(
                    kPracticeRevealBackFrameMaskAsset,
                    color: Colors.white.withValues(alpha: frameGlow),
                  ),
                  _layer(
                    kPracticeRevealBackEmblemMaskAsset,
                    color: Colors.white.withValues(alpha: emblemGlow),
                  ),
                ],
              ),
            ),
            if (goldFlash > 0.01)
              _layer(
                kPracticeRevealBackEmblemMaskAsset,
                color: Colors.white.withValues(alpha: goldFlash),
              ),
            if (colors.holo > 0.01)
              CustomPaint(painter: _HoloRimPainter(strength: colors.holo)),
          ],
        ),
      ),
    );
  }

  Widget _layer(String asset, {Color? color}) => Image.asset(
        asset,
        fit: BoxFit.fill,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        excludeFromSemantics: true,
        color: color,
        colorBlendMode: color == null ? null : BlendMode.srcIn,
      );
}

/// SR 卡背外框的全息彩虹描邊（α 0.35）。
class _HoloRimPainter extends CustomPainter {
  _HoloRimPainter({required this.strength});

  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(2);
    final alpha = 0.35 * strength;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect,
        const Radius.circular(kPracticeRevealCardRadius - 2),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..shader = SweepGradient(
          colors: [
            PracticeRevealPalette.holoCyan.withValues(alpha: alpha),
            PracticeRevealPalette.holoViolet.withValues(alpha: alpha),
            PracticeRevealPalette.holoPink.withValues(alpha: alpha),
            PracticeRevealPalette.holoCyan.withValues(alpha: alpha),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_HoloRimPainter old) => old.strength != strength;
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
    required this.stampOpacity,
    required this.newTagAppear,
    required this.starScales,
    required this.starPulses,
    required this.overlayOpacity,
    required this.light,
  });

  /// [revealMs]＝揭曉經過的毫秒；收卡中再給 [archiveMs]。
  factory PracticeRevealFaceState.at(double revealMs, {double? archiveMs}) {
    return PracticeRevealFaceState(
      photoScale: practiceRevealPhotoScale(revealMs),
      infoAppear: practiceRevealInfoAppear(revealMs),
      sheenX: practiceRevealSheenX(revealMs),
      stamped: practiceRevealStamped(revealMs),
      stampScale: practiceRevealStampScale(revealMs),
      stampOpacity: practiceRevealStampOpacity(revealMs),
      newTagAppear: practiceRevealNewTagAppear(revealMs),
      starScales: [
        for (var i = 0; i < _kMaxStars; i++)
          practiceRevealStarScale(revealMs, i),
      ],
      starPulses: [
        for (var i = 0; i < _kMaxStars; i++)
          practiceRevealStarPulse(revealMs, i),
      ],
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

  /// 稀有度牌已烙上（之前不存在）。
  final bool stamped;
  final double stampScale;
  final double stampOpacity;

  /// NEW 小標浮現（0..1）；只有新卡會畫。
  final double newTagAppear;

  /// 每顆亮星的縮放與點亮脈衝（只取前 `rarity.stars` 顆）。
  final List<double> starScales;
  final List<double> starPulses;

  /// 收卡時資訊欄、稀有度牌、星星一起淡掉（1 → 0）。
  final double overlayOpacity;

  /// 收卡時卡面疊上的稀有度色光（0 → 1）。
  final double light;
}

/// 卡面：1.5 px 漸層倒角框＋外光、照片緩縮、全息掃光、稀有度牌、毛玻璃資訊欄。
/// 名字單獨成行、基本資訊用「 · 」串：刻意避開練習室 hero 的「名字，年齡」字串。
class PracticeRevealCardFront extends StatelessWidget {
  const PracticeRevealCardFront({
    super.key,
    required this.girl,
    required this.width,
    required this.height,
    required this.state,
    this.isNew,
  });

  final PracticeGirlProfile girl;
  final double width;
  final double height;
  final PracticeRevealFaceState state;

  /// 這次抽到的是不是新角色（V3.1 規格 §5.14）：true 在稀有度牌旁掛 NEW；false＝重複
  /// 角色，資訊欄寫「已收藏」；null＝不知道（抽牌中離開圖鑑又回來），兩個都不畫。
  final bool? isNew;

  @override
  Widget build(BuildContext context) {
    final theme = PracticeRevealTheme.of(girl.rarity);
    final inner = Size(width - 2 * _kFrameWidth, height - 2 * _kFrameWidth);
    final innerRadius = BorderRadius.circular(_kPhotoRadius);
    final infoRise = 12 * (1 - state.infoAppear);
    final infoOpacity = state.infoAppear * state.overlayOpacity;

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Container(
        key: const ValueKey('practice-draw-ceremony-front'),
        width: width,
        height: height,
        padding: const EdgeInsets.all(_kFrameWidth),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(kPracticeRevealCardRadius),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [theme.frameLight, theme.frameDeep, theme.frameLight],
            stops: const [0.0, 0.5, 1.0],
          ),
          boxShadow: [
            BoxShadow(
              color: theme.glow.withValues(alpha: 0.35),
              blurRadius: 24,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: innerRadius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _photo(inner, innerRadius),
              const CustomPaint(painter: _InnerHighlightPainter()),
              if (state.sheenX != null)
                CustomPaint(
                  key: const ValueKey('practice-draw-ceremony-sheen'),
                  painter: PracticeRevealSheenPainter(
                    x: state.sheenX!,
                    strength: theme.sheenStrength,
                    holo: theme.holo,
                  ),
                ),
              if (state.stamped && state.overlayOpacity > 0)
                Positioned(
                  top: 16,
                  left: 16,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Opacity(
                        opacity: state.stampOpacity * state.overlayOpacity,
                        child: Transform.scale(
                          scale: state.stampScale,
                          child: PracticeRevealRarityBadge(
                            rarity: girl.rarity,
                            theme: theme,
                          ),
                        ),
                      ),
                      if (isNew == true && state.newTagAppear > 0) ...[
                        const SizedBox(width: 6),
                        Opacity(
                          opacity: state.newTagAppear * state.overlayOpacity,
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
                      collected: isNew == false,
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

/// 卡面內層 1 px 高光：左上白 @0.28 → 右下透明（倒角框的第二層）。
class _InnerHighlightPainter extends CustomPainter {
  const _InnerHighlightPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(0.5);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(_kPhotoRadius)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.28),
            Colors.white.withValues(alpha: 0),
          ],
          stops: const [0.0, 0.6],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_InnerHighlightPainter old) => false;
}

/// 稀有度牌（D5=A 金屬膠囊）：高 24、左右內距 10、主題漸層底、上緣白色內高光、下緣
/// 深色內陰影、黑色投影。
class PracticeRevealRarityBadge extends StatelessWidget {
  const PracticeRevealRarityBadge({
    super.key,
    required this.rarity,
    required this.theme,
  });

  final PracticeGirlRarity rarity;
  final PracticeRevealTheme theme;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(999);
    return Container(
      key: const ValueKey('practice-draw-ceremony-rarity-badge'),
      height: 24,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [theme.badgeLight, theme.badgeDeep],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 8,
              right: 8,
              height: 1,
              child: ColoredBox(color: Colors.white.withValues(alpha: 0.55)),
            ),
            Positioned(
              bottom: 0,
              left: 8,
              right: 8,
              height: 1,
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.5)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Center(
                widthFactor: 1,
                child: Text(
                  rarity.label,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.brandInk,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                    height: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 資訊欄（D6=A 兩行）：名字一行；基本資訊＋右側亮星一行。毛玻璃不用 BackdropFilter：
/// 在資訊欄範圍內墊一份同位置、同緩縮的照片再模糊，3D transform 裡也正確，也不會和
/// 全螢幕模糊搶 backdrop（規格 §6.6）。
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
    this.collected = false,
  });

  final PracticeGirlProfile girl;
  final PracticeRevealTheme theme;

  /// 重複角色：基本資訊那行最後加「已收藏」（V3.1 規格 §5.14）。基本資訊太長時
  /// （小螢幕、系統字放大）先省略前面，「已收藏」一定整個看得到。
  final bool collected;

  /// 和卡面同一張、同緩縮的照片（模糊後當毛玻璃底）。
  final Widget photo;
  final Size photoSize;

  /// 資訊欄浮出時往下偏移的距離；照片副本反向補回，才會和卡面照片對齊。
  final double photoShift;
  final List<double> starScales;
  final List<double> starPulses;

  @override
  Widget build(BuildContext context) {
    final meta = <String>[
      '${girl.age}',
      if (girl.city.isNotEmpty) girl.city,
      if (girl.professionLabel.isNotEmpty) girl.professionLabel,
    ].join(' · ');
    final metaStyle = AppTypography.caption.copyWith(
      color: Colors.white.withValues(alpha: 0.78),
      fontWeight: FontWeight.w600,
    );
    final radius = BorderRadius.circular(18);
    // 不設 liveRegion：停住時整層已主動唸出抽到誰（儀式的讀屏按鈕），這裡再唸會連唸兩次。
    return ClipRRect(
      key: const ValueKey('practice-draw-ceremony-info'),
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
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: PracticeRevealPalette.infoGlass.withValues(alpha: 0.68),
                borderRadius: radius,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12),
                ),
              ),
            ),
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
                  style: AppTypography.titleLarge.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
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
                      scales: starScales,
                      pulses: starPulses,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 亮星（只畫亮的，D6=A）：16 px、間距 4；每顆有自己的點亮縮放與發光脈衝。
class PracticeRevealStars extends StatelessWidget {
  const PracticeRevealStars({
    super.key,
    required this.count,
    required this.color,
    required this.scales,
    required this.pulses,
  });

  final int count;
  final Color color;
  final List<double> scales;
  final List<double> pulses;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const ValueKey('practice-draw-ceremony-rarity-stars'),
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          SizedBox(
            width: 16,
            height: 16,
            child: Transform.scale(
              scale: i < scales.length ? scales[i] : 1,
              child: Icon(
                Icons.star_rounded,
                size: 16,
                color: color,
                shadows: [
                  Shadow(
                    color: color.withValues(
                      alpha: 0.45 + 0.45 * (i < pulses.length ? pulses[i] : 0),
                    ),
                    blurRadius: 6 + 6 * (i < pulses.length ? pulses[i] : 0),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
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
    // 跟底下的 Text 取一樣的字樣、字級縮放、方向與語系。
    final style = DefaultTextStyle.of(context).style.merge(_style);
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
