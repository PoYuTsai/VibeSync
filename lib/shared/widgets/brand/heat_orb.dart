// lib/shared/widgets/brand/heat_orb.dart
//
// 投入度光球：對象頁 Hero 右側那顆會呼吸的光。
//
// 設計概念「同一盞光，越靠越近」——
// App 背景本來就是三顆漂浮的柔光球（gradient_background.dart：blur 60、
// opacity 0.08–0.18、緩慢漂移）。這顆球不是新物件，它是同一族的光，只是靠得
// 夠近，近到感覺得到溫度。投入度升高時它不變成別的東西，而是更近、更暖、更
// 快、更活。
//
// 六條「融入」紀律（違反任一條就會看起來像貼上去的貼紙）：
//  1. 永遠不能有硬邊——alpha 必須在碰到邊界前衰減到 0，不描邊、不畫圓框。
//  2. 是光不是物件——同一層內用 [BlendMode.plus] 相加，讓底下的紫透上來。
//  3. 紫底永遠要透出來——連第 5 段外圈都保留紫暈，純橘會變貼紙。
//  4. 柔度跟背景同一族——衰減曲線比照 blur 60 的 bokeh。
//  5. 不轉、不彈、不跳——只允許呼吸、漂移、內部翻湧。
//  6. 換段要溶接——[_bandCrossfade] 600ms，硬切會像畫面壞掉。
//
// 硬規則：
//  - 純 Flutter 繪製。NO image asset、NO Lottie、NO DALL-E。
//  - 分段與顏色是純呈現層映射，不合成分數、不呼叫 AI。
//  - 動畫吃 TickerMode 與 reduce motion 守門（同 LiquidMotionFrame）；關掉時
//    停在該段的靜態靜止幀，不是空白。
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';

/// 換段時的交叉溶接時長。分數只在新分析完成時才變，硬切會被讀成畫面壞掉。
const Duration _bandCrossfade = Duration(milliseconds: 600);

/// 關動畫時停在這個相位。0.18 讓呼吸停在略為擴張處——完全的 0 看起來像
/// 「還沒開始」，略為擴張才像「靜止但活著」。與 LiquidMotionFrame 同一手法。
const double _restingPhase = 0.18;

/// 火星上升一輪相對於呼吸一圈的倍率。比呼吸慢，火星才不會像在抖。
const double _emberCycleRatio = 1.7;

/// 火星池大小。等於 [kHeatOrbBands] 裡最大的 embers 值。
const int _emberPoolSize = 8;

/// 三顆銜接色。冷段與暖段兩端都直接取自 [AppColors]，只有中間過渡需要調和
/// 色——它們的存在就是為了讓紫不會一步跳到橘（紀律 3）。
const Color _violetLift = Color(0xFFB9A9FF); // primaryLight 提亮，第 2 段核心
const Color _violetMagenta = Color(0xFFB274E2); // 紫→粉的橋，第 4 段外暈
const Color _emberViolet = Color(0xFFB06EEB); // 第 5 段外圈保留的紫暈

/// 一段投入度對應的完整光球配方。
///
/// 欄位全部可線性內插（[lerp]），換段才能溶接而不是硬切。[cores] 與 [embers]
/// 刻意用 double：換段時顆數要能長出 2.4 顆——第 3 顆以 0.4 的透明度淡入，
/// 而不是「啪」一聲整顆出現。
@immutable
class HeatOrbBand {
  /// 這一段的分數下界（含）。
  final int min;

  /// 這一段的分數上界（含）。
  final int max;

  /// 設計代號，給測試與除錯用；不上畫面。
  final String name;

  /// 最外圈的暈。決定「這顆球是什麼溫度」的第一眼。
  final Color halo;
  final double haloAlpha;

  /// 中層暈。冷暖交界在這一層先發生。
  final Color mid;
  final double midAlpha;

  /// 內核。真正的熱源。
  final Color core;
  final double coreAlpha;

