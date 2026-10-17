// 抽卡揭曉 V3 的特效 painter（規格 docs/plans/2026-10-15-card-draw-v3-luxury-reveal-spec.md
// §6.3、§6.6、§6.7、§6.9）：環境光、星塵、光刃、全息掃光、收卡光球。
//
// 全部由時間解析計算、零 Random：同一個時間點畫出來一模一樣，widget test 可以直接比對。
// 光暈一律用漸層畫，不用 MaskFilter.blur（規格 §12：逐幀 painter 不做模糊）。
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../core/theme/practice_reveal_palette.dart';
import 'practice_reveal_timing.dart';

const double _kGoldenAngle = 2.399963229728653;

double _frac(double x) => x - x.floorToDouble();

/// 環境星塵顆數。
const int kPracticeRevealAmbientDustCount = 14;

/// 爆發星塵最長壽命：卡片側立後這麼久全部燃盡（停住前就乾淨）。
const double kPracticeRevealBurstMaxLifeMs = 1300;

/// 一顆星塵在某個時間點的樣子。
@immutable
class PracticeRevealParticle {
  const PracticeRevealParticle({
    required this.offset,
    required this.radius,
    required this.alpha,
    required this.bokeh,
    required this.tone,
  });

  final Offset offset;
  final double radius;
  final double alpha;

  /// 失焦大光斑：用徑向漸層畫、不透明度壓在 0.25 以下。
  final bool bokeh;

  /// 0＝白、1＝主題星色、2＝粉（只有 SR 會用到）。
  final int tone;

  @override
  bool operator ==(Object other) =>
      other is PracticeRevealParticle &&
      other.offset == offset &&
      other.radius == radius &&
      other.alpha == alpha &&
      other.bokeh == bokeh &&
      other.tone == tone;

  @override
  int get hashCode => Object.hash(offset, radius, alpha, bokeh, tone);
}

/// 翻牌爆發星塵第 [index] 顆，在卡片側立後 [tauMs] 毫秒的狀態。位置相對卡片中心：從
/// 光刃（卡片中心垂直軸）上往兩側噴出（橫向為主，縱向壓到 0.65），初速 160–320 px/s、
/// 阻尼 2/s、同時向上漂 18 px/s，很快離開臉的位置；壽命 900–1300 ms（停住前全部燃盡，
/// 停住畫面才是乾淨的靜止）。還沒噴出或已燃盡回 null。
PracticeRevealParticle? practiceRevealBurstParticle(
  int index,
  double tauMs,
  Size card,
) {
  if (tauMs < 0) return null;
  final i = index + 1;
  final life = 900 +
      (kPracticeRevealBurstMaxLifeMs - 900) * _frac(i * 0.7548776662 + 0.1);
  if (tauMs >= life) return null;
  final seconds = tauMs / 1000;
  const damping = 2.0;
  final speed = 160 + 160 * _frac(i * 0.6180339887);
  final travel = speed / damping * (1 - math.exp(-damping * seconds));
  final angle = i * _kGoldenAngle;
  final start =
      Offset(0, (_frac(i * 0.5698402910 + 0.3) - 0.5) * card.height * 0.8);
  final offset = start +
      Offset(math.cos(angle), 0.65 * math.sin(angle)) * travel +
      Offset(0, -18 * seconds);

  // 尺寸分布：65% 細點、28% 中點、7% 失焦大光斑。
  final sizeRoll = _frac(i * 0.4655712319 + 0.7);
  final sizeT = _frac(i * 0.8191725134 + 0.2);
  final bokeh = sizeRoll >= 0.93;
  final diameter = sizeRoll < 0.65
      ? 1.5 + 1.0 * sizeT
      : bokeh
          ? 9 + 5 * sizeT
          : 3 + 2 * sizeT;
  final fadeIn = (tauMs / 60).clamp(0.0, 1.0);
  final fadeOut = math.pow(1 - tauMs / life, 1.6).toDouble();
  final base = bokeh ? 0.22 : 0.55 + 0.4 * _frac(i * 0.3819660113 + 0.5);
  final toneRoll = _frac(i * 0.9127 + 0.4);
  return PracticeRevealParticle(
    offset: offset,
    radius: diameter / 2,
    alpha: base * fadeIn * fadeOut,
    bokeh: bokeh,
    tone: toneRoll < 0.05
        ? 2
        : toneRoll < 0.55
            ? 1
            : 0,
  );
}

