import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vibesync/core/theme/partner_signal_palette.dart';
import 'package:vibesync/features/analysis/domain/entities/guide_v3_result.dart';
import 'package:vibesync/features/partner/presentation/widgets/japanese_led_signal.dart';

/// 放大 10 倍畫，外面留 4 的透明邊，用來檢查有沒有畫出 42 × 16 之外。
const double _ratio = 10;
const double _margin = 4;

class _Pixels {
  _Pixels(this.width, this.bytes);

  final int width;
  final ByteData bytes;

  /// 設計座標（相對信號機左上角）→ RGBA，各 0～1。
  List<double> at(double x, double y) {
    final px = ((_margin + x) * _ratio).round();
    final py = ((_margin + y) * _ratio).round();
    return rawAt(px, py);
  }

  List<double> rawAt(int px, int py) {
    final i = (py * width + px) * 4;
    return [for (var k = 0; k < 4; k++) bytes.getUint8(i + k) / 255];
  }
}

double _luminance(List<double> rgba) =>
    0.2126 * rgba[0] + 0.7152 * rgba[1] + 0.0722 * rgba[2];

double _distance(List<double> rgba, Color c) {
  final dr = rgba[0] - c.r;
  final dg = rgba[1] - c.g;
  final db = rgba[2] - c.b;
  return dr * dr + dg * dg + db * db;
}

Future<_Pixels> _render(WidgetTester t, GuideV3Light light) async {
  final key = GlobalKey();
  await t.pumpWidget(
    Center(
      child: RepaintBoundary(
        key: key,
        child: Padding(
          padding: const EdgeInsets.all(_margin),
          child: JapaneseLedSignal(light: light),
        ),
      ),
    ),
  );
  final boundary = t.renderObject<RenderRepaintBoundary>(find.byKey(key));
  final image = (await t.runAsync(() => boundary.toImage(pixelRatio: _ratio)))!;
  final bytes = (await t.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
  ))!;
  final pixels = _Pixels(image.width, bytes);
  image.dispose();
  return pixels;
}

void main() {
  testWidgets('外接尺寸 42 × 16，不給 VoiceOver 語意', (t) async {
    final semantics = t.ensureSemantics();
    await t.pumpWidget(
      const Center(child: JapaneseLedSignal(light: GuideV3Light.green)),
    );
    expect(t.getSize(find.byType(JapaneseLedSignal)), const Size(42, 16));
    expect(find.bySemanticsLabel(RegExp('.+')), findsNothing);
    semantics.dispose();
  });

  test('三顆燈由左到右固定青綠、黃、紅；顏色只用這組色票', () {
    expect(partnerSignalLitIndex(GuideV3Light.green), 0);
    expect(partnerSignalLitIndex(GuideV3Light.yellow), 1);
    expect(partnerSignalLitIndex(GuideV3Light.red), 2);
    expect(partnerSignalColor(GuideV3Light.green), PartnerSignalPalette.green);
    expect(
        partnerSignalColor(GuideV3Light.yellow), PartnerSignalPalette.yellow);
    expect(partnerSignalColor(GuideV3Light.red), PartnerSignalPalette.red);
  });

  test('點陣：9 列、整齊排列、收在鏡片內；三顆鏡片共用同一組座標', () {
    final dots = JapaneseLedSignalPainter.dotOffsets;
    expect(dots.map((o) => o.dy).toSet(), hasLength(9));
    expect(dots.map((o) => o.dx).toSet(), hasLength(9));
    for (final dot in dots) {
      expect(
        dot.distance,
        lessThanOrEqualTo(JapaneseLedSignalPainter.dotFieldRadius),
      );
    }
    expect(
      JapaneseLedSignalPainter.dotFieldRadius,
      lessThan(JapaneseLedSignalPainter.lensRadius),
    );
    expect(JapaneseLedSignalPainter.lensCenters.map((c) => c.dy).toSet(),
        hasLength(1));
  });

  test('只有燈號改變才重畫', () {
    const green = JapaneseLedSignalPainter(light: GuideV3Light.green);
    expect(
      green.shouldRepaint(
        const JapaneseLedSignalPainter(light: GuideV3Light.green),
      ),
      isFalse,
    );
    expect(
      green.shouldRepaint(
        const JapaneseLedSignalPainter(light: GuideV3Light.red),
      ),
      isTrue,
    );
  });

  testWidgets('每次只亮一顆：亮的那顆是對的顏色，另外兩顆是暗的；不畫出外框', (t) async {
    const centers = JapaneseLedSignalPainter.lensCenters;
    const tones = [
      PartnerSignalPalette.green,
      PartnerSignalPalette.yellow,
      PartnerSignalPalette.red,
    ];
    for (final light in GuideV3Light.values) {
      final pixels = await _render(t, light);
      final lit = partnerSignalLitIndex(light);
      for (var i = 0; i < centers.length; i++) {
        final center = pixels.at(centers[i].dx, centers[i].dy);
        if (i == lit) {
          expect(_luminance(center), greaterThan(0.5),
              reason: '${light.wire} 亮燈');
          // 鏡片邊緣那顆 LED 最接近燈色本身。
          final edge = pixels.at(centers[i].dx + 4.6, centers[i].dy);
          final nearest = tones.reduce(
            (a, b) => _distance(edge, a) <= _distance(edge, b) ? a : b,
          );
          expect(nearest, partnerSignalColor(light), reason: light.wire);
        } else {
          // 暗燈只留極弱的格紋（中心那顆點是深灰），跟亮燈差很遠。
          expect(_luminance(center), lessThan(0.25),
              reason: '${light.wire} 第 $i 顆應該是暗的');
        }
      }

      // 外框（42 × 16 以外的透明邊）一點都不能畫到：光暈與遮陽罩都收在燈具內。
      final width = ((42 + 2 * _margin) * _ratio).round();
      final height = ((16 + 2 * _margin) * _ratio).round();
      final inset = (_margin * _ratio).round();
      final painted = <String>[];
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final inside = x >= inset &&
              x < width - inset &&
              y >= inset &&
              y < height - inset;
          if (!inside && pixels.rawAt(x, y)[3] > 0) painted.add('($x, $y)');
        }
      }
      expect(painted, isEmpty, reason: '${light.wire} 畫出外框：${painted.take(5)}');
    }
  });
}