  /// 內核顆數。越多顆＝內部越翻湧。
  final double cores;

  /// 內核互繞半徑（相對於整顆球邊長）。0＝完全不動。
  final double churn;

  /// 呼吸幅度（縮放振幅）。
  final double amplitude;

  /// 呼吸一圈的秒數。**速度是這套設計真正的訊號載體**——顏色說溫度，
  /// 速度說「有多活」。12 秒近乎靜止，2.8 秒已是明顯躁動。
  final double cycleSeconds;

  /// 上升火星顆數。只有第 4、5 段有。
  final double embers;

  /// 內核是否帶向上竄動（火焰行為，不是火焰形狀）。
  final double flame;

  const HeatOrbBand({
    required this.min,
    required this.max,
    required this.name,
    required this.halo,
    required this.haloAlpha,
    required this.mid,
    required this.midAlpha,
    required this.core,
    required this.coreAlpha,
    required this.cores,
    required this.churn,
    required this.amplitude,
    required this.cycleSeconds,
    required this.embers,
    required this.flame,
  });

  static HeatOrbBand lerp(HeatOrbBand a, HeatOrbBand b, double t) {
    if (identical(a, b) || t <= 0) return a;
    if (t >= 1) return b;
    return HeatOrbBand(
      min: b.min,
      max: b.max,
      name: b.name,
      halo: Color.lerp(a.halo, b.halo, t)!,
      haloAlpha: ui.lerpDouble(a.haloAlpha, b.haloAlpha, t)!,
      mid: Color.lerp(a.mid, b.mid, t)!,
      midAlpha: ui.lerpDouble(a.midAlpha, b.midAlpha, t)!,
      core: Color.lerp(a.core, b.core, t)!,
      coreAlpha: ui.lerpDouble(a.coreAlpha, b.coreAlpha, t)!,
      cores: ui.lerpDouble(a.cores, b.cores, t)!,
      churn: ui.lerpDouble(a.churn, b.churn, t)!,
      amplitude: ui.lerpDouble(a.amplitude, b.amplitude, t)!,
      cycleSeconds: ui.lerpDouble(a.cycleSeconds, b.cycleSeconds, t)!,
      embers: ui.lerpDouble(a.embers, b.embers, t)!,
      flame: ui.lerpDouble(a.flame, b.flame, t)!,
    );
  }
}

