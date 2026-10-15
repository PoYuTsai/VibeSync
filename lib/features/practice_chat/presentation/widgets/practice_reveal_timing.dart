// 翻牌揭曉 V3 時間軸的單一真相（儀式 widget 與測試共用）。
// 規格：docs/plans/2026-10-15-card-draw-v3-luxury-reveal-spec.md §4。
//
// 三條有限 controller 各自以起點為 0：
// - drawing：以按下翻牌為 0（[PracticeRevealTiming.intro]／[PracticeRevealTiming.caption]）。
// - revealing：以 R0 為 0＝server 成功回來「且」卡背入場已完成（[PracticeRevealTiming.reveal]）。
// - archiving：以點擊收卡為 0（[PracticeRevealTiming.archive]）。
// 揭曉走完之後是 holding：畫面完全靜止，等使用者點擊，沒有任何計時器。
import 'dart:math' as math;

import 'package:flutter/animation.dart';

import '../../../../core/theme/app_motion.dart';
import '../../domain/entities/practice_girl_rarity.dart';

abstract final class PracticeRevealTiming {
  // ── drawing（以按下翻牌為 0）──
  static const Duration intro = Duration(milliseconds: 500);
  static const double introBackdropEndMs = 300;
  static const double introCardStartMs = 100;
  static const double introCardFadeEndMs = 300;

  /// 等待字樣：server 超過 900 ms 還沒回來才淡入，快的時候根本不出現。
  static const Duration caption = Duration(milliseconds: 1200);
  static const double captionFadeStartMs = 900;

  // ── revealing（以 R0 為 0）──
  static const Duration reveal = Duration(milliseconds: 2700);

  /// 等待呼吸的位置、縮放、亮度在這段內混到蓄力姿態，避免跳格。
  static const double poseBlendMs = 150;
  static const double captionOutMs = 200;
  static const double chargeEndMs = 600;

  /// 蓄力三下輕震（第一下在 R0）。
  static const double chargeTick1Ms = 200;
  static const double chargeTick2Ms = 400;

  /// 卡背染色只升到真實稀有度。R／SR 第一段：銀 → 電光藍，徽記亮度衝到 1.0。
  static const double dyeBlueMs = 600;
  static const double dyeBlueEndMs = 720;

  /// N 不變色，只做一次銀光脈衝（0.80 → 1.00 → 0.85）。
  static const double silverPulsePeakMs = 700;
  static const double silverPulseEndMs = 800;

  /// SR 第二段：藍 → 香檳金，徽記白色爆閃 120 ms，外框疊上全息彩邊。
  static const double dyeGoldMs = 850;
  static const double dyeGoldEndMs = 1000;
  static const double goldFlashMs = 120;
  static const double flipStartMs = 1100;

  /// SR 的 celebrate 三下共 200 ms，提前起手讓第三下重擊落在翻牌峰值。
  static const double srBuildMs = 1150;

  /// 卡片正好側立（yaw 90°）：換面＋光刃＋星塵爆發＋最重的一下觸覺。
  static const double flipPeakMs = 1350;
  static const double flipEndMs = 1800;

  /// 光刃：外暈前 60 ms 張開、之後 190 ms 收掉；SR 另加一道 180 ms 的橫向十字。
  static const double bladeOpenMs = 60;
  static const double bladeMs = 250;
  static const double crossMs = 180;

  /// 翻牌落定前點擊一律不理；落定後點擊＝快轉到資訊全部落位。
  static const double skipFromMs = 1800;
  static const Duration skip = Duration(milliseconds: 180);
  static const double photoZoomStartMs = 1500;

  /// 全息斜向掃光：光帶從卡片左外側（−120%）掃到右外側（+120%）。
  static const double sheenStartMs = 1700;
  static const double sheenEndMs = 2400;
  static const double infoStartMs = 1850;
  static const double infoEndMs = 2150;

  /// 稀有度牌烙印：在這之前牌根本不存在（不先掛別的稀有度）。
  static const double stampStartMs = 2000;
  static const double stampEndMs = 2250;
  static const double stampFadeMs = 100;