/// 環境星塵第 [index] 顆在 [phase]（以等待呼吸的一圈 2.6 s 為 1）時的狀態，位置是整個
/// overlay 的座標。每顆在自己的一圈裡向上漂 8–14 px/s、淡入淡出，接圈那一刻正好透明，
/// 所以循環無縫。
PracticeRevealParticle practiceRevealAmbientParticle(
  int index,
  double phase,
  Size area,
) {
  final i = index + 1;
  final u = _frac(phase + i * 0.6180339887);
  final speed = 8 + 6 * _frac(i * 0.7548776662);
  final drift = speed * 2.6;
  final x = (0.06 + 0.88 * _frac(i * 0.5698402910 + 0.17)) * area.width;
  final y =
      (0.10 + 0.82 * _frac(i * 0.4655712319 + 0.61)) * area.height - drift * u;
  final diameter = 1 + 2 * _frac(i * 0.3819660113 + 0.29);
  final alpha =
      (0.15 + 0.30 * _frac(i * 0.8191725134 + 0.43)) * math.sin(math.pi * u);
  return PracticeRevealParticle(
    offset: Offset(x, y),
    radius: diameter / 2,
    alpha: alpha,
    bokeh: false,
    tone: i.isEven ? 1 : 0,
  );
}

void _paintParticle(
  Canvas canvas,
  PracticeRevealParticle p,
  Offset origin,
  Color color,
  double alphaScale,
) {
  final alpha = (p.alpha * alphaScale).clamp(0.0, 1.0);
  if (alpha <= 0.01) return;
  final center = origin + p.offset;
  if (p.bokeh) {
    canvas.drawCircle(
      center,
      p.radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: alpha),
            color.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: p.radius)),
    );
    return;
  }
  final halo = p.radius * 3;
  canvas.drawCircle(
    center,
    halo,
    Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: alpha * 0.45),
          color.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: halo)),
  );
  canvas.drawCircle(
      center, p.radius, Paint()..color = color.withValues(alpha: alpha));
}

/// L1 環境光：卡片背後的稀有度色徑向光（跟著卡背染色走：銀 → 藍 → 金）。
class PracticeRevealGlowPainter extends CustomPainter {
  PracticeRevealGlowPainter({
    required this.center,
    required this.radius,
    required this.color,
    required this.alpha,
  });

  final Offset center;
  final double radius;
  final Color color;
  final double alpha;

  @override
  void paint(Canvas canvas, Size size) {
    if (alpha <= 0.005 || radius <= 0) return;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: alpha),
            color.withValues(alpha: alpha * 0.35),
            color.withValues(alpha: 0),
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  @override
  bool shouldRepaint(PracticeRevealGlowPainter old) =>
      old.center != center ||
      old.radius != radius ||
      old.color != color ||
      old.alpha != alpha;
}

/// L2 環境星塵（卡片後方，整個 overlay 慢慢往上漂）。停住期間 [phase] 不動＝凍結。
class PracticeRevealAmbientDustPainter extends CustomPainter {
  PracticeRevealAmbientDustPainter({
    required this.phase,
    required this.color,
    required this.opacity,
  });

  final double phase;
  final Color color;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0.01) return;
    for (var i = 0; i < kPracticeRevealAmbientDustCount; i++) {
      final p = practiceRevealAmbientParticle(i, phase, size);
      _paintParticle(
        canvas,
        p,
        Offset.zero,
        p.tone == 1 ? color : Colors.white,
        opacity,
      );
    }
  }

  @override
  bool shouldRepaint(PracticeRevealAmbientDustPainter old) =>
      old.phase != phase || old.color != color || old.opacity != opacity;
}

/// 翻牌爆發星塵：卡片側立那一刻從光刃噴出，畫在卡片前面（細碎的光點朝鏡頭飛散）。
/// [tauMs]＝卡片側立後經過的毫秒。
class PracticeRevealBurstPainter extends CustomPainter {
  PracticeRevealBurstPainter({
    required this.center,
    required this.cardSize,
    required this.tauMs,
    required this.count,
    required this.color,
    required this.holo,
    this.opacity = 1,
  });