/// 五段升溫。分段界線與可見滿分是拍板規格，改動前先看 heat_orb_test.dart。
///
/// 色帶刻意等於把 App 的色彩語言從「解讀」走到「行動」：
/// cold/frozen → primaryLight（解讀紫）→ brandBlush（AI 推薦粉）→
/// brandFlame（行動橘），剛好對應投入度從冷到燃。
///
/// 速度是等比壓縮的（12 → 9 → 6.8 → 4.5 → 2.8），升溫感才連續、不跳階。
/// 6.8 秒那段特別選過：那是 LiquidBeamEntryPreset 既有的品牌流速。
const List<HeatOrbBand> kHeatOrbBands = [
  // 遠光 — 霧裡的一盞遠光。在，但還沒靠近你。
  HeatOrbBand(
    min: 0,
    max: 35,
    name: 'distant',
    halo: AppColors.cold,
    haloAlpha: 0.30,
    mid: AppColors.frozen,
    midAlpha: 0.13,
    core: AppColors.frozen,
    coreAlpha: 0.17,
    cores: 1,
    churn: 0.000,
    amplitude: 0.045,
    cycleSeconds: 12.0,
    embers: 0,
    flame: 0,
  ),
  // 靠近 — 它注意到你了。開始有穩定的呼吸。
  HeatOrbBand(
    min: 36,
    max: 50,
    name: 'approaching',
    halo: AppColors.primaryLight,
    haloAlpha: 0.34,
    mid: AppColors.cold,
    midAlpha: 0.17,
    core: _violetLift,
    coreAlpha: 0.26,
    cores: 2,
    churn: 0.018,
    amplitude: 0.075,
    cycleSeconds: 9.0,
    embers: 0,
    flame: 0,
  ),
  // 回應 — 冷外暈裡浮出一顆暖核。裡面有事在發生。
  HeatOrbBand(
    min: 51,
    max: 65,
    name: 'responding',
    halo: AppColors.primaryLight,
    haloAlpha: 0.40,
    mid: AppColors.veryHot,
    midAlpha: 0.20,
    core: AppColors.brandBlush,
    coreAlpha: 0.30,
    cores: 2,
    churn: 0.030,
    amplitude: 0.100,
    cycleSeconds: 6.8,
    embers: 0,
    flame: 0,
  ),
  // 有溫度 — 顏色跨過了冷暖線。這時候是感覺得到熱的。
  HeatOrbBand(
    min: 66,
    max: 80,
    name: 'warm',
    halo: _violetMagenta,
    haloAlpha: 0.42,
    mid: AppColors.brandBlush,
    midAlpha: 0.28,
    core: AppColors.brandFlame,
    coreAlpha: 0.34,
    cores: 3,
    churn: 0.042,
    amplitude: 0.130,
    cycleSeconds: 4.5,
    embers: 4,
    flame: 0,
  ),
  // 燃燒 — 像火焰，但是柔光的火，不是卡通的火。
  HeatOrbBand(
    min: 81,
    max: AppConstants.investmentVisibleMax,
    name: 'burning',
    halo: _emberViolet, // 紀律 3：燒到這裡外圈仍留紫暈
    haloAlpha: 0.30,
    mid: AppColors.coachRecommendation,
    midAlpha: 0.34,
    core: AppColors.brandFlame,
    coreAlpha: 0.46,
    cores: 3,
    churn: 0.055,
    amplitude: 0.160,
    cycleSeconds: 2.8,
    embers: 8,
    flame: 1,
  ),
];

/// 分數 → 段。null（尚未分析）落在最冷那段：沒有訊號就是遠光。
HeatOrbBand heatOrbBandFor(int? heat) {
  if (heat == null) return kHeatOrbBands.first;
  final s = heat.clamp(0, AppConstants.investmentVisibleMax);
  for (final band in kHeatOrbBands) {
    if (s <= band.max) return band;
  }
  return kHeatOrbBands.last;
}

/// 光球的時鐘與狀態。
///
/// 拆成獨立的 [ChangeNotifier] 是為了讓 [CustomPaint] 只重繪這 80pt，不必
/// setState 重建整張卡片子樹——這顆球每格都在動，用 setState 會把 Hero 卡
/// 的文字一起拖著重建。
class _OrbClock extends ChangeNotifier {
  _OrbClock(HeatOrbBand initial)
      : _from = initial,
        _to = initial;

  double phase = _restingPhase;
  HeatOrbBand _from;
  HeatOrbBand _to;
  double _blend = 1;

  /// 每顆火星各自的相位。獨立累加是必要的：共用一個相位再乘上各自速度的話，
  /// 相位歸零那一刻所有火星會一起跳位置。各自累加則各自在 alpha 歸零處回捲，
  /// 看不出來。
  final List<double> emberPhase =
      List<double>.generate(_emberPoolSize, (i) => _hash(i * 7 + 3));

  /// 每顆火星的上升速度倍率，決定性產生。
  static final List<double> emberSpeed =
      List<double>.generate(_emberPoolSize, (i) => 0.65 + _hash(i + 61) * 0.7);

  /// 每顆火星的水平位置偏移，決定性產生。
  static final List<double> emberOffset =
      List<double>.generate(_emberPoolSize, (i) => _hash(i + 113) - 0.5);

  static double _hash(int i) {
    final x = math.sin(i * 127.1) * 43758.5453;
    return x - x.floorToDouble();
  }

