// 抽卡揭曉 V3 的特效 painter（規格 docs/plans/2026-10-15-card-draw-v3-luxury-reveal-spec.md
// §6.3、§6.6、§6.7、§6.9）：環境光、星塵、光刃、全息掃光、收卡光球。V3.1 第一刀
// （docs/plans/2026-10-17-card-draw-v3-1-polish-spec.md §5.1、§5.3、§5.5–§5.7、§5.9、§5.12）
// 加上泛光、升階光點、衝擊波、卡片厚度邊、三次貝茲收卡弧線與落位爆光；星塵改成光點貼圖
// 一次畫完（`Canvas.drawRawAtlas`）。
//
// 全部由時間解析計算、零 Random：同一個時間點畫出來一模一樣，widget test 可以直接比對。
// 光暈一律用漸層或預先模糊好的貼圖畫，不用 MaskFilter.blur（規格 §12：逐幀 painter 不做模糊）。
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../core/theme/practice_reveal_palette.dart';
import 'practice_reveal_timing.dart';

/// 光效貼圖（由 `tools/practice-reveal-sprites/make_sprites.py` 離線產出，白色、透明底）。
const String kPracticeRevealBloomAsset =
    'assets/images/practice/practice_reveal_bloom.webp';
const String kPracticeRevealSparkleAsset =
    'assets/images/practice/practice_reveal_sparkle.webp';
const String kPracticeRevealParticleAsset =
    'assets/images/practice/practice_reveal_particle.webp';

/// 解碼好的光效貼圖；還沒載好的是 null，painter 退回用漸層畫。
@immutable
class PracticeRevealSprites {
  const PracticeRevealSprites({this.bloom, this.sparkle, this.particle});

  static const PracticeRevealSprites none = PracticeRevealSprites();

  final ui.Image? bloom;
  final ui.Image? sparkle;
  final ui.Image? particle;
}

/// 光點貼圖的實心核半徑佔半邊長的比例（產生器的 PARTICLE_CORE＋一半的邊緣柔化）。
const double _kParticleSpriteCore = 0.26;

/// 把白色貼圖染成 [color] 畫到 [dst]，疊加混色（貼圖本身已預先模糊，不再做模糊）。
void _paintSprite(Canvas canvas, ui.Image image, Rect dst, Color color) {
  canvas.drawImageRect(
    image,
    Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    dst,
    Paint()
      ..filterQuality = FilterQuality.medium
      ..blendMode = BlendMode.plus
      ..colorFilter = ColorFilter.mode(color, BlendMode.modulate),
  );
}

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
/// 光刃（卡片中心垂直軸）上往兩側噴出（橫向為主，縱向壓到 0.65），初速 160–320 px/s
/// （乘 [speed]：V3.1 SR 1.7 倍，散成滿畫面）、
/// 阻尼 2/s、同時向上漂 18 px/s，很快離開臉的位置；壽命 900–1300 ms（停住前全部燃盡，
/// 停住畫面才是乾淨的靜止）。還沒噴出或已燃盡回 null。
PracticeRevealParticle? practiceRevealBurstParticle(
  int index,
  double tauMs,
  Size card, {
  double speed = 1,
}) {
  if (tauMs < 0) return null;
  final i = index + 1;
  final life = 900 +
      (kPracticeRevealBurstMaxLifeMs - 900) * _frac(i * 0.7548776662 + 0.1);
  if (tauMs >= life) return null;
  final seconds = tauMs / 1000;
  const damping = 2.0;
  final velocity = (160 + 160 * _frac(i * 0.6180339887)) * speed;
  final travel = velocity / damping * (1 - math.exp(-damping * seconds));
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
/// [tauMs]＝卡片側立後經過的毫秒。有光點貼圖時用 `drawRawAtlas` 一次畫完（V3.1 §5.7），
/// 還沒載好就逐顆用漸層畫。
class PracticeRevealBurstPainter extends CustomPainter {
  PracticeRevealBurstPainter({
    required this.center,
    required this.cardSize,
    required this.tauMs,
    required this.count,
    required this.color,
    required this.holo,
    this.speed = 1,
    this.sprite,
    this.opacity = 1,
  });

  final Offset center;
  final Size cardSize;
  final double tauMs;
  final int count;
  final Color color;

  /// SR：5% 的星塵換成粉色。
  final bool holo;

  /// 初速倍率（[practiceRevealBurstParticle] 的 `speed`）。
  final double speed;
  final ui.Image? sprite;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (tauMs < 0 || opacity <= 0.01) return;
    final particles = <(PracticeRevealParticle, Color)>[];
    for (var i = 0; i < count; i++) {
      final p = practiceRevealBurstParticle(i, tauMs, cardSize, speed: speed);
      if (p == null) continue;
      final tone = switch (p.tone) {
        2 when holo => PracticeRevealPalette.holoPink,
        1 => color,
        _ => Colors.white,
      };
      particles.add((p, tone));
    }
    final image = sprite;
    if (image == null) {
      for (final (p, tone) in particles) {
        _paintParticle(canvas, p, center, tone, opacity);
      }
      return;
    }
    practicePaintParticleAtlas(canvas, image, center, particles, opacity);
  }

  @override
  bool shouldRepaint(PracticeRevealBurstPainter old) =>
      old.center != center ||
      old.cardSize != cardSize ||
      old.tauMs != tauMs ||
      old.count != count ||
      old.color != color ||
      old.holo != holo ||
      old.speed != speed ||
      old.sprite != sprite ||
      old.opacity != opacity;
}

