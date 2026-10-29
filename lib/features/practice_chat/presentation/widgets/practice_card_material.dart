// 抽卡卡片典藏材質的共用件（規格 docs/plans/2026-10-28-card-collectible-material-spec.md）：
// - [practiceCardLight]：從卡片姿態算出這一刻的光（§6.4）。卡片怎麼轉，高光、受光點、
//   全息色帶就怎麼走；姿態不動（停住），光就不動，不增加動畫幀。
// - [PracticeCardRimPainter]：卡背、卡面共用的 2 pt 拋光金屬外框（§6.7），SR 加全息邊。
// - 卡背（§5.4、§6）：[PracticeCardMaterialSlot] 七張離線渲染好的素材、[PracticeCardMaterialLoader]
//   解碼與釋放、[PracticeCardBackPainter] 在一個 painter 裡疊 B0–B9 各層（每層混色不同）。
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_motion.dart';
import '../../../../core/theme/practice_reveal_palette.dart';
import '../../domain/entities/practice_girl_rarity.dart';
import 'practice_reveal_theme.dart';
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

  /// 落定（停住）時的光：卡面正對，受光點停在左上（示意圖二的受光位置）。卡背的等待基準姿態
  /// （yaw −10°、pitch 4°）算出來也是這組。
  static const PracticeCardLight settled =
      PracticeCardLight(band: 0.35, relief: 0, holoPhase: 0.15);

  /// 高光帶中心（沿 115° 對角軸，0＝左上角、1＝右下角）。
  final double band;

  /// 浮雕補光（−1..1，卡背用）。
  final double relief;

  /// SR 全息色帶的相位（週期數）。
  final double holoPhase;

  /// 外框受光點的角度（度；0＝右、90＝下，225＝左上）。band 在卡外（翻牌側立時）只算到離
  /// 左上半圈的右下角為止：受光點從右下滑進來、停在左上，不會繞著外框轉圈。
  double get glintDeg => 225 + 180 * (band - 0.35).clamp(-1.0, 1.0);

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
    this.holoStrength = 1,
    this.innerLine = true,
    this.radius = 24,
  });

  final Color dark;
  final Color mid;
  final Color hi;
  final PracticeCardLight light;
  final bool holo;

  /// 全息邊的強度（0..1）：卡背跟著染金從 0 升到 1；卡面固定 1。
  final double holoStrength;
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
    if (holo && holoStrength > 0) {
      final colors = <Color>[];
      final stops = <double>[];
      for (var i = 0; i <= _holoStops; i++) {
        final f = i / _holoStops;
        // 0＝右側直邊中央，往下順時針一圈。
        final facing = math.max(0.0, math.cos(f * 2 * math.pi));
        final weight = 0.2 + 0.8 * facing * facing;
        colors.add(
          practiceHoloColorAt(light.holoPhase + _kHoloCycles * f)
              .withValues(alpha: 0.6 * weight * holoStrength),
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
      old.holoStrength != holoStrength ||
      old.innerLine != innerLine ||
      old.radius != radius;
}

// ── 卡背（§5.4、§6）──────────────────────────────────────────────────────────

/// 卡背的七張素材（§5.4，`tools/practice-card-material/render_card_back.py` 離線渲染）。
/// 遮罩一律不透明、用 RGB 打包：解碼後是預乘 alpha，放在 alpha 的話 RGB 會被清掉。
enum PracticeCardMaterialSlot {
  /// N 成品圖（B0）。
  n('practice_card_back_v4_n.webp'),

  /// R 成品圖（B1，轉化擴散）。
  r('practice_card_back_v4_r.webp'),

  /// SR 成品圖（B2，轉化擴散）。
  sr('practice_card_back_v4_sr.webp'),

  /// R＝浮雕補光差（0.5＝不變）、G＝全息遮罩、B＝高光遮罩。
  light('practice_card_back_v4_light.webp'),

  /// 半解析度：R＝徽記與節點、G＝外框、B＝線路（額外發光、徽記白光）。
  glowMask('practice_card_back_v4_glowmask.webp'),

  /// 半解析度：預先模糊好的白色泛光。
  glow('practice_card_back_v4_glow.webp'),

  /// 128×128 雜訊磚（顆粒），原尺寸解。
  noise('practice_card_noise.webp');

  const PracticeCardMaterialSlot(this._file);

  final String _file;

  String get asset => 'assets/images/practice/$_file';

  /// 儀式掛上就解的一組：N 卡背一定用得到（§6.1）。
  static const Set<PracticeCardMaterialSlot> base = {
    n,
    light,
    glowMask,
    glow,
    noise,
  };

  /// 按下翻牌才解、收卡就釋放的一組：最早到 R0＋600 ms 才用到。
  static const Set<PracticeCardMaterialSlot> tiers = {r, sr};

  /// 成品圖與遮罩的原始寬（px）。
  static const int sourceWidth = 1200;

  /// 解碼用的 provider：成品圖與 `light` 解成卡片實際像素寬（[cardPixelWidth]＝卡寬 pt×裝置
  /// 像素比，上限原圖 1200），半解析度的遮罩與泛光解一半，雜訊磚原尺寸。錄製工具預先解碼時
  /// 用同一個 provider，儀式就直接拿到快取。
  ImageProvider provider(int cardPixelWidth) {
    final image = AssetImage(asset);
    final width = cardPixelWidth.clamp(1, sourceWidth);
    return switch (this) {
      noise => image,
      glowMask || glow => ResizeImage(image, width: (width / 2).ceil()),
      _ => ResizeImage(image, width: width),
    };
  }
}

/// 解碼好的卡背素材。每次有圖解好或被釋放都換一個新的實例，painter 用 identity 判斷要不要重畫。
@immutable
class PracticeCardMaterialImages {
  PracticeCardMaterialImages(Map<PracticeCardMaterialSlot, ui.Image> images)
      : _images = Map.unmodifiable(images);

  const PracticeCardMaterialImages._empty() : _images = const {};

  /// 一張都還沒解好（§6.8 的退路）。
  static const PracticeCardMaterialImages none =
      PracticeCardMaterialImages._empty();

  final Map<PracticeCardMaterialSlot, ui.Image> _images;

  ui.Image? operator [](PracticeCardMaterialSlot slot) => _images[slot];

  /// 換掉（[image] 為 null＝拿掉）[slot] 那一張。
  PracticeCardMaterialImages withImage(
    PracticeCardMaterialSlot slot,
    ui.Image? image,
  ) {
    final next = Map.of(_images);
    if (image == null) {
      next.remove(slot);
    } else {
      next[slot] = image;
    }
    return PracticeCardMaterialImages(next);
  }
}

/// 卡背素材的解碼與釋放（§6.1）：沿用儀式光效貼圖的模式（`ImageProvider.resolve` →
/// `ImageStreamListener`），每張圖各留一份 [ImageInfo]；釋放時連同圖片快取裡的那一份一起清掉。
class PracticeCardMaterialLoader {
  /// [debugProviderFor]：測試用，換掉 [PracticeCardMaterialSlot.provider]（例如給一張解不出來的圖）。
  PracticeCardMaterialLoader({
    required this.onChanged,
    ImageProvider Function(PracticeCardMaterialSlot slot, int cardPixelWidth)?
        debugProviderFor,
  }) : _providerFor = debugProviderFor ?? _slotProvider;

  /// 有圖解好或被釋放時呼叫（呼叫端 setState）；[dispose] 時不呼叫。
  final ValueChanged<PracticeCardMaterialImages> onChanged;

  final ImageProvider Function(
      PracticeCardMaterialSlot slot, int cardPixelWidth) _providerFor;

  static ImageProvider _slotProvider(
    PracticeCardMaterialSlot slot,
    int cardPixelWidth,
  ) =>
      slot.provider(cardPixelWidth);

  PracticeCardMaterialImages get images => _images;
  PracticeCardMaterialImages _images = PracticeCardMaterialImages.none;

  final Map<PracticeCardMaterialSlot, _CardMaterialRequest> _requests = {};
  bool _disposed = false;

  /// 卡片像素寬比解碼時大超過這個倍數才換寬度重解（[upgrade]）：放大 10% 以內看不出糊，網頁拖拉
  /// 視窗時也不會一直重解。
  static const double upgradeRatio = 1.1;

  /// 開始解碼 [slots]；正在解或已經解好的跳過。[cardPixelWidth] 見
  /// [PracticeCardMaterialSlot.provider]。
  void load(
    Iterable<PracticeCardMaterialSlot> slots, {
    required ImageConfiguration configuration,
    required int cardPixelWidth,
  }) {
    if (_disposed) return;
    for (final slot in slots) {
      if (_requests.containsKey(slot)) continue;
      _start(slot, configuration, cardPixelWidth);
    }
  }

  /// 卡片變大（轉向、iPad 分割畫面、網頁視窗放大）：已經在解或解好的素材，[cardPixelWidth] 比解碼
  /// 時大超過 [upgradeRatio] 就換新寬度重解。新圖解好前繼續畫舊圖、解好才釋放舊的，解不出來就留著
  /// 舊圖；變小不重解，雜訊磚原尺寸解、跟卡寬無關。還沒開始解的不在這裡開始（首屏照舊等第一幀之後）。
  void upgrade({
    required ImageConfiguration configuration,
    required int cardPixelWidth,
  }) {
    if (_disposed) return;
    final width = _decodeWidth(cardPixelWidth);
    for (final slot in _requests.keys.toList()) {
      if (slot == PracticeCardMaterialSlot.noise) continue;
      final current = _requests[slot]!;
      if (width <= current.cardPixelWidth * upgradeRatio) continue;
      // 畫面上正在用的那張留到新圖解好；還在解、還沒畫出來的那張（初次或上一次重解）不等了。
      final shown = current.info != null ? current : current.takePrevious();
      if (!identical(shown, current)) current.release();
      _start(slot, configuration, width, previous: shown);
    }
  }

  /// 解碼用的卡片像素寬：上限原圖寬（再寬也解不出更多細節，不必重解）。
  static int _decodeWidth(int cardPixelWidth) =>
      cardPixelWidth.clamp(1, PracticeCardMaterialSlot.sourceWidth);

  void _start(
    PracticeCardMaterialSlot slot,
    ImageConfiguration configuration,
    int cardPixelWidth, {
    _CardMaterialRequest? previous,
  }) {
    final request = _CardMaterialRequest(
      _providerFor(slot, cardPixelWidth),
      configuration,
      cardPixelWidth: _decodeWidth(cardPixelWidth),
      previous: previous,
    );
    _requests[slot] = request;
    request.start(
      onImage: (info) {
        if (_disposed || _requests[slot] != request) {
          info.dispose();
          return;
        }
        request.info = info;
        _images = _images.withImage(slot, info.image);
        request.takePrevious()?.release();
        onChanged(_images);
      },
      onError: () {
        if (_requests[slot] != request) return;
        // 重解失敗：換回畫面上的舊圖（有的話），之後卡片再變大還會再試。
        final shown = request.takePrevious();
        if (shown != null) {
          _requests[slot] = shown;
        } else {
          _requests.remove(slot);
        }
      },
    );
  }

  /// 釋放 [slots]：還在解的不等了，解好的放掉自己那份並從圖片快取清掉。
  void evict(Iterable<PracticeCardMaterialSlot> slots) {
    var changed = false;
    for (final slot in slots) {
      final request = _requests.remove(slot);
      if (request == null) continue;
      request.release();
      if (_images[slot] != null) {
        _images = _images.withImage(slot, null);
        changed = true;
      }
    }
    if (changed && !_disposed) onChanged(_images);
  }

  /// 儀式卸載：全部釋放。
  void dispose() {
    _disposed = true;
    evict(PracticeCardMaterialSlot.values);
  }
}

class _CardMaterialRequest {
  _CardMaterialRequest(
    this.provider,
    this.configuration, {
    required this.cardPixelWidth,
    _CardMaterialRequest? previous,
  }) : _previous = previous;

  final ImageProvider provider;
  final ImageConfiguration configuration;

  /// 解碼時的卡片像素寬（已經夾在原圖寬以內）；[PracticeCardMaterialLoader.upgrade] 拿它比。
  final int cardPixelWidth;

  /// 換寬度重解時畫面上還在用的舊圖：這張解好才釋放，解不出來就換回它。
  _CardMaterialRequest? _previous;

  ImageStream? _stream;
  ImageStreamListener? _listener;
  ImageInfo? info;

  void start({
    required ValueChanged<ImageInfo> onImage,
    required VoidCallback onError,
  }) {
    final stream = provider.resolve(configuration);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (image, _) {
        stream.removeListener(listener);
        _listener = null;
        onImage(image);
      },
      onError: (_, __) {
        stream.removeListener(listener);
        _listener = null;
        onError();
      },
    );
    _stream = stream;
    _listener = listener;
    stream.addListener(listener);
  }

  /// 拿走 [_previous]（之後由呼叫端釋放或換回）。
  _CardMaterialRequest? takePrevious() {
    final previous = _previous;
    _previous = null;
    return previous;
  }

  /// 不等了、放掉解好的那份並從圖片快取清掉；還留著的舊圖一起放。
  void release() {
    takePrevious()?.release();
    final listener = _listener;
    if (listener != null) _stream?.removeListener(listener);
    _listener = null;
    info?.dispose();
    info = null;
    unawaited(provider.evict(configuration: configuration));
  }
}

/// 測試與錄製工具用：一次把七張素材解好（要在 `tester.runAsync` 裡等）。解不到的那張留空。
@visibleForTesting
Future<PracticeCardMaterialImages> debugLoadCardMaterial(
  ImageConfiguration configuration, {
  required int cardPixelWidth,
}) async {
  final images = <PracticeCardMaterialSlot, ui.Image>{};
  for (final slot in PracticeCardMaterialSlot.values) {
    final done = Completer<void>();
    final stream = slot.provider(cardPixelWidth).resolve(configuration);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        images[slot] = info.image;
        stream.removeListener(listener);
        if (!done.isCompleted) done.complete();
      },
      onError: (_, __) {
        stream.removeListener(listener);
        if (!done.isCompleted) done.complete();
      },
    );
    stream.addListener(listener);
    await done.future;
  }
  return PracticeCardMaterialImages(images);
}