  /// 星星逐顆點亮（只畫亮星）：第 i 顆從 2150＋80·i 起跳，每顆 220 ms。
  static const double starsStartMs = 2150;
  static const double starStaggerMs = 80;
  static const double starPopMs = 220;
  static const double hintStartMs = 2400;

  // ── archiving（以點擊收卡為 0）──
  static const Duration archive = Duration(milliseconds: 550);

  /// 收卡第一拍：資訊欄、稀有度牌、星星在 80 ms 內淡掉（同時卡面開始變成光）。
  static const double archiveInfoOutMs = 80;
  static const double collapseEndMs = 150;
  static const double cardFadeStartMs = 60;
  static const double orbAppearStartMs = 90;
  static const double flightStartMs = 150;

  /// 光球落進圖鑑格：圖鑑頁在這一刻點亮那一格。
  static const double landMs = 450;
  static const double orbVanishMs = 60;
  static const double backdropOutStartMs = 150;
  static const double backdropOutEndMs = 500;
  static const double hintOutEndMs = 150;

  /// 找不到目標格時，光球在原地縮到 0 的結束點。
  static const double implodeEndMs = 350;

  /// 收卡路上灑出的星點：各自向外漂 20 px、300 ms 淡掉。
  static const int sparkleCount = 8;
  static const double sparkleLifeMs = 300;

  static double get revealMs => reveal.inMilliseconds.toDouble();
  static double get introMs => intro.inMilliseconds.toDouble();
  static double get captionMs => caption.inMilliseconds.toDouble();
  static double get archiveMs => archive.inMilliseconds.toDouble();

  // ── 曲線（DESIGN.md §6：只用 AppMotion 與 Flutter 內建）──
  static const Curve enter = AppMotion.easeOut;
  static const Curve charge = Curves.easeInOutCubic;

  /// 翻牌前半：等於提案的 cubic-bezier(0.6, -0.28, 0.735, 0.045)，會先往回拉一點再衝。
  static const Curve flipIn = Curves.easeInBack;

  /// 翻牌後半：高阻尼減速；肉眼與提案的 cubic-bezier(0.16, 1, 0.3, 1) 幾乎一樣。
  static const Curve settle = AppMotion.easeOut;

  /// 稀有度牌的撞擊感：略微壓過 1.0 再回彈（DESIGN.md §6：彈感只准 celebrate 檔，
  /// 烙印與星星屬於慶祝時刻）。
  static const Curve stamp = AppMotion.celebrateCurve;
  static const Curve sheen = Curves.easeInOut;
  static const Curve flight = Curves.easeInOutCubic;
}

/// [from]–[to] 區段內的線性進度（0..1）。
double practiceRevealSeg(double ms, double from, double to) =>
    ((ms - from) / (to - from)).clamp(0.0, 1.0);

/// 揭曉卡片姿態，yaw／pitch 單位是度：蓄力縮小後仰 → 翻牌前半加速 → 正好側立 90°
/// → 後半減速落定在 180°（正面朝向使用者）。
({double yaw, double pitch, double scale}) practiceRevealPose(double ms) {
  final charge = PracticeRevealTiming.charge.transform(
    practiceRevealSeg(ms, 0, PracticeRevealTiming.chargeEndMs),
  );
  if (ms < PracticeRevealTiming.flipPeakMs) {
    final flipIn = ms <= PracticeRevealTiming.flipStartMs
        ? 0.0
        : PracticeRevealTiming.flipIn.transform(
            practiceRevealSeg(
              ms,
              PracticeRevealTiming.flipStartMs,
              PracticeRevealTiming.flipPeakMs,
            ),
          );
    // easeInBack 前段略小於 0：卡片先往回拉約 10° 再衝，這是刻意的預備動作。
    return (
      yaw: -8 * charge + 98 * flipIn,
      pitch: 6 * charge,
      scale: 1 - 0.08 * charge,
    );
  }
  final out = PracticeRevealTiming.settle.transform(
    practiceRevealSeg(
      ms,
      PracticeRevealTiming.flipPeakMs,
      PracticeRevealTiming.flipEndMs,
    ),
  );
  return (yaw: 90 + 90 * out, pitch: 6 * (1 - out), scale: 0.92 + 0.08 * out);
}