/// 用光點貼圖一次畫完一批粒子（`Canvas.drawRawAtlas`，一個 draw call）：貼圖的實心核縮放到
/// 正好等於粒子半徑，外暈自然帶出來；顏色用 modulate 染、疊加混色。位置是 [origin] 加上
/// 粒子的 offset。
void practicePaintParticleAtlas(
  Canvas canvas,
  ui.Image image,
  Offset origin,
  List<(PracticeRevealParticle, Color)> particles,
  double alphaScale,
) {
  final visible = [
    for (final (p, tone) in particles)
      if (p.alpha * alphaScale > 0.01) (p, tone),
  ];
  if (visible.isEmpty) return;
  final half = image.width / 2;
  final core = half * _kParticleSpriteCore;
  final transforms = Float32List(visible.length * 4);
  final rects = Float32List(visible.length * 4);
  final colors = Int32List(visible.length);
  for (var k = 0; k < visible.length; k++) {
    final (p, tone) = visible[k];
    final scale = p.radius / core;
    final c = origin + p.offset;
    transforms
      ..[k * 4] = scale
      ..[k * 4 + 1] = 0
      ..[k * 4 + 2] = c.dx - scale * half
      ..[k * 4 + 3] = c.dy - scale * half;
    rects
      ..[k * 4] = 0
      ..[k * 4 + 1] = 0
      ..[k * 4 + 2] = image.width.toDouble()
      ..[k * 4 + 3] = image.height.toDouble();
    colors[k] = tone
        .withValues(alpha: (p.alpha * alphaScale).clamp(0.0, 1.0))
        .toARGB32();
  }
  canvas.drawRawAtlas(
    image,
    transforms,
    rects,
    colors,
    BlendMode.modulate,
    null,
    Paint()
      ..filterQuality = FilterQuality.medium
      ..blendMode = BlendMode.plus,
  );
}

/// 升階光點顆數（V3.1 §5.3）。
const int kPracticeRevealRiseDotCount = 24;

/// 升階光點第 [index] 顆在揭曉 [ms] 時的狀態，位置相對卡片中心（V3.1 §5.3）：染藍之後沿
/// 卡片四周（外擴 6 px、不只左右邊）出生，往上飄 18–34 px/s、左右輕晃，壽命 600–900 ms、
/// 1.5–3 px；翻牌峰值前 100 ms 全部淡掉。還沒出生或已熄滅回 null。只給 R／SR 用。
PracticeRevealParticle? practiceRevealRiseDot(int index, double ms, Size card) {
  final i = index + 1;
  final birth =
      PracticeRevealTiming.dyeBlueEndMs + 350 * _frac(i * 0.6180339887);
  final life = 600 + 300 * _frac(i * 0.7548776662 + 0.3);
  final age = ms - birth;
  if (age <= 0 || age >= life) return null;
  final fade = 1 -
      practiceRevealSeg(
        ms,
        PracticeRevealTiming.flipPeakMs - 100,
        PracticeRevealTiming.flipPeakMs,
      );
  if (fade <= 0) return null;
  final w = card.width + 12;
  final h = card.height + 12;
  var d = _frac(i * 0.4655712319 + 0.13) * 2 * (w + h);
  final Offset start;
  if (d < w) {
    start = Offset(-w / 2 + d, -h / 2);
  } else if ((d -= w) < h) {
    start = Offset(w / 2, -h / 2 + d);
  } else if ((d -= h) < w) {
    start = Offset(w / 2 - d, h / 2);
  } else {
    d -= w;
    start = Offset(-w / 2, h / 2 - d);
  }
  final seconds = age / 1000;
  final rise = (18 + 16 * _frac(i * 0.8191725134)) * seconds;
  final sway = 3 * math.sin(2 * math.pi * seconds + i);
  return PracticeRevealParticle(
    offset: start + Offset(sway, -rise),
    radius: (1.5 + 1.5 * _frac(i * 0.3819660113 + 0.7)) / 2,
    alpha: 0.9 * math.sin(math.pi * age / life) * fade,
    bokeh: false,
    tone: 1,
  );
}