/// 卡背靜止值以外的額外發光（§6.6）。成品圖已經畫進靜止時的光（徽記光暈、R／SR 的線路光），
/// 這裡只算多出來的能量，靜止時全是 0。
@immutable
class PracticeCardBackEnergy {
  const PracticeCardBackEnergy({
    this.emblem = 0,
    this.frame = 0,
    this.lines = 0,
    this.bloom = 0,
  });

  static const PracticeCardBackEnergy none = PracticeCardBackEnergy();

  /// 等待呼吸與心跳：徽記亮度（0.30–0.45＋心跳 0.12）超過 0.30 的部分，畫在徽記與泛光。
  factory PracticeCardBackEnergy.waiting(double emblemGlow) {
    final extra = math.max(0.0, emblemGlow - 0.30);
    return PracticeCardBackEnergy(emblem: extra, bloom: extra);
  }

  /// 徽記與節點（`glowMask.R`）。
  final double emblem;

  /// 外框（`glowMask.G`）。
  final double frame;

  /// 線路（`glowMask.B`）。
  final double lines;

  /// 徽記泛光貼圖（`glow`）。
  final double bloom;

  bool get isZero => emblem <= 0 && frame <= 0 && lines <= 0 && bloom <= 0;

  /// 從 [a] 往 [b] 混 [t]（揭曉起手從等待姿態接過來，不跳格）。
  static PracticeCardBackEnergy lerp(
    PracticeCardBackEnergy a,
    PracticeCardBackEnergy b,
    double t,
  ) =>
      PracticeCardBackEnergy(
        emblem: a.emblem + (b.emblem - a.emblem) * t,
        frame: a.frame + (b.frame - a.frame) * t,
        lines: a.lines + (b.lines - a.lines) * t,
        bloom: a.bloom + (b.bloom - a.bloom) * t,
      );

