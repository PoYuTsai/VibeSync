import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../../core/theme/partner_signal_palette.dart';
import '../../../analysis/domain/entities/guide_v3_result.dart';

/// 首頁對象卡燈號的亮燈與文字主色（Bruce 2026-10-21 燈號標籤規格）。只用在首頁對象卡；
/// 報告頁等其他燈號仍用 `guideV3LightColor`。
Color partnerSignalColor(GuideV3Light light) => switch (light) {
      GuideV3Light.green => PartnerSignalPalette.green,
      GuideV3Light.yellow => PartnerSignalPalette.yellow,
      GuideV3Light.red => PartnerSignalPalette.red,
    };

/// 三顆燈由左到右固定是青綠、黃、紅（日本橫式信號機）；亮哪顆只看燈號。
int partnerSignalLitIndex(GuideV3Light light) => switch (light) {
      GuideV3Light.green => 0,
      GuideV3Light.yellow => 1,
      GuideV3Light.red => 2,
    };

/// 微型日本橫式 LED 三燈信號機（含遮陽罩 42 × 16）。靜態、純裝飾：燈號由旁邊的字念出來，
/// 這裡不給 VoiceOver 語意。外面包 RepaintBoundary，頭像流光或捲動時不跟著重畫。
class JapaneseLedSignal extends StatelessWidget {
  const JapaneseLedSignal({super.key, required this.light});

  final GuideV3Light light;

  /// 含遮陽罩的外接尺寸（logical px）。
  static const Size size = Size(
    JapaneseLedSignalPainter.designWidth,
    JapaneseLedSignalPainter.designHeight,
  );

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          size: size,
          painter: JapaneseLedSignalPainter(light: light),
        ),
      ),
    );
  }
}

/// 用 42 × 16 的設計座標畫，實際尺寸等比縮放。三種燈號共用同一組外殼、鏡片、遮陽罩與
/// 點陣座標，只換哪顆亮；點陣位置事先算好，不在每次重畫時產生。
class JapaneseLedSignalPainter extends CustomPainter {
  const JapaneseLedSignalPainter({required this.light});

  final GuideV3Light light;

  static const double designWidth = 42;
  static const double designHeight = 16;

  /// 三顆鏡片的中心（規格參考座標）與半徑。
  static const List<Offset> lensCenters = [
    Offset(8, 8.5),
    Offset(21, 8.5),
    Offset(34, 8.5),
  ];
  static const double lensRadius = 5.1;

  // 外殼：低矮的切角金屬盒（切角是金屬切面，不是容器圓角）。
  static const Rect _housing = Rect.fromLTRB(0.5, 1, 41.5, 15.5);
  static const double _chamfer = 1.6;
  static const List<Offset> _rivets = [
    Offset(14.5, 2.4),
    Offset(27.5, 2.4),
    Offset(14.5, 14.2),
    Offset(27.5, 14.2),
  ];

  // 遮陽罩（庇）：鏡片外的一圈弧形帶，從左側略低於水平、經過頂端到右側略低於水平，
  // 看起來是往前伸、左右往下彎。
  static const double _hoodInner = 5.35;
  static const double _hoodOuter = 6.4;
  static const double _hoodStart = math.pi - 0.3;
  static const double _hoodSweep = math.pi + 0.6;

  // 亮燈鏡片外一圈克制的同色光，收在外殼內。
  static const double _haloRadius = 6.3;

  // LED 點陣：間距 1.15、點徑 0.7，裁在半徑 4.65 的圓內（9 列）。點徑取規格上限，
  // 原尺寸下亮燈才讀得出來；3 倍螢幕上點與點之間仍有暗隙。
  static const double _dotPitch = 1.15;
  static const double _dotRadius = 0.35;
  static const double dotFieldRadius = 4.65;