/// yaw 超過 90° 才畫正面；剛好 90° 卡片側立看不見，由光刃遮住換面。
bool practiceRevealShowsFront(double ms) => practiceRevealPose(ms).yaw > 90;

/// 蓄力亮度（0..1）：蓄力段漸亮，之後維持滿。
double practiceRevealChargeGlow(double ms) =>
    PracticeRevealTiming.charge.transform(
      practiceRevealSeg(ms, 0, PracticeRevealTiming.chargeEndMs),
    );

/// 卡背染色進度：`blue`＝銀 → 電光藍，`gold`＝藍 → 香檳金。只升到真實稀有度：
/// N 兩個都恆 0（全程銀）、R 的 `gold` 恆 0；不做「先金後退回藍」的假動作。
({double blue, double gold}) practiceRevealDye(
  double ms,
  PracticeGirlRarity rarity,
) {
  if (rarity == PracticeGirlRarity.n) return (blue: 0.0, gold: 0.0);
  final blue = PracticeRevealTiming.enter.transform(
    practiceRevealSeg(
      ms,
      PracticeRevealTiming.dyeBlueMs,
      PracticeRevealTiming.dyeBlueEndMs,
    ),
  );
  if (rarity == PracticeGirlRarity.r) return (blue: blue, gold: 0.0);
  final gold = PracticeRevealTiming.enter.transform(
    practiceRevealSeg(
      ms,
      PracticeRevealTiming.dyeGoldMs,
      PracticeRevealTiming.dyeGoldEndMs,
    ),
  );
  return (blue: blue, gold: gold);
}

/// 卡背徽記亮度（0..1）：蓄力 0.35 → 0.80；N 再做一次 0.80 → 1.00 → 0.85 的銀光
/// 脈衝；R／SR 染藍時衝到 1.0 並維持。
double practiceRevealEmblemGlow(double ms, PracticeGirlRarity rarity) {
  final charged = 0.35 + 0.45 * practiceRevealChargeGlow(ms);
  if (ms < PracticeRevealTiming.dyeBlueMs) return charged;
  if (rarity == PracticeGirlRarity.n) {
    if (ms < PracticeRevealTiming.silverPulsePeakMs) {
      return 0.80 +
          0.20 *
              Curves.easeOut.transform(
                practiceRevealSeg(
                  ms,
                  PracticeRevealTiming.dyeBlueMs,
                  PracticeRevealTiming.silverPulsePeakMs,
                ),
              );
    }
    return 1.0 -
        0.15 *
            Curves.easeIn.transform(
              practiceRevealSeg(
                ms,
                PracticeRevealTiming.silverPulsePeakMs,
                PracticeRevealTiming.silverPulseEndMs,
              ),
            );
  }
  return 0.80 +
      0.20 *
          PracticeRevealTiming.enter.transform(
            practiceRevealSeg(
              ms,
              PracticeRevealTiming.dyeBlueMs,
              PracticeRevealTiming.dyeBlueEndMs,
            ),
          );
}

/// 卡背外框亮度（0..1）：蓄力 0.25 → 0.60，之後維持。
double practiceRevealFrameGlow(double ms) =>
    0.25 + 0.35 * practiceRevealChargeGlow(ms);

/// SR 染金那一刻的徽記白色爆閃（0..1）：120 ms，前 30% 衝滿、之後退掉。N／R 恆 0。
double practiceRevealGoldFlash(double ms, PracticeGirlRarity rarity) {
  if (rarity != PracticeGirlRarity.sr) return 0;
  final t = practiceRevealSeg(
    ms,
    PracticeRevealTiming.dyeGoldMs,
    PracticeRevealTiming.dyeGoldMs + PracticeRevealTiming.goldFlashMs,
  );
  if (t <= 0 || t >= 1) return 0;
  return t < 0.3 ? t / 0.3 : 1 - (t - 0.3) / 0.7;
}