  @override
  bool operator ==(Object other) =>
      other is PracticeCardBackEnergy &&
      other.emblem == emblem &&
      other.frame == frame &&
      other.lines == lines &&
      other.bloom == bloom;

  @override
  int get hashCode => Object.hash(emblem, frame, lines, bloom);
}

/// 染色脈衝退回 0 的時間（§6.6）。
const double _kDyePulseFadeMs = 280;

/// 染藍、染金脈衝（0..1，§6.6）：染色進行時升到 1，結束後 280 ms 退回 0（`AppMotion.easeOut`）。
/// SR 的染藍脈衝撐到染金結束才退：兩段合成一次升降，不多一次閃光。N 恆 0。
double practiceCardBackDyePulse(double ms, PracticeGirlRarity rarity) {
  if (rarity == PracticeGirlRarity.n) return 0;
  final end = rarity == PracticeGirlRarity.sr
      ? PracticeRevealTiming.dyeGoldEndMs
      : PracticeRevealTiming.dyeBlueEndMs;
  if (ms <= end) return practiceRevealDye(ms, rarity).blue;
  return 1 -
      AppMotion.easeOut.transform(
        practiceRevealSeg(ms, end, end + _kDyePulseFadeMs),
      );
}

/// 揭曉時間軸上的額外發光（§6.6）：蓄力（`practiceRevealChargeGlow`×0.5）一路留到翻牌；N 再加
/// 一次銀光脈衝（0.80 → 1.00 → 0.85 超過蓄力的那一段）；R／SR 的染色脈衝讓徽記、外框、線路、
/// 泛光一起亮再退。
PracticeCardBackEnergy practiceCardBackEnergy(
  double ms,
  PracticeGirlRarity rarity,
) {
  var emblem = 0.5 * practiceRevealChargeGlow(ms);
  if (rarity == PracticeGirlRarity.n && ms >= PracticeRevealTiming.dyeBlueMs) {
    emblem += practiceRevealEmblemGlow(ms, rarity) - 0.80;
  }
  final pulse = practiceCardBackDyePulse(ms, rarity);
  return PracticeCardBackEnergy(
    emblem: math.max(emblem, pulse),
    frame: pulse,
    lines: pulse,
    bloom: math.max(emblem, pulse),
  );
}