  HeatOrbBand get band => HeatOrbBand.lerp(_from, _to, _blend);

  /// 目標段換人。從「目前看到的樣子」接下去，而不是從舊段的起點——連續兩次
  /// 換段才不會倒退一格再重跑。
  void retarget(HeatOrbBand next, {required bool animated}) {
    if (identical(next, _to)) return;
    if (animated) {
      _from = HeatOrbBand.lerp(_from, _to, _blend);
      _to = next;
      _blend = 0;
    } else {
      _from = next;
      _to = next;
      _blend = 1;
    }
    notifyListeners();
  }

  /// 停在靜止幀：溶接落底、相位回到 [_restingPhase]。
  void rest() {
    _from = _to;
    _blend = 1;
    phase = _restingPhase;
    notifyListeners();
  }

  void advance(double dt) {
    if (dt <= 0) return;

    if (_blend < 1) {
      final crossfade =
          _bandCrossfade.inMicroseconds / Duration.microsecondsPerSecond;
      _blend = math.min(1.0, _blend + dt / crossfade);
      if (_blend >= 1) _from = _to;
    }

    final cycle = band.cycleSeconds;
    phase = (phase + dt / cycle) % 1.0;

    final emberStep = dt / (cycle * _emberCycleRatio);
    for (var i = 0; i < emberPhase.length; i++) {
      emberPhase[i] = (emberPhase[i] + emberStep * emberSpeed[i]) % 1.0;
    }
    notifyListeners();
  }
}

/// 對象頁 Hero 右側的投入度光球。
///
/// [heat] 是已經 clamp 過的可見分數（0–90）或 null。這個 widget 只做呈現層
/// 映射，不做任何計算或校準。
class HeatOrb extends StatefulWidget {
  const HeatOrb({
    super.key,
    required this.heat,
    this.size = 80,
  });

  final int? heat;
  final double size;

  @override
  State<HeatOrb> createState() => _HeatOrbState();
}

class _HeatOrbState extends State<HeatOrb> with SingleTickerProviderStateMixin {
  late final _OrbClock _clock = _OrbClock(heatOrbBandFor(widget.heat));
  late final Ticker _ticker = createTicker(_onTick);

  Duration _lastTick = Duration.zero;
  bool? _motionEnabled;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant HeatOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.heat == widget.heat) return;
    _clock.retarget(
      heatOrbBandFor(widget.heat),
      animated: _motionEnabled ?? false,
    );
  }

  /// 守門手法比照 LiquidMotionFrame：reduce motion 或 subtree 被靜音就停在
  /// 靜止幀。少了 TickerMode 那一半，躺在非當前路由底下的卡也會照跑。
  void _syncMotion() {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final enabled = TickerMode.valuesOf(context).enabled && !reduceMotion;
    if (_motionEnabled == enabled) return;
    _motionEnabled = enabled;

    if (enabled) {
      _lastTick = Duration.zero;
      if (!_ticker.isActive) _ticker.start();
    } else {
      if (_ticker.isActive) _ticker.stop();
      _clock.rest();
    }
  }

  void _onTick(Duration elapsed) {
    if (_lastTick == Duration.zero) {
      _lastTick = elapsed;
      return;
    }
    final dt =
        (elapsed - _lastTick).inMicroseconds / Duration.microsecondsPerSecond;
    _lastTick = elapsed;
    _clock.advance(dt);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: CustomPaint(
          size: Size.square(widget.size),
          painter: _HeatOrbPainter(_clock),
        ),
      ),
    );
  }
}

class _HeatOrbPainter extends CustomPainter {
  _HeatOrbPainter(this.clock) : super(repaint: clock);

  final _OrbClock clock;