  final Offset center;
  final Size cardSize;
  final double tauMs;
  final int count;
  final Color color;

  /// SR：5% 的星塵換成粉色。
  final bool holo;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (tauMs < 0 || opacity <= 0.01) return;
    for (var i = 0; i < count; i++) {
      final p = practiceRevealBurstParticle(i, tauMs, cardSize);
      if (p == null) continue;
      final tone = switch (p.tone) {
        2 when holo => PracticeRevealPalette.holoPink,
        1 => color,
        _ => Colors.white,
      };
      _paintParticle(canvas, p, center, tone, opacity);
    }
  }

  @override
  bool shouldRepaint(PracticeRevealBurstPainter old) =>
      old.center != center ||
      old.cardSize != cardSize ||
      old.tauMs != tauMs ||
      old.count != count ||
      old.color != color ||
      old.holo != holo ||
      old.opacity != opacity;
}

/// L4 光刃：卡片側立那一刻，沿卡片中心垂直軸的一道光；SR 再加一道橫向十字。
/// 畫在螢幕座標、不進 3D transform，保持銳利。外暈與上下漸隱都用漸層。
class PracticeRevealBladePainter extends CustomPainter {
  PracticeRevealBladePainter({
    required this.center,
    required this.cardSize,
    required this.halo,
    required this.core,
    required this.coreAlpha,
    required this.cross,
    required this.tint,
  });

  final Offset center;
  final Size cardSize;

  /// 外暈寬度（0..1，乘上卡寬的一半）。
  final double halo;

  /// 白色核心粗細（px）。
  final double core;
  final double coreAlpha;

  /// SR 橫向十字（0..1）。
  final double cross;
  final Color tint;

  @override
  void paint(Canvas canvas, Size size) {
    final height = cardSize.height * 1.2;
    final haloWidth = cardSize.width * 0.5 * halo;
    if (haloWidth > 0.5 || (core > 0 && coreAlpha > 0)) {
      final bounds = Rect.fromCenter(
        center: center,
        width: math.max(haloWidth, core) + 2,
        height: height,
      );
      canvas.saveLayer(bounds, Paint());
      if (haloWidth > 0.5) {
        final haloRect =
            Rect.fromCenter(center: center, width: haloWidth, height: height);
        canvas.drawRect(
          haloRect,
          Paint()..shader = _bandShader(haloRect, horizontal: true),
        );
      }
      if (core > 0 && coreAlpha > 0) {
        canvas.drawRect(
          Rect.fromCenter(center: center, width: core, height: height),
          Paint()..color = Colors.white.withValues(alpha: coreAlpha),
        );
      }
      // 上下各 15% 漸隱。
      canvas.drawRect(
        bounds,
        Paint()
          ..blendMode = BlendMode.dstIn
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.black,
              Colors.black,
              Colors.transparent,
            ],
            stops: [0.0, 0.15, 0.85, 1.0],
          ).createShader(bounds),
      );
      canvas.restore();
    }

    if (cross > 0.01) {
      final width = cardSize.width * 0.9;
      const haloHeight = 24.0;
      const coreHeight = 3.0;
      final bounds =
          Rect.fromCenter(center: center, width: width, height: haloHeight);
      canvas.saveLayer(
        bounds,
        Paint()..color = Colors.white.withValues(alpha: cross),
      );
      canvas.drawRect(
        bounds,
        Paint()..shader = _bandShader(bounds, horizontal: false),
      );
      canvas.drawRect(
        Rect.fromCenter(center: center, width: width, height: coreHeight),
        Paint()..color = Colors.white,
      );
      // 左右各 15% 漸隱。
      canvas.drawRect(
        bounds,
        Paint()
          ..blendMode = BlendMode.dstIn
          ..shader = const LinearGradient(
            colors: [
              Colors.transparent,
              Colors.black,
              Colors.black,
              Colors.transparent,
            ],
            stops: [0.0, 0.15, 0.85, 1.0],
          ).createShader(bounds),
      );
      canvas.restore();
    }
  }

  // 外暈的截面：透明 → 主題色 @0.55 → 白 @0.95 → 主題色 @0.55 → 透明。
  Shader _bandShader(Rect rect, {required bool horizontal}) => LinearGradient(
        begin: horizontal ? Alignment.centerLeft : Alignment.topCenter,
        end: horizontal ? Alignment.centerRight : Alignment.bottomCenter,
        colors: [
          tint.withValues(alpha: 0),
          tint.withValues(alpha: 0.55),
          Colors.white.withValues(alpha: 0.95),
          tint.withValues(alpha: 0.55),
          tint.withValues(alpha: 0),
        ],
        stops: const [0.0, 0.3, 0.5, 0.7, 1.0],
      ).createShader(rect);

  @override
  bool shouldRepaint(PracticeRevealBladePainter old) =>
      old.center != center ||
      old.cardSize != cardSize ||
      old.halo != halo ||
      old.core != core ||
      old.coreAlpha != coreAlpha ||
      old.cross != cross ||
      old.tint != tint;
}