/// 轉化擴散（§6.3）：下一階的成品圖從徽記（卡片正中）往外長出來。[t]＝`practiceRevealDye` 的
/// 進度（已經過 `enter` 曲線，不再疊）。回傳擴散半徑、遮罩邊緣柔化寬、前緣光環的寬與不透明度。
({double radius, double soft, double ringWidth, double ringAlpha})
    practiceCardDiffusion(double t, Size size) {
  final halfDiag = size.center(Offset.zero).distance;
  final p = t.clamp(0.0, 1.0);
  return (
    radius: p * 1.2 * halfDiag,
    soft: 0.18 * halfDiag,
    ringWidth: 0.06 * halfDiag,
    ringAlpha: 0.65 * math.sin(math.pi * p),
  );
}

/// 把遮罩圖的第 [channel] 個通道（0＝R、1＝G、2＝B）變成 [color] 的透明度×[strength]（附錄
/// §18.2）。`ColorFilter.matrix` 的位移欄是 0–255、輸出夾在 0–1。
ColorFilter practiceChannelAlpha(int channel, Color color, double strength) {
  final a = [0.0, 0.0, 0.0]..[channel] = strength;
  return ColorFilter.matrix(<double>[
    0, 0, 0, 0, color.r * 255, //
    0, 0, 0, 0, color.g * 255, //
    0, 0, 0, 0, color.b * 255, //
    a[0], a[1], a[2], 0, 0,
  ]);
}