/// 卡片背後環境光的放大倍率：1.00 →（染藍）1.15 →（染金）1.35。
double practiceRevealAmbientScale(double ms, PracticeGirlRarity rarity) {
  final dye = practiceRevealDye(ms, rarity);
  return 1 + 0.15 * dye.blue + 0.20 * dye.gold;
}

/// 光刃外暈寬度（0..1，乘上卡寬的一半）：卡片側立後 60 ms 張開、190 ms 收掉。
double practiceRevealBladeWidth(double ms) {
  final t = ms - PracticeRevealTiming.flipPeakMs;
  if (t <= 0 || t >= PracticeRevealTiming.bladeMs) return 0;
  if (t < PracticeRevealTiming.bladeOpenMs) {
    return PracticeRevealTiming.enter
        .transform(t / PracticeRevealTiming.bladeOpenMs);
  }
  return 1 -
      Curves.easeIn.transform(
        (t - PracticeRevealTiming.bladeOpenMs) /
            (PracticeRevealTiming.bladeMs - PracticeRevealTiming.bladeOpenMs),
      );
}

/// 光刃白色核心的粗細（px）：2 → 1；光刃時段外回 0。
double practiceRevealBladeCore(double ms) {
  final t = ms - PracticeRevealTiming.flipPeakMs;
  if (t < 0 || t >= PracticeRevealTiming.bladeMs) return 0;
  return 2 - t / PracticeRevealTiming.bladeMs;
}

/// 光刃白色核心的不透明度：最後 50 ms 淡掉，不會一刀切。
double practiceRevealBladeCoreAlpha(double ms) {
  final t = ms - PracticeRevealTiming.flipPeakMs;
  if (t < 0 || t >= PracticeRevealTiming.bladeMs) return 0;
  return 1 -
      practiceRevealSeg(
        t,
        PracticeRevealTiming.bladeMs - 50,
        PracticeRevealTiming.bladeMs,
      );
}

/// SR 的橫向十字光（0..1）：卡片側立起 180 ms 的鐘形。N／R 恆 0。
double practiceRevealCross(double ms, PracticeGirlRarity rarity) {
  if (rarity != PracticeGirlRarity.sr) return 0;
  final t =
      (ms - PracticeRevealTiming.flipPeakMs) / PracticeRevealTiming.crossMs;
  if (t <= 0 || t >= 1) return 0;
  return math.sin(math.pi * t);
}

/// 全息掃光的光帶位置（以卡寬為單位，−1.2 → +1.2）。時段外回 null＝不畫。
double? practiceRevealSheenX(double ms) {
  if (ms <= PracticeRevealTiming.sheenStartMs ||
      ms >= PracticeRevealTiming.sheenEndMs) {
    return null;
  }
  return -1.2 +
      2.4 *
          PracticeRevealTiming.sheen.transform(
            practiceRevealSeg(
              ms,
              PracticeRevealTiming.sheenStartMs,
              PracticeRevealTiming.sheenEndMs,
            ),
          );
}

/// 稀有度牌已經烙上（在這之前牌不存在）。
bool practiceRevealStamped(double ms) =>
    ms >= PracticeRevealTiming.stampStartMs;

/// 稀有度牌縮放：1.6 → 1.0，略微壓過 1.0 再回彈。
double practiceRevealStampScale(double ms) =>
    1.6 -
    0.6 *
        PracticeRevealTiming.stamp.transform(
          practiceRevealSeg(
            ms,
            PracticeRevealTiming.stampStartMs,
            PracticeRevealTiming.stampEndMs,
          ),
        );

/// 稀有度牌不透明度：烙印的前 100 ms 淡入。
double practiceRevealStampOpacity(double ms) => practiceRevealSeg(
      ms,
      PracticeRevealTiming.stampStartMs,
      PracticeRevealTiming.stampStartMs + PracticeRevealTiming.stampFadeMs,
    );