/// 卡面全息掃光：115° 斜向光帶（文字提案原值：透明 20% → 白 @0.40 45% → 暖金 @0.30
/// 50% → 透明 80%），從卡片左外側掃到右外側；SR 另加兩道 ±6% 偏移的細彩邊。
class PracticeRevealSheenPainter extends CustomPainter {
  PracticeRevealSheenPainter({
    required this.x,
    required this.strength,
    required this.holo,
  });

  /// 光帶位置（以卡寬為單位，−1.2 → +1.2）。
  final double x;
  final double strength;
  final bool holo;

  static const double _angle = 115 * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    if (strength <= 0) return;
    final dir = Offset(math.sin(_angle), -math.cos(_angle));
    final span = (size.width * dir.dx).abs() + (size.height * dir.dy).abs();
    final center = size.center(Offset.zero) + Offset(x * size.width, 0);
    final from = center - dir * (span / 2);
    final to = center + dir * (span / 2);
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = BlendMode.softLight
        ..shader = ui.Gradient.linear(
          from,
          to,
          [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.40 * strength),
            PracticeRevealPalette.sheenGold.withValues(alpha: 0.30 * strength),
            PracticeRevealPalette.sheenGold.withValues(alpha: 0),
          ],
          const [0.20, 0.45, 0.50, 0.80],
        ),
    );
    // 柔光在暗部幾乎看不見：同一條光帶再疊一層很淡的 screen，讓暗處也有一道亮痕。
    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = BlendMode.screen
        ..shader = ui.Gradient.linear(
          from,
          to,
          [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.16 * strength),
            Colors.white.withValues(alpha: 0),
          ],
          const [0.36, 0.47, 0.58],
        ),
    );
    if (!holo) return;
    for (final (color, offset) in [
      (PracticeRevealPalette.holoCyan, -0.06),
      (PracticeRevealPalette.holoPink, 0.06),
    ]) {
      final c = 0.475 + offset;
      canvas.drawRect(
        rect,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = ui.Gradient.linear(
            from,
            to,
            [
              color.withValues(alpha: 0),
              color.withValues(alpha: 0.18 * strength),
              color.withValues(alpha: 0),
            ],
            [c - 0.018, c, c + 0.018],
          ),
      );
    }
  }

  @override
  bool shouldRepaint(PracticeRevealSheenPainter old) =>
      old.x != x || old.strength != strength || old.holo != holo;
}

/// L6 收卡光球：卡片縮成光球，沿二次貝茲弧線飛進圖鑑那一格。拖尾＝沿路徑回推的 10 個
/// 殘影，沿途灑 8 顆星點；落位時擴一圈光環。沒有目標格時不飛到別的卡上誤導，在原地
/// 縮到 0。全由 [ms] 解析計算、零 Random。
class PracticeRevealOrbPainter extends CustomPainter {
  PracticeRevealOrbPainter({
    required this.ms,
    required this.origin,
    required this.control,
    required this.target,
    required this.color,
  });

  final double ms;
  final Offset origin;
  final Offset control;