/// 浮雕補光（`light.R`，0.5＝不變）的一半變成 [color] 的透明度：[upper]＝R 大於 0.5 的那一半
/// （α＝clamp(2R − 1)×[strength]），否則是小於 0.5 的那一半（α＝clamp(1 − 2R)×[strength]）。
/// 輸出會被夾在 0–1，所以正負兩半各用一個矩陣就能拆開。
ColorFilter practiceReliefHalf({
  required bool upper,
  required Color color,
  required double strength,
}) =>
    ColorFilter.matrix(<double>[
      0, 0, 0, 0, color.r * 255, //
      0, 0, 0, 0, color.g * 255, //
      0, 0, 0, 0, color.b * 255, //
      (upper ? 2 : -2) * strength, 0, 0, 0, (upper ? -255 : 255) * strength,
    ]);

/// 卡背的圖層（§6.2 的 B0–B9，加上素材還沒解好時的退路）。
enum PracticeCardBackLayer {
  /// 素材還沒解碼好：深色底（§6.8）。
  fallback,

  /// B0：N 成品圖。
  base,

  /// B1：R 成品圖從徽記往外擴散。
  blueWipe,

  /// B2：SR 成品圖從徽記往外擴散。
  goldWipe,

  /// B3：擴散前緣光環。
  wipeRing,

  /// B4：浮雕補光（低檔不畫）。
  relief,

  /// B5：跟著姿態走的高光帶。
  specular,

  /// B6：SR 全息（低檔不畫）。
  holo,

  /// B7：額外發光。
  energy,

  /// B8：徽記白光。
  emblemWhite,

  /// B9：顆粒（防色帶）。
  grain,
}

/// 卡背（§6.2）：全部在一個 painter 裡畫（每一層要不同的混色模式，用 widget 疊做不到）。外面由
/// [PracticeRevealCardBack] 圓角裁切、再壓拋光外框。每幀最多 3 個 `saveLayer`（轉化擴散、高光帶、
/// SR 全息）；泛光、光暈全是預先模糊好的貼圖，painter 裡不做模糊。
class PracticeCardBackPainter extends CustomPainter {
  const PracticeCardBackPainter({
    required this.images,
    required this.dye,
    required this.light,
    this.energy = PracticeCardBackEnergy.none,
    this.emblemWhite = 0,
    this.tier = PracticeRevealEffectTier.medium,
    this.grainScale = 1,
  });

  final PracticeCardMaterialImages images;

  /// 染色進度（`practiceRevealDye`，已經只升到真實稀有度）。
  final ({double blue, double gold}) dye;
  final PracticeCardLight light;
  final PracticeCardBackEnergy energy;

  /// 徽記白光（0..1，`practiceRevealEmblemWhite`）。
  final double emblemWhite;
  final PracticeRevealEffectTier tier;

  /// 雜訊磚的縮放（1／裝置像素比＝一個雜訊點對一個實體像素）。
  final double grainScale;

  /// 浮雕補光的最大不透明度（relief＝±1、補光差最大時）。
  static const double _kReliefGain = 0.6;

  /// 高光帶的半寬（沿 115° 對角軸，左上角到右下角＝1）。
  static const double _kBandHalf = 0.11;