  /// 一團無邊界的光。
  ///
  /// 四個 stop 的衰減曲線是紀律 1 與 4 的實作：最後一站必為 alpha 0，且中段
  /// 壓得比線性更低，看起來才像 blur 60 的 bokeh 而不是實心圓。
  void _blob(Canvas canvas, Offset c, double r, Color color, double alpha) {
    if (r <= 0 || alpha <= 0) return;
    final a = alpha.clamp(0.0, 1.0);
    final shader = ui.Gradient.radial(
      c,
      r,
      [
        color.withValues(alpha: a),
        color.withValues(alpha: a * 0.52),
        color.withValues(alpha: a * 0.16),
        color.withValues(alpha: 0),
      ],
      const [0.0, 0.35, 0.68, 1.0],
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = shader
        // 紀律 2：光是相加的。放在 saveLayer 內，所以只在光球自己各層之間
        // 相加，對外仍是正常的 src-over——不會把卡片背景一起燒白。
        ..blendMode = BlendMode.plus,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final b = clock.band;
    final s = size.shortestSide;
    if (s <= 0) return;

    final c = Offset(size.width / 2, size.height / 2);
    final p = clock.phase;
    final breath = math.sin(p * 2 * math.pi);
    final counter = math.sin(p * 2 * math.pi + math.pi * 0.55);

    canvas.saveLayer(Offset.zero & size, Paint());

    // 外暈
    _blob(canvas, c, s * 0.46 * (1 + b.amplitude * 0.55 * breath), b.halo,
        b.haloAlpha);

    // 中暈：反相呼吸，兩層才不會像同一顆球單純放大縮小
    _blob(
      canvas,
      c.translate(0, s * 0.012 * counter),
      s * 0.30 * (1 + b.amplitude * 0.85 * counter),
      b.mid,
      b.midAlpha,
    );

    // 內核：互繞 + 各自錯開的呼吸相位＝內部翻湧。
    // 顆數是小數：最後一顆用小數部分當淡入係數，換段時不會啪一聲多一顆。
    final coreCount = b.cores.ceil();
    final coreWhole = b.cores.floor();
    for (var i = 0; i < coreCount; i++) {
      final fade = i < coreWhole ? 1.0 : b.cores - coreWhole;
      if (fade <= 0) break;
      final ang = p * 2 * math.pi + i * (2 * math.pi / coreCount);
      var oy = math.sin(ang * 1.37) * s * b.churn;
      if (b.flame > 0) {
        // 火焰是一種行為不是形狀：內核被持續往上帶，不畫火舌輪廓。
        oy -= s * 0.035 * b.flame * (0.6 + 0.4 * math.sin(ang * 2.1));
      }
      final wob = 1 + b.amplitude * 0.9 * math.sin(p * 2 * math.pi + i * 1.9);
      _blob(
        canvas,
        c.translate(math.cos(ang) * s * b.churn, oy),
        s * 0.165 * wob,
        b.core,
        b.coreAlpha / (1 + i * 0.45) * fade,
      );
    }

    // 上升火星。同樣用小數顆數淡入，第 3 段升到第 4 段時火星是「浮現」的。
    final emberCount = math.min(b.embers.ceil(), clock.emberPhase.length);
    final emberWhole = b.embers.floor();
    for (var e = 0; e < emberCount; e++) {
      final fade = e < emberWhole ? 1.0 : b.embers - emberWhole;
      if (fade <= 0) break;
      final t = clock.emberPhase[e];
      final ex = c.dx +
          _OrbClock.emberOffset[e] * s * 0.30 +
          math.sin(t * 2 * math.pi + e) * s * 0.028;
      final ey = c.dy + s * 0.17 - t * s * 0.46;
      // sin(t·π) 在 t=0 與 t=1 都是 0，所以相位回捲那一刻火星正好不可見。
      _blob(canvas, Offset(ex, ey), s * 0.036, b.core,
          math.sin(t * math.pi) * 0.42 * b.coreAlpha * 2.2 * fade);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HeatOrbPainter oldDelegate) =>
      !identical(oldDelegate.clock, clock);
}