/// 第 [index] 顆星的起跳時間。
double practiceRevealStarStartMs(int index) =>
    PracticeRevealTiming.starsStartMs +
    PracticeRevealTiming.starStaggerMs * index;

double _starT(double ms, int index) {
  final start = practiceRevealStarStartMs(index);
  return practiceRevealSeg(ms, start, start + PracticeRevealTiming.starPopMs);
}

/// 第 [index] 顆星的縮放：0 → 1.25（前 60%）→ 1.00（後 40%）；起跳前 0＝不畫。
double practiceRevealStarScale(double ms, int index) {
  final t = _starT(ms, index);
  if (t <= 0) return 0;
  if (t < 0.6) return 1.25 * Curves.easeOut.transform(t / 0.6);
  return 1.25 - 0.25 * Curves.easeInOut.transform((t - 0.6) / 0.4);
}

/// 第 [index] 顆星點亮時的一次發光脈衝（0..1）。
double practiceRevealStarPulse(double ms, int index) {
  final t = _starT(ms, index);
  if (t <= 0 || t >= 1) return 0;
  return math.sin(math.pi * t);
}

/// 照片緩縮倍率：翻開時 1.08，1500 ms 起緩縮到 1.00（揭曉結束）。
double practiceRevealPhotoScale(double ms) =>
    1.08 -
    0.08 *
        Curves.easeOut.transform(
          practiceRevealSeg(
            ms,
            PracticeRevealTiming.photoZoomStartMs,
            PracticeRevealTiming.revealMs,
          ),
        );

/// 資訊欄浮出（0..1）。
double practiceRevealInfoAppear(double ms) =>
    PracticeRevealTiming.enter.transform(
      practiceRevealSeg(
        ms,
        PracticeRevealTiming.infoStartMs,
        PracticeRevealTiming.infoEndMs,
      ),
    );

/// 「點擊任意處繼續」淡入（0..1），揭曉結束時正好全亮。
double practiceRevealHintIn(double ms) => PracticeRevealTiming.enter.transform(
      practiceRevealSeg(
        ms,
        PracticeRevealTiming.hintStartMs,
        PracticeRevealTiming.revealMs,
      ),
    );

/// drawing：背景暗化進場（0..1）。失敗時 `_intro` 倒轉，暗化跟著退。
double practiceIntroBackdrop(double ms) => PracticeRevealTiming.enter.transform(
      practiceRevealSeg(ms, 0, PracticeRevealTiming.introBackdropEndMs),
    );

/// drawing：卡背入場進度（0..1），驅動 scale 0.85→1 與 translateY 30→0。
double practiceIntroCard(double ms) => PracticeRevealTiming.enter.transform(
      practiceRevealSeg(
        ms,
        PracticeRevealTiming.introCardStartMs,
        PracticeRevealTiming.introMs,
      ),
    );

/// drawing：卡背不透明度（0..1）。
double practiceIntroCardOpacity(double ms) => practiceRevealSeg(
      ms,
      PracticeRevealTiming.introCardStartMs,
      PracticeRevealTiming.introCardFadeEndMs,
    );

/// drawing：等待字樣淡入（0..1）。
double practiceCaptionIn(double ms) => practiceRevealSeg(
      ms,
      PracticeRevealTiming.captionFadeStartMs,
      PracticeRevealTiming.captionMs,
    );

/// 收卡：資訊欄、稀有度牌、星星先淡掉（1 → 0）。
double practiceArchiveInfoOpacity(double ms) =>
    1 - practiceRevealSeg(ms, 0, PracticeRevealTiming.archiveInfoOutMs);

/// 收卡：卡面疊上的稀有度色徑向光（0 → 1），像整張卡變成光。
double practiceArchiveCardLight(double ms) => Curves.easeInCubic.transform(
      practiceRevealSeg(ms, 0, PracticeRevealTiming.collapseEndMs),
    );

