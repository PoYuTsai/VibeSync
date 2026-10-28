// 抽卡卡片典藏材質的共用件（規格 docs/plans/2026-10-28-card-collectible-material-spec.md）：
// - [practiceCardLight]：從卡片姿態算出這一刻的光（§6.4）。卡片怎麼轉，高光、受光點、
//   全息色帶就怎麼走；姿態不動（停住），光就不動，不增加動畫幀。
// - [PracticeCardRimPainter]：卡背、卡面共用的 2 pt 拋光金屬外框（§6.7），SR 加全息邊。
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/practice_reveal_palette.dart';
import 'practice_reveal_timing.dart';

/// 拋光外框寬（§6.7）；卡面照片的內圓角 22＝外圓角 24 − 2。
const double kPracticeCardRimWidth = 2;

/// 卡片這一刻的光（§6.4）。
@immutable
class PracticeCardLight {
  const PracticeCardLight({
    required this.band,
    required this.relief,
    required this.holoPhase,
  });

  /// 落定（停住）時的光：卡面正對，受光點停在左上（示意圖二的受光位置）。
  static const PracticeCardLight settled =
      PracticeCardLight(band: 0.35, relief: 0, holoPhase: 0.15);

  /// 高光帶中心（沿 115° 對角軸，0＝左上角、1＝右下角）。
  final double band;

  /// 浮雕補光（−1..1，卡背用）。
  final double relief;

  /// SR 全息色帶的相位（週期數）。
  final double holoPhase;

  /// 外框受光點的角度（度；0＝右、90＝下，225＝左上）。
  double get glintDeg => 225 + 180 * (band - 0.35);

  @override
  bool operator ==(Object other) =>
      other is PracticeCardLight &&
      other.band == band &&
      other.relief == relief &&
      other.holoPhase == holoPhase;

  @override
  int get hashCode => Object.hash(band, relief, holoPhase);
}

/// 依卡片姿態（度）算光。卡背以等待姿態（yaw −10°、pitch 4°）為基準，卡面以落定姿態
/// （yaw 180°＝正面 0°、pitch 0°）為基準，取差值。
PracticeCardLight practiceCardLight({
  required double yawDeg,
  required double pitchDeg,
  required bool front,
}) {
  const toRad = math.pi / 180;
  final dYaw =
      (front ? yawDeg - 180 : yawDeg - PracticeRevealTiming.waitingYaw) * toRad;
  final dPitch =
      (pitchDeg - (front ? 0 : PracticeRevealTiming.waitingPitch)) * toRad;
  return PracticeCardLight(
    band: 0.35 - 2.2 * dYaw - 0.8 * dPitch,
    relief: (-3 * dYaw).clamp(-1.0, 1.0),
    holoPhase: 0.15 + 1.4 * dYaw + 0.6 * dPitch,
  );
}

/// SR 全息色序（§6.5，示意圖取樣）：玫瑰 → 洋紅 → 紫 → 天空藍 → 香檳，再接回玫瑰。
const List<Color> kPracticeHoloColors = [
  PracticeRevealPalette.holoRose,
  PracticeRevealPalette.holoMagenta,
  PracticeRevealPalette.holoPlum,
  PracticeRevealPalette.holoSky,
  PracticeRevealPalette.srHoloChampagne,
];

/// 全息色帶在相位 [t]（週期數）的顏色：五色循環，相鄰兩色之間線性插值。
Color practiceHoloColorAt(double t) {
  final n = kPracticeHoloColors.length;
  final x = (t - t.floorToDouble()) * n;
  final i = x.floor() % n;
  return Color.lerp(
    kPracticeHoloColors[i],
    kPracticeHoloColors[(i + 1) % n],
    x - x.floorToDouble(),
  )!;
}

/// 拋光金屬外框（§6.7）：貼著卡緣往內 [kPracticeCardRimWidth]。截面外 0.35 pt 暗、中段 1.3 pt
/// 亮、內 0.35 pt 暗，像一根細金屬管；中段在受光角最亮、對角次亮（示意圖二的右下角）、兩者之間
/// 最暗，受光角再疊一段 40° 的白色受光點。SR 另加全息邊：右側直邊最強（示意圖二），其他地方 0.2。[innerLine] 在框的內緣畫一道細暗線，拉開金屬框與
/// 照片。全部用漸層描邊，不做模糊。
class PracticeCardRimPainter extends CustomPainter {
  const PracticeCardRimPainter({
    required this.dark,
    required this.mid,
    required this.hi,
    required this.light,
    this.holo = false,
    this.innerLine = true,
    this.radius = 24,
  });

  final Color dark;
  final Color mid;
  final Color hi;
  final PracticeCardLight light;
  final bool holo;
  final bool innerLine;
  final double radius;

  /// 全息邊的漸層取樣點數（一圈）。
  static const int _holoStops = 24;

  /// 全息色帶繞一圈的循環數：右側直邊（約 ±56°）剛好看得到整組玫瑰到天空藍。
  static const double _kHoloCycles = 4;

  /// 中段亮帶佔框寬的比例：外、內各剩 0.35 pt 暗邊。
  static const double _kCoreFraction = 0.65;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    const width = kPracticeCardRimWidth;
    final outer = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final band = outer.deflate(width / 2);
    final glint = light.glintDeg * math.pi / 180;
    final low = Color.lerp(dark, mid, 0.6)!;
    final second = Color.lerp(mid, hi, 0.55)!;

    canvas.drawRRect(
      band,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = dark,
    );
    canvas.drawRRect(
      band,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width * _kCoreFraction
        ..shader = SweepGradient(
          colors: [hi, mid, low, second, low, mid, hi],
          stops: const [0, 0.22, 0.38, 0.5, 0.62, 0.78, 1],
          transform: GradientRotation(glint),
        ).createShader(rect),
    );
    canvas.drawRRect(
      band,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width * _kCoreFraction
        ..shader = SweepGradient(
          colors: [
            Colors.white.withValues(alpha: 0.85),
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.85),
          ],
          stops: const [0, 20 / 360, 340 / 360, 1],
          transform: GradientRotation(glint),
        ).createShader(rect),
    );
    if (holo) {
      final colors = <Color>[];
      final stops = <double>[];
      for (var i = 0; i <= _holoStops; i++) {
        final f = i / _holoStops;
        // 0＝右側直邊中央，往下順時針一圈。
        final facing = math.max(0.0, math.cos(f * 2 * math.pi));
        final weight = 0.2 + 0.8 * facing * facing;
        colors.add(
          practiceHoloColorAt(light.holoPhase + _kHoloCycles * f)
              .withValues(alpha: 0.6 * weight),
        );
        stops.add(f);
      }
      canvas.drawRRect(
        band,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..shader =
              SweepGradient(colors: colors, stops: stops).createShader(rect),
      );
    }
    if (innerLine) {
      canvas.drawRRect(
        outer.deflate(width + 0.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.black.withValues(alpha: 0.55),
      );
    }
  }

  @override
  bool shouldRepaint(PracticeCardRimPainter old) =>
      old.dark != dark ||
      old.mid != mid ||
      old.hi != hi ||
      old.light != light ||
      old.holo != holo ||
      old.innerLine != innerLine ||
      old.radius != radius;
}