/// 升階光點（R／SR 染藍後繞著卡片往上飄）：顏色跟著卡背染色走（藍段藍、金段金）。
class PracticeRevealRiseDotsPainter extends CustomPainter {
  PracticeRevealRiseDotsPainter({
    required this.center,
    required this.cardSize,
    required this.ms,
    required this.color,
    this.sprite,
  });

  final Offset center;
  final Size cardSize;
  final double ms;
  final Color color;
  final ui.Image? sprite;

  @override
  void paint(Canvas canvas, Size size) {
    final particles = <(PracticeRevealParticle, Color)>[
      for (var i = 0; i < kPracticeRevealRiseDotCount; i++)
        if (practiceRevealRiseDot(i, ms, cardSize) case final p?) (p, color),
    ];
    final image = sprite;
    if (image != null) {
      practicePaintParticleAtlas(canvas, image, center, particles, 1);
      return;
    }
    for (final (p, tone) in particles) {
      _paintParticle(canvas, p, center, tone, 1);
    }
  }

  @override
  bool shouldRepaint(PracticeRevealRiseDotsPainter old) =>
      old.center != center ||
      old.cardSize != cardSize ||
      old.ms != ms ||
      old.color != color ||
      old.sprite != sprite;
}

/// 泛光（V3.1 §5.1）：預先模糊好的柔光貼圖染成 [color]、拉到 [size] 畫在 [center]，疊加
/// 混色。貼圖還沒載好時用同樣大小的徑向漸層代替。
class PracticeRevealBloomPainter extends CustomPainter {
  PracticeRevealBloomPainter({
    required this.center,
    required this.size,
    required this.color,
    required this.alpha,
    this.sprite,
  });

  final Offset center;
  final Size size;
  final Color color;
  final double alpha;
  final ui.Image? sprite;

  @override
  void paint(Canvas canvas, Size canvasSize) {
    if (alpha <= 0.005) return;
    final dst = Rect.fromCenter(
      center: center,
      width: size.width,
      height: size.height,
    );
    final image = sprite;
    if (image != null) {
      _paintSprite(canvas, image, dst, color.withValues(alpha: alpha));
      return;
    }
    canvas.drawOval(
      dst,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: alpha),
            color.withValues(alpha: 0),
          ],
        ).createShader(dst),
    );
  }

  @override
  bool shouldRepaint(PracticeRevealBloomPainter old) =>
      old.center != center ||
      old.size != size ||
      old.color != color ||
      old.alpha != alpha ||
      old.sprite != sprite;
}

/// 衝擊波光環（V3.1 §5.6）：中間亮、兩側漸隱的圓環，用徑向漸層畫（不做模糊），中線再描一條
/// 細的白色核心；疊加混色。
class PracticeRevealShockwavePainter extends CustomPainter {
  PracticeRevealShockwavePainter({required this.rings, required this.tint});

  final List<({Offset center, PracticeRevealRing ring})> rings;
  final Color tint;

  @override
  void paint(Canvas canvas, Size size) {
    for (final (:center, :ring) in rings) {
      if (ring.alpha <= 0.01 || ring.radius <= 0) continue;
      final outer = ring.radius + ring.width;
      final inner = math.max(0.0, ring.radius - ring.width);
      final rect = Rect.fromCircle(center: center, radius: outer);
      canvas.drawCircle(
        center,
        outer,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = RadialGradient(
            colors: [
              tint.withValues(alpha: 0),
              tint.withValues(alpha: ring.alpha),
              tint.withValues(alpha: 0),
            ],
            stops: [inner / outer, ring.radius / outer, 1],
          ).createShader(rect),
      );
      canvas.drawCircle(
        center,
        ring.radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1, ring.width * 0.25)
          ..blendMode = BlendMode.plus
          ..color = Colors.white.withValues(alpha: 0.6 * ring.alpha),
      );
    }
  }

  @override
  bool shouldRepaint(PracticeRevealShockwavePainter old) =>
      old.tint != tint ||
      old.rings.length != rings.length ||
      !Iterable<int>.generate(rings.length).every(
        (i) =>
            old.rings[i].center == rings[i].center &&
            old.rings[i].ring == rings[i].ring,
      );
}