/// 收卡：卡片縮小倍率（1 → 0.15）。
double practiceArchiveCardScale(double ms) =>
    1 -
    0.85 *
        Curves.easeInCubic.transform(
          practiceRevealSeg(ms, 0, PracticeRevealTiming.collapseEndMs),
        );

/// 收卡：卡片本體淡出（1 → 0）。
double practiceArchiveCardOpacity(double ms) =>
    1 -
    practiceRevealSeg(
      ms,
      PracticeRevealTiming.cardFadeStartMs,
      PracticeRevealTiming.collapseEndMs,
    );

/// 收卡：背景暗化退場（1 → 0），底下的圖鑑慢慢清楚。
double practiceArchiveBackdrop(double ms) =>
    1 -
    Curves.easeOut.transform(
      practiceRevealSeg(
        ms,
        PracticeRevealTiming.backdropOutStartMs,
        PracticeRevealTiming.backdropOutEndMs,
      ),
    );

/// 收卡：光球沿路徑的參數 t（0..1）。
double practiceArchiveFlightT(double ms) =>
    PracticeRevealTiming.flight.transform(
      practiceRevealSeg(
        ms,
        PracticeRevealTiming.flightStartMs,
        PracticeRevealTiming.landMs,
      ),
    );

/// 收卡：光球核心半徑（px）。90–150 ms 在卡片中心從 14 長到 18，飛行中縮到 10。
double practiceArchiveOrbRadius(double ms) {
  if (ms < PracticeRevealTiming.orbAppearStartMs) return 0;
  if (ms < PracticeRevealTiming.flightStartMs) {
    return 14 +
        4 *
            PracticeRevealTiming.enter.transform(
              practiceRevealSeg(
                ms,
                PracticeRevealTiming.orbAppearStartMs,
                PracticeRevealTiming.flightStartMs,
              ),
            );
  }
  return 18 - 8 * practiceArchiveFlightT(ms);
}

/// 收卡：第 [index] 顆星點（1..8）灑出的時間＝光球的路徑參數 t 經過 0.1·index 那一刻。
double practiceArchiveSparkleSpawnMs(int index) {
  final target = 0.1 * index;
  // 飛行曲線單調遞增：二分法反解線性進度，再換回毫秒。
  var lo = 0.0;
  var hi = 1.0;
  for (var i = 0; i < 24; i++) {
    final mid = (lo + hi) / 2;
    if (PracticeRevealTiming.flight.transform(mid) < target) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return PracticeRevealTiming.flightStartMs +
      (PracticeRevealTiming.landMs - PracticeRevealTiming.flightStartMs) *
          ((lo + hi) / 2);
}

/// 收卡弧線的控制點：弦的中點沿法向量偏 0.35×弦長，取水平方向較靠近畫面中線的
/// 那一側（弧線不會飛出螢幕），再夾在畫面內縮 24 px 的範圍內。
Offset practiceArchiveControlPoint(Offset p0, Offset p2, Size stage) {
  final d = p2 - p0;
  final len = d.distance;
  if (len < 1) return p0;
  final n = Offset(-d.dy / len, d.dx / len);
  final mid = (p0 + p2) / 2;
  final a = mid + n * (0.35 * len);
  final b = mid - n * (0.35 * len);
  final cx = stage.width / 2;
  final p1 = (a.dx - cx).abs() <= (b.dx - cx).abs() ? a : b;
  const inset = 24.0;
  return Offset(
    p1.dx.clamp(inset, math.max(inset, stage.width - inset)),
    p1.dy.clamp(inset, math.max(inset, stage.height - inset)),
  );
}

/// 二次貝茲曲線上參數 [t] 的點。
Offset practiceQuadBezier(Offset p0, Offset p1, Offset p2, double t) {
  final u = 1 - t;
  return p0 * (u * u) + p1 * (2 * u * t) + p2 * (t * t);
}

/// 二次貝茲曲線在參數 [t] 的切線方向（未正規化）。
Offset practiceQuadBezierTangent(Offset p0, Offset p1, Offset p2, double t) =>
    (p1 - p0) * (2 * (1 - t)) + (p2 - p1) * (2 * t);