  /// SR 全息的不透明度上限：保留成品圖本身的全息與金屬色，執行時這層只讓色帶跟著轉動走。
  static const double _kHoloAlpha = 0.35;

  /// 全息色帶的週期（卡寬的倍數，同離線渲染）。
  static const double _kHoloPeriod = 0.35;

  /// 額外發光各通道的最大不透明度（`screen` 混色）。
  static const double _kEmblemGain = 0.3;
  static const double _kFrameGain = 0.4;
  static const double _kLinesGain = 0.5;
  static const double _kBloomGain = 0.5;

  /// 顆粒的不透明度（`overlay`）。
  static const double _kGrainAlpha = 0.025;

  /// 115° 對角軸的方向（0°＝往上、順時針；同離線渲染的全息方向）。
  static final Offset _axis = Offset(
    math.sin(115 * math.pi / 180),
    -math.cos(115 * math.pi / 180),
  );

  bool get _full => tier != PracticeRevealEffectTier.low;

  /// 這一幀要畫的圖層，依序。只看傳進來的狀態：N 沒有 B1、B2；R 沒有 B2；SR 的 B2 要等染金
  /// （稀有度誠實，§6.3）；R、SR 成品圖還沒解好時維持上一階（§6.8）。成品圖不透明：上一階轉化
  /// 完成後就不再畫底下那幾張。
  List<PracticeCardBackLayer> get layers {
    final n = images[PracticeCardMaterialSlot.n];
    if (n == null) return const [PracticeCardBackLayer.fallback];
    final hasR = images[PracticeCardMaterialSlot.r] != null;
    final hasSr = images[PracticeCardMaterialSlot.sr] != null;
    final hasLight = images[PracticeCardMaterialSlot.light] != null;
    final hasMask = images[PracticeCardMaterialSlot.glowMask] != null;
    final blue = hasR && dye.blue > 0;
    final gold = hasSr && dye.gold > 0;
    final goldDone = gold && dye.gold >= 1;
    final blueDone = blue && dye.blue >= 1;
    final wiping =
        (gold && dye.gold < 1) || (!gold && blue && dye.blue < 1);
    final band = light.band;
    return [
      if (!blueDone && !goldDone) PracticeCardBackLayer.base,
      if (blue && !goldDone) PracticeCardBackLayer.blueWipe,
      if (gold) PracticeCardBackLayer.goldWipe,
      if (wiping) PracticeCardBackLayer.wipeRing,
      if (_full && hasLight && light.relief != 0) PracticeCardBackLayer.relief,
      if (hasLight && band > -_kBandHalf && band < 1 + _kBandHalf)
        PracticeCardBackLayer.specular,
      if (_full && hasLight && gold) PracticeCardBackLayer.holo,
      if (hasMask && !energy.isZero) PracticeCardBackLayer.energy,
      if (hasMask && emblemWhite > 0) PracticeCardBackLayer.emblemWhite,
      if (images[PracticeCardMaterialSlot.noise] != null)
        PracticeCardBackLayer.grain,
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    for (final layer in layers) {
      switch (layer) {
        case PracticeCardBackLayer.fallback:
          canvas.drawRect(
            rect,
            Paint()..color = PracticeRevealPalette.cardBackField,
          );
        case PracticeCardBackLayer.base:
          _image(canvas, images[PracticeCardMaterialSlot.n]!, rect);
        case PracticeCardBackLayer.blueWipe:
          _wipe(canvas, images[PracticeCardMaterialSlot.r]!, rect, dye.blue);
        case PracticeCardBackLayer.goldWipe:
          _wipe(canvas, images[PracticeCardMaterialSlot.sr]!, rect, dye.gold);
        case PracticeCardBackLayer.wipeRing:
          _ring(canvas, rect);
        case PracticeCardBackLayer.relief:
          _relief(canvas, rect);
        case PracticeCardBackLayer.specular:
          _specular(canvas, rect);
        case PracticeCardBackLayer.holo:
          _holo(canvas, rect);
        case PracticeCardBackLayer.energy:
          _energy(canvas, rect);
        case PracticeCardBackLayer.emblemWhite:
          _image(
            canvas,
            images[PracticeCardMaterialSlot.glowMask]!,
            rect,
            Paint()
              ..colorFilter =
                  practiceChannelAlpha(0, Colors.white, emblemWhite),
          );
        case PracticeCardBackLayer.grain:
          _grain(canvas, rect);
      }
    }
  }

  void _image(Canvas canvas, ui.Image image, Rect rect, [Paint? paint]) {
    canvas.drawImageRect(
      image,
      Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
      rect,
      (paint ?? Paint())..filterQuality = FilterQuality.low,
    );
  }

  /// 轉化擴散：下一階的成品圖從徽記往外長出來（`saveLayer`＋徑向遮罩 `dstIn`）；擴散完直接畫，
  /// 不開 layer。
  void _wipe(Canvas canvas, ui.Image next, Rect rect, double t) {
    if (t >= 1) return _image(canvas, next, rect);
    final d = practiceCardDiffusion(t, rect.size);
    final outer = d.radius + d.soft;
    canvas.saveLayer(rect, Paint());
    _image(canvas, next, rect);
    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = ui.Gradient.radial(
          rect.center,
          outer,
          const [Colors.white, Colors.white, Colors.transparent],
          [0, d.radius / outer, 1],
        ),
    );
    canvas.restore();
  }