/// 卡片厚度邊（V3.1 §5.9）：卡片轉到 |yaw| 在 60°–120°（以 180° 為一圈）時，左右兩側各畫
/// 一條 5 px 的深色金屬面。[transform] 是卡片中心座標 → overlay 座標的完整矩陣（含透視）；
/// 這一層畫在卡片後面，轉到背面那一側的厚度會被卡片本身蓋住，不用另外判斷正反面。
class PracticeRevealThicknessPainter extends CustomPainter {
  PracticeRevealThicknessPainter({
    required this.transform,
    required this.cardSize,
    required this.strength,
  });

  final Matrix4 transform;
  final Size cardSize;

  /// 0..1：側立附近最明顯。
  final double strength;

  static const double depth = 5;

  Offset _project(double x, double y, double z) {
    final m = transform.storage;
    final w = m[3] * x + m[7] * y + m[11] * z + m[15];
    return Offset(
      (m[0] * x + m[4] * y + m[8] * z + m[12]) / w,
      (m[1] * x + m[5] * y + m[9] * z + m[13]) / w,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (strength <= 0.01) return;
    final hw = cardSize.width / 2;
    final hh = cardSize.height / 2 - kPracticeRevealEdgeInset;
    for (final side in const [-1.0, 1.0]) {
      final x = side * hw;
      final a = _project(x, -hh, 0);
      final b = _project(x, hh, 0);
      final c = _project(x, hh, depth);
      final d = _project(x, -hh, depth);
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..lineTo(b.dx, b.dy)
        ..lineTo(c.dx, c.dy)
        ..lineTo(d.dx, d.dy)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..shader = ui.Gradient.linear(
            (a + b) / 2,
            (c + d) / 2,
            [
              PracticeRevealPalette.cardEdgeLight.withValues(alpha: strength),
              PracticeRevealPalette.cardEdgeDeep.withValues(alpha: strength),
            ],
          ),
      );
    }
  }

  @override
  bool shouldRepaint(PracticeRevealThicknessPainter old) =>
      old.transform != transform ||
      old.cardSize != cardSize ||
      old.strength != strength;
}

/// 厚度邊上下各內縮多少（跟卡片圓角錯開，不會從圓角外面凸出去）。
const double kPracticeRevealEdgeInset = 16;

/// 卡片厚度邊的強度（0..1）：yaw（以 180° 為一圈）在 60°–120° 之間，70°–110° 全亮。
double practiceRevealThicknessStrength(double yawDeg) {
  final y = yawDeg % 180;
  if (y <= 60 || y >= 120) return 0;
  if (y < 70) return (y - 60) / 10;
  if (y > 110) return (120 - y) / 10;
  return 1;
}

/// L4 光刃：卡片側立那一刻，沿卡片中心垂直軸的一道光；SR 再加一道橫跨整個螢幕的
/// 十字光（V3.1 §5.5：1.2×螢幕寬、兩端各 15% 漸隱、核心 4 px、外暈 40 px）。畫在螢幕座標、
/// 不進 3D transform，保持銳利。外暈與漸隱都用漸層。
class PracticeRevealBladePainter extends CustomPainter {
  PracticeRevealBladePainter({
    required this.center,
    required this.cardSize,
    required this.halo,
    required this.core,
    required this.coreAlpha,
    required this.cross,
    required this.tint,
    this.haloMax = 0.5,
  });

  final Offset center;
  final Size cardSize;

  /// 外暈寬度（0..1，乘上 [haloMax]×卡寬）。
  final double halo;

  /// 外暈最寬是幾倍卡寬（V3.1：N 0.6、R 0.7、SR 0.8）。
  final double haloMax;

  /// 白色核心粗細（px）。
  final double core;
  final double coreAlpha;

  /// SR 橫向十字（0..1）。
  final double cross;
  final Color tint;

