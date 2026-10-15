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
  static const double flipStartMs = 1100;

  /// SR 的 celebrate 三下共 200 ms，提前起手讓第三下重擊落在翻牌峰值。
  static const double srBuildMs = 1150;

  /// 卡片正好側立（yaw 90°）：換面＋閃光＋最重的一下觸覺。
  static const double flipPeakMs = 1350;
  static const double flipEndMs = 1800;

  /// 翻牌落定前點擊一律不理；落定後點擊＝快轉到資訊全部落位。
  static const double skipFromMs = 1800;
  static const Duration skip = Duration(milliseconds: 180);
  static const double photoZoomStartMs = 1500;
  static const double infoStartMs = 1850;
  static const double infoEndMs = 2150;
  static const double hintStartMs = 2400;

  // ── archiving（以點擊收卡為 0）──
  static const Duration archive = Duration(milliseconds: 550);
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

/// yaw 超過 90° 才畫正面；剛好 90° 卡片側立看不見，由閃光遮住換面。
bool practiceRevealShowsFront(double ms) => practiceRevealPose(ms).yaw > 90;

/// 蓄力亮度（0..1）：蓄力段漸亮，之後維持滿。
double practiceRevealChargeGlow(double ms) =>
    PracticeRevealTiming.charge.transform(
      practiceRevealSeg(ms, 0, PracticeRevealTiming.chargeEndMs),
    );

/// 翻牌峰值閃光：以側立那一刻為中心的窄鐘形。
double practiceRevealFlipFlash(double ms) {
  final d = (ms - PracticeRevealTiming.flipPeakMs) / 110;
  return math.exp(-d * d);
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