  /// 前緣光環（`plus`）：在擴散半徑畫一圈徑向漸層光，顏色是這一階的主題光色。
  void _ring(Canvas canvas, Rect rect) {
    final gold = dye.gold > 0;
    final d = practiceCardDiffusion(gold ? dye.gold : dye.blue, rect.size);
    if (d.ringAlpha <= 0 || d.radius <= 0) return;
    final color = (gold ? PracticeRevealTheme.sr : PracticeRevealTheme.r).glow;
    final outer = d.radius + d.ringWidth;
    final inner = math.max(0.0, d.radius - d.ringWidth) / outer;
    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.radial(
          rect.center,
          outer,
          [
            color.withValues(alpha: 0),
            color.withValues(alpha: d.ringAlpha),
            color.withValues(alpha: 0),
          ],
          [inner, d.radius / outer, 1],
        ),
    );
  }

  /// 浮雕補光（§6.4）：`light.R` 是光從左上移到右上時的明暗差。relief＞0 把變亮的那一半疊亮
  /// （`plus` 這一階金屬的亮色，金屬的反光帶自己的顏色，香檳金不會被白光洗淡）、變暗的那一半
  /// 壓暗（黑）；relief＜0 反過來。看起來像光跟著卡片轉動慢慢移動。
  void _relief(Canvas canvas, Rect rect) {
    final mask = images[PracticeCardMaterialSlot.light]!;
    final strength = light.relief.abs() * _kReliefGain;
    final toward = light.relief > 0;
    _image(
      canvas,
      mask,
      rect,
      Paint()
        ..blendMode = BlendMode.plus
        ..colorFilter = practiceReliefHalf(
          upper: toward,
          color: _tint,
          strength: strength,
        ),
    );
    _image(
      canvas,
      mask,
      rect,
      Paint()
        ..colorFilter = practiceReliefHalf(
          upper: !toward,
          color: Colors.black,
          strength: strength,
        ),
    );
  }

  /// 沿 115° 對角軸的漸層：[from]、[to] 是軸上的比例（左上角 0、右下角 1）。
  ui.Gradient _alongAxis(
    Rect rect,
    double from,
    double to,
    List<Color> colors,
    List<double> stops, [
    TileMode mode = TileMode.clamp,
  ]) {
    final span = rect.width * _axis.dx + rect.height * _axis.dy;
    return ui.Gradient.linear(
      rect.topLeft + _axis * (span * from),
      rect.topLeft + _axis * (span * to),
      colors,
      stops,
      mode,
    );
  }

  /// 高光帶（§6.4）：`light.B` 當遮罩（倒角、細線、節點 1，平頂 0.25）、沿 115° 的光帶 `srcIn`，
  /// 整層 `plus`。光帶染成這一階外框的亮色（金屬的反光帶自己的顏色，不把金洗成白）；強度跟著
  /// 染色從 N 0.26 走到 R 0.30、SR 0.34。
  void _specular(Canvas canvas, Rect rect) {
    final strength = _mix(
      PracticeRevealTheme.n.backSpecular,
      PracticeRevealTheme.r.backSpecular,
      PracticeRevealTheme.sr.backSpecular,
    );
    final tint = _tint;
    canvas.saveLayer(rect, Paint()..blendMode = BlendMode.plus);
    _image(
      canvas,
      images[PracticeCardMaterialSlot.light]!,
      rect,
      Paint()..colorFilter = practiceChannelAlpha(2, Colors.white, 1),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = BlendMode.srcIn
        ..shader = _alongAxis(
          rect,
          light.band - _kBandHalf,
          light.band + _kBandHalf,
          [
            tint.withValues(alpha: 0),
            tint.withValues(alpha: 0.55 * strength),
            tint.withValues(alpha: strength),
            tint.withValues(alpha: 0.55 * strength),
            tint.withValues(alpha: 0),
          ],
          const [0, 0.25, 0.5, 0.75, 1],
        ),
    );
    canvas.restore();
  }

  /// 染色當下的值：銀 → 藍 → 金（[dye] 只升到真實稀有度）。
  double _mix(double n, double r, double sr) =>
      (n + (r - n) * dye.blue) * (1 - dye.gold) + sr * dye.gold;

  /// 這一階金屬反光的顏色（外框的亮色，跟著染色走）。
  Color get _tint => Color.lerp(
        Color.lerp(
          PracticeRevealTheme.n.rimHi,
          PracticeRevealTheme.r.rimHi,
          dye.blue,
        ),
        PracticeRevealTheme.sr.rimHi,
        dye.gold,
      )!;

  /// SR 全息（§6.5）：`light.G`（×染金進度）當遮罩、右邊強左邊弱（示意圖二），再 `srcIn` 一條
  /// 115° 的重複彩虹；整層 `color` 混色只換色相與飽和度、保留金屬的明暗。色帶隨全息相位平移。
  void _holo(Canvas canvas, Rect rect) {
    final white = Colors.white;
    canvas.saveLayer(rect, Paint()..blendMode = BlendMode.color);
    _image(
      canvas,
      images[PracticeCardMaterialSlot.light]!,
      rect,
      Paint()
        ..colorFilter = practiceChannelAlpha(1, white, _kHoloAlpha * dye.gold),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = ui.Gradient.linear(
          rect.centerLeft,
          rect.centerRight,
          [
            white.withValues(alpha: 0.25),
            white.withValues(alpha: 0.25),
            white,
          ],
          const [0, 0.35, 1],
        ),
    );
    final span = rect.width * _axis.dx + rect.height * _axis.dy;
    final period = _kHoloPeriod * rect.width / span;
    final colors = [...kPracticeHoloColors, kPracticeHoloColors.first];
    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = BlendMode.srcIn
        ..shader = _alongAxis(
          rect,
          light.holoPhase * period,
          (light.holoPhase + 1) * period,
          colors,
          [for (var i = 0; i < colors.length; i++) i / (colors.length - 1)],
          TileMode.repeated,
        ),
    );
    canvas.restore();
  }

  /// 額外發光（§6.6）：`glowMask` 三個通道與 `glow` 泛光，顏色跟著染色走。用 `screen` 疊（結果
  /// ＝底＋光×(1−底)）：暗的地方（徽記外圍的光暈、暗帶）幾乎照樣加亮，本來就亮的金屬只微微提亮、
  /// 不會一起爆成一片白，蓄力與脈衝時徽記的倒角、拉絲仍看得到（#114 第 3 輪；原本是 `plus`）。
  void _energy(Canvas canvas, Rect rect) {
    final color = Color.lerp(
      Color.lerp(
        PracticeRevealTheme.n.glow,
        PracticeRevealTheme.r.glow,
        dye.blue,
      ),
      PracticeRevealTheme.sr.glow,
      dye.gold,
    )!;
    final mask = images[PracticeCardMaterialSlot.glowMask]!;
    for (final (channel, value, gain) in [
      (0, energy.emblem, _kEmblemGain),
      (1, energy.frame, _kFrameGain),
      (2, energy.lines, _kLinesGain),
    ]) {
      if (value <= 0) continue;
      _image(
        canvas,
        mask,
        rect,
        Paint()
          ..blendMode = BlendMode.screen
          ..colorFilter =
              practiceChannelAlpha(channel, color, (value * gain).clamp(0, 1)),
      );
    }
    final glow = images[PracticeCardMaterialSlot.glow];
    if (glow != null && energy.bloom > 0) {
      _image(
        canvas,
        glow,
        rect,
        Paint()
          ..blendMode = BlendMode.screen
          ..colorFilter = ColorFilter.mode(
            color.withValues(alpha: (energy.bloom * _kBloomGain).clamp(0, 1)),
            BlendMode.srcIn,
          ),
      );
    }
  }

  /// 顆粒（`overlay`，α 0.025）：雜訊磚重複鋪，防大面積暗部出現色帶。
  void _grain(Canvas canvas, Rect rect) {
    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = BlendMode.overlay
        ..color = Colors.white.withValues(alpha: _kGrainAlpha)
        ..shader = ImageShader(
          images[PracticeCardMaterialSlot.noise]!,
          TileMode.repeated,
          TileMode.repeated,
          Matrix4.diagonal3Values(grainScale, grainScale, 1).storage,
        ),
    );
  }

  @override
  bool shouldRepaint(PracticeCardBackPainter old) =>
      old.images != images ||
      old.dye != dye ||
      old.light != light ||
      old.energy != energy ||
      old.emblemWhite != emblemWhite ||
      old.tier != tier ||
      old.grainScale != grainScale;
}