  @override
  void paint(Canvas canvas, Size size) {
    final height = cardSize.height * 1.2;
    final haloWidth = cardSize.width * haloMax * halo;
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
      final width = size.width * 1.2;
      const haloHeight = 40.0;
      const coreHeight = 4.0;
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
      old.haloMax != haloMax ||
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

/// L6 收卡光球（V3.1 §5.12）：卡片收成細線再化成光球，沿三次貝茲弧線繞半圈飛進圖鑑那一格。
/// 光尾＝路徑上 t−0.5 到 t 之間 32 個點連成的漸細帶狀（光球端 16 px 漸細到 0），沿途灑 14 顆
/// 星點；落位時那一格上一個大四芒星爆光＋圓形泛光＋兩圈光環。沒有目標格時不飛到別的卡上
/// 誤導，在原地縮到 0。全由 [ms] 解析計算、零 Random。
class PracticeRevealOrbPainter extends CustomPainter {
  PracticeRevealOrbPainter({
    required this.ms,
    required this.origin,
    required this.control1,
    required this.control2,
    required this.target,
    required this.color,
    this.sparkle,
  });

  final double ms;
  final Offset origin;
  final Offset control1;
  final Offset control2;

  /// 目標格（overlay 本地座標）；null＝原地收束。
  final Rect? target;
  final Color color;

  /// 四芒星光貼圖；還沒載好就只畫泛光與光環。
  final ui.Image? sparkle;

  Offset _at(Offset end, double t) =>
      practiceCubicBezier(origin, control1, control2, end, t);

  Offset _normal(Offset end, double t) {
    final tangent =
        practiceCubicBezierTangent(origin, control1, control2, end, t);
    final len = tangent.distance;
    return len < 1e-3
        ? Offset.zero
        : Offset(-tangent.dy / len, tangent.dx / len);
  }

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

    // 沿途星點：光球經過各自的 t 時灑出，向外漂 20 px、300 ms 淡掉。
    for (var i = 1; i <= PracticeRevealTiming.sparkleCount; i++) {
      final age = ms - kPracticeArchiveSparkleSpawnMs[i - 1];
      if (age <= 0 || age >= PracticeRevealTiming.sparkleLifeMs) continue;
      final ti = practiceArchiveSparkleT(i);
      final life = age / PracticeRevealTiming.sparkleLifeMs;
      final pos = _at(end, ti) +
          _normal(end, ti) *
              ((i.isEven ? 1.0 : -1.0) * 20 * Curves.easeOut.transform(life));
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
      _paintTail(canvas, end, t, 1 - vanish);
      _paintOrb(canvas, _at(end, t), core * (1 - vanish), 1 - vanish);
    }

    _paintLanding(canvas, goal);
  }

  /// 光尾：由光球往回 32 個點，寬度與不透明度都漸減到 0，連成三角帶一次畫完。
  void _paintTail(Canvas canvas, Offset end, double t, double strength) {
    if (strength <= 0 || t <= 0) return;
    const n = PracticeRevealTiming.tailPoints;
    final positions = <Offset>[];
    final colors = <Color>[];
    for (var k = 0; k < n; k++) {
      final f = k / (n - 1); // 0＝光球端、1＝尾端
      final tk = t - PracticeRevealTiming.tailSpan * f;
      if (tk < 0) break;
      final p = _at(end, tk);
      final half = practiceArchiveTailWidth(f) / 2 * strength;
      final nrm = _normal(end, tk) * half;
      final c = color.withValues(alpha: 0.95 * (1 - f) * strength);
      positions
        ..add(p + nrm)
        ..add(p - nrm);
      colors
        ..add(c)
        ..add(c);
    }
    if (positions.length < 4) return;
    canvas.drawVertices(
      ui.Vertices(ui.VertexMode.triangleStrip, positions, colors: colors),
      BlendMode.dst,
      Paint()..blendMode = BlendMode.plus,
    );
  }

  /// 落位：大四芒星爆光（1.2×格寬、250 ms）＋圓形泛光＋兩圈光環。那一格本來的發光由
  /// 圖鑑頁負責，這裡不動。
  void _paintLanding(Canvas canvas, Rect goal) {
    final end = goal.center;
    final burst = practiceArchiveLandBurst(ms);
    if (burst != null) {
      final glowRadius = goal.longestSide * 0.7 * burst.scale;
      canvas.drawCircle(
        end,
        glowRadius,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: 0.55 * burst.alpha),
              color.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: end, radius: glowRadius)),
      );
      final image = sparkle;
      if (image != null) {
        final side = goal.width * 1.2 * burst.scale;
        _paintSprite(
          canvas,
          image,
          Rect.fromCenter(center: end, width: side, height: side),
          Color.lerp(Colors.white, color, 0.35)!.withValues(alpha: burst.alpha),
        );
      }
    }
    final maxRadius = Offset(goal.width, goal.height).distance * 0.6;
    for (final which in const [0, 1]) {
      final ring = practiceArchiveLandRing(ms, which);
      if (ring == null) continue;
      canvas.drawCircle(
        end,
        maxRadius * (which == 0 ? 1.0 : 0.8) * Curves.easeOut.transform(ring),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = which == 0 ? 2 : 1.5
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
      old.control1 != control1 ||
      old.control2 != control2 ||
      old.target != target ||
      old.color != color ||
      old.sparkle != sparkle;
}