  /// 點陣相對鏡片中心的位置（三顆鏡片共用）。
  static final List<Offset> dotOffsets = List.unmodifiable([
    for (var row = -4; row <= 4; row++)
      for (var col = -4; col <= 4; col++)
        if (Offset(col * _dotPitch, row * _dotPitch).distance <= dotFieldRadius)
          Offset(col * _dotPitch, row * _dotPitch),
  ]);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / designWidth, size.height / designHeight);
    _paintHousing(canvas);
    final lit = partnerSignalLitIndex(light);
    final tone = partnerSignalColor(light);
    for (var i = 0; i < lensCenters.length; i++) {
      final center = lensCenters[i];
      if (i == lit) {
        _paintLitLens(canvas, center, tone);
      } else {
        _paintDarkLens(canvas, center);
      }
      _paintHood(canvas, center);
    }
    canvas.restore();
  }

  void _paintHousing(Canvas canvas) {
    const r = _housing;
    const c = _chamfer;
    final body = Path()
      ..moveTo(r.left + c, r.top)
      ..lineTo(r.right - c, r.top)
      ..lineTo(r.right, r.top + c)
      ..lineTo(r.right, r.bottom - c)
      ..lineTo(r.right - c, r.bottom)
      ..lineTo(r.left + c, r.bottom)
      ..lineTo(r.left, r.bottom - c)
      ..lineTo(r.left, r.top + c)
      ..close();
    canvas.drawPath(
      body,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            PartnerSignalPalette.housingTop,
            PartnerSignalPalette.housingBottom,
          ],
        ).createShader(r),
    );
    // 上緣一道窄亮邊、下緣一道暗邊：讀得出金屬切面。
    final bevel = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.35;
    canvas.drawLine(
      Offset(r.left + c, r.top + 0.35),
      Offset(r.right - c, r.top + 0.35),
      bevel
        ..color = PartnerSignalPalette.housingHighlight.withValues(alpha: 0.75),
    );
    canvas.drawLine(
      Offset(r.left + c, r.bottom - 0.35),
      Offset(r.right - c, r.bottom - 0.35),
      bevel..color = PartnerSignalPalette.housingEdge,
    );
    canvas.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5
        ..color = PartnerSignalPalette.housingEdge,
    );
    final shade = Paint()..color = PartnerSignalPalette.housingEdge;
    final rivet = Paint()..color = PartnerSignalPalette.rivet;
    for (final p in _rivets) {
      canvas.drawCircle(p + const Offset(0.12, 0.12), 0.42, shade);
      canvas.drawCircle(p, 0.36, rivet);
    }
  }

  void _paintLensBody(Canvas canvas, Offset center) {
    canvas.drawCircle(
      center,
      lensRadius,
      Paint()
        ..shader = const RadialGradient(
          colors: [
            PartnerSignalPalette.lensCenter,
            PartnerSignalPalette.lensDark
          ],
        ).createShader(Rect.fromCircle(center: center, radius: lensRadius)),
    );
  }

  void _paintLensRim(Canvas canvas, Offset center) {
    canvas.drawCircle(
      center,
      lensRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.45
        ..color = PartnerSignalPalette.lensRim,
    );
  }

  void _paintLitLens(Canvas canvas, Offset center, Color tone) {
    // 一層漸層當光暈（不對每顆 LED 模糊）；上半被遮陽罩擋住，下半落在外殼上。
    canvas.drawCircle(
      center,
      _haloRadius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            tone.withValues(alpha: 0.38),
            tone.withValues(alpha: 0.38),
            tone.withValues(alpha: 0),
          ],
          stops: const [0, lensRadius / _haloRadius, 1],
        ).createShader(Rect.fromCircle(center: center, radius: _haloRadius)),
    );
    _paintLensBody(canvas, center);
    // 同色底光要克制：點與點之間保留暗隙。
    canvas.drawCircle(
      center,
      lensRadius,
      Paint()
        ..shader = RadialGradient(
          colors: [tone.withValues(alpha: 0.36), tone.withValues(alpha: 0.12)],
        ).createShader(Rect.fromCircle(center: center, radius: lensRadius)),
    );
    // 中心偏白、往外漸成燈色。
    final dot = Paint();
    for (final offset in dotOffsets) {
      final t = offset.distance / dotFieldRadius;
      dot.color =
          Color.lerp(PartnerSignalPalette.ledCore, tone, 0.35 + 0.65 * t)!
              .withValues(alpha: 1 - 0.1 * t);
      canvas.drawCircle(center + offset, _dotRadius, dot);
    }
    _paintLensRim(canvas, center);
  }

  void _paintDarkLens(Canvas canvas, Offset center) {
    _paintLensBody(canvas, center);
    final dot = Paint()..color = PartnerSignalPalette.unlitGrid;
    for (final offset in dotOffsets) {
      canvas.drawCircle(center + offset, _dotRadius, dot);
    }
    _paintLensRim(canvas, center);
    // 左上角很淡的透鏡反光，沒有外發光。
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: 3.7),
      math.pi * 1.08,
      math.pi * 0.32,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.4
        ..strokeCap = StrokeCap.round
        ..color = PartnerSignalPalette.lensGlint,
    );
  }

  void _paintHood(Canvas canvas, Offset center) {
    final outer = Rect.fromCircle(center: center, radius: _hoodOuter);
    final inner = Rect.fromCircle(center: center, radius: _hoodInner);
    final band = Path()
      ..arcTo(outer, _hoodStart, _hoodSweep, true)
      ..arcTo(inner, _hoodStart + _hoodSweep, -_hoodSweep, false)
      ..close();
    // 深色內側：從正面看到的是罩子的內面。
    canvas.drawPath(band, Paint()..color = PartnerSignalPalette.hoodInner);
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.3
      ..color = PartnerSignalPalette.hoodSide;
    canvas.drawArc(outer, _hoodStart, _hoodSweep, false, edge);
    // 兩側短邊：罩子往下彎的切口。
    for (final angle in const [_hoodStart, _hoodStart + _hoodSweep]) {
      final direction = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(
        center + direction * _hoodInner,
        center + direction * _hoodOuter,
        edge..strokeWidth = 0.4,
      );
    }
    // 頂端窄亮邊：只描罩子上緣的一段。
    canvas.drawArc(
      outer,
      math.pi * 1.5 - 0.95,
      1.9,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.4
        ..strokeCap = StrokeCap.round
        ..color = PartnerSignalPalette.hoodHighlight,
    );
  }

  @override
  bool shouldRepaint(JapaneseLedSignalPainter oldDelegate) =>
      oldDelegate.light != light;
}