  /// 目標格（overlay 本地座標）；null＝原地收束。
  final Rect? target;
  final Color color;

  static const int _trailCount = 10;
  static const double _trailStep = 0.035;

  @override
  void paint(Canvas canvas, Size size) {
    final core = practiceArchiveOrbRadius(ms);
    final goal = target;
    if (goal == null) {
      if (core <= 0) return;
      final shrink = practiceRevealSeg(
        ms,
        PracticeRevealTiming.flightStartMs,
        PracticeRevealTiming.implodeEndMs,
      );
      // 原地收束：柔閃一下再縮到 0。
      final flash = math.sin(math.pi * shrink);
      _paintOrb(canvas, origin, 18 * (1 - shrink) + 6 * flash, 1 - shrink);
      return;
    }

    final end = goal.center;
    final t = practiceArchiveFlightT(ms);
    final vanish = practiceRevealSeg(
      ms,
      PracticeRevealTiming.landMs,
      PracticeRevealTiming.landMs + PracticeRevealTiming.orbVanishMs,
    );
    final endFade = 1 -
        practiceRevealSeg(
          ms,
          PracticeRevealTiming.landMs,
          PracticeRevealTiming.archiveMs,
        );

    // 沿途星點：光球經過 t＝0.1·i 時灑出，向外漂 20 px、300 ms 淡掉。
    for (var i = 1; i <= PracticeRevealTiming.sparkleCount; i++) {
      final age = ms - kPracticeArchiveSparkleSpawnMs[i - 1];
      if (age <= 0 || age >= PracticeRevealTiming.sparkleLifeMs) continue;
      final ti = 0.1 * i;
      final tangent = practiceQuadBezierTangent(origin, control, end, ti);
      final len = tangent.distance;
      final normal = len < 1e-3
          ? Offset.zero
          : Offset(-tangent.dy / len, tangent.dx / len) *
              (i.isEven ? 1.0 : -1.0);
      final life = age / PracticeRevealTiming.sparkleLifeMs;
      final pos = practiceQuadBezier(origin, control, end, ti) +
          normal * (20 * Curves.easeOut.transform(life));
      final alpha = (1 - life) * endFade;
      canvas.drawCircle(
        pos,
        4,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: 0.5 * alpha),
              color.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: pos, radius: 4)),
      );
      canvas.drawCircle(
        pos,
        1.2,
        Paint()..color = Colors.white.withValues(alpha: 0.9 * alpha),
      );
    }

    if (core > 0) {
      for (var k = _trailCount; k >= 1; k--) {
        final tk = t - k * _trailStep;
        if (tk <= 0) continue;
        final fade = math.pow(1 - k / _trailCount, 2).toDouble() * (1 - vanish);
        canvas.drawCircle(
          practiceQuadBezier(origin, control, end, tk),
          (18 - 8 * tk) * (1 - k / 12),
          Paint()..color = color.withValues(alpha: 0.5 * fade),
        );
      }
      _paintOrb(
        canvas,
        practiceQuadBezier(origin, control, end, t),
        core * (1 - vanish),
        1 - vanish,
      );
    }

    final ring = practiceRevealSeg(
      ms,
      PracticeRevealTiming.landMs,
      PracticeRevealTiming.archiveMs,
    );
    if (ring > 0) {
      final maxRadius = Offset(goal.width, goal.height).distance * 0.6;
      canvas.drawCircle(
        end,
        maxRadius * Curves.easeOut.transform(ring),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color.withValues(alpha: 0.9 * (1 - ring)),
      );
    }
  }

  void _paintOrb(Canvas canvas, Offset center, double radius, double alpha) {
    if (radius <= 0.1 || alpha <= 0) return;
    // 外暈約 48 px（核心 18 時）。
    final glowRadius = radius * 2.67;
    canvas.drawCircle(
      center,
      glowRadius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: 0.55 * alpha),
            color.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: glowRadius)),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: alpha),
            color.withValues(alpha: 0.9 * alpha),
          ],
          stops: const [0.35, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  @override
  bool shouldRepaint(PracticeRevealOrbPainter old) =>
      old.ms != ms ||
      old.origin != origin ||
      old.control != control ||
      old.target != target ||
      old.color != color;
}
