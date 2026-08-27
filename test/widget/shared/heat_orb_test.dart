// test/widget/shared/heat_orb_test.dart
//
// HeatOrb 的合約測試。
//
// 三層：
//   1. 分段映射——五段界線與可見滿分是拍板規格，邊界值逐一鎖住。
//   2. 色帶／速度的設計意圖——越熱越快、越亮、越大幅，這是「慢慢升溫」的
//      定義。任何一項被改成非單調就是把設計改掉了，測試要擋下來。
//   3. Widget 行為——reduce motion 守門（同時也是 pumpAndSettle 能不能收斂
//      的關鍵），以及各段都畫得出來不丟例外。
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vibesync/core/constants/app_constants.dart';
import 'package:vibesync/shared/widgets/brand/heat_orb.dart';

import '../../helpers/motion_free_app.dart';

void main() {
  group('heatOrbBandFor 分段映射', () {
    test('null（尚未分析）落在最冷那段', () {
      expect(heatOrbBandFor(null).name, 'distant');
    });

    test('0–35 → distant（邊界 0 / 35）', () {
      expect(heatOrbBandFor(0).name, 'distant');
      expect(heatOrbBandFor(18).name, 'distant');
      expect(heatOrbBandFor(35).name, 'distant');
    });

    test('36–50 → approaching（邊界 36 / 50）', () {
      expect(heatOrbBandFor(36).name, 'approaching');
      expect(heatOrbBandFor(43).name, 'approaching');
      expect(heatOrbBandFor(50).name, 'approaching');
    });

    test('51–65 → responding（邊界 51 / 65）', () {
      expect(heatOrbBandFor(51).name, 'responding');
      expect(heatOrbBandFor(63).name, 'responding');
      expect(heatOrbBandFor(65).name, 'responding');
    });

    test('66–80 → warm（邊界 66 / 80）', () {
      expect(heatOrbBandFor(66).name, 'warm');
      expect(heatOrbBandFor(75).name, 'warm');
      expect(heatOrbBandFor(80).name, 'warm');
    });

    test('81–90 → burning（邊界 81 / 90）', () {
      expect(heatOrbBandFor(81).name, 'burning');
      expect(heatOrbBandFor(90).name, 'burning');
    });

    test('超界值被夾回可見範圍，不會掉出分段', () {
      expect(heatOrbBandFor(95).name, 'burning',
          reason: 'legacy 未校準分數仍應落在最熱那段，不能回傳 null 或丟例外');
      expect(heatOrbBandFor(-5).name, 'distant');
    });
  });

  group('kHeatOrbBands 設計意圖', () {
    test('從 0 起、收在可見滿分，中間不留縫也不重疊', () {
      expect(kHeatOrbBands.first.min, 0);
      expect(kHeatOrbBands.last.max, AppConstants.investmentVisibleMax);
      for (var i = 1; i < kHeatOrbBands.length; i++) {
        expect(
          kHeatOrbBands[i].min,
          kHeatOrbBands[i - 1].max + 1,
          reason: '第 ${i + 1} 段的下界必須緊接上一段的上界，中間不能有分數落空',
        );
      }
    });

    test('五段', () {
      expect(kHeatOrbBands.length, 5);
    });

    test('越熱越快——一圈秒數嚴格遞減', () {
      for (var i = 1; i < kHeatOrbBands.length; i++) {
        expect(
          kHeatOrbBands[i].cycleSeconds,
          lessThan(kHeatOrbBands[i - 1].cycleSeconds),
          reason: '速度是這套設計的訊號載體；某一段變得比前一段慢就不是升溫了',
        );
      }
    });

    test('越熱越亮、呼吸越大、內部越翻湧', () {
      for (var i = 1; i < kHeatOrbBands.length; i++) {
        final prev = kHeatOrbBands[i - 1];
        final cur = kHeatOrbBands[i];
        expect(cur.coreAlpha, greaterThan(prev.coreAlpha));
        expect(cur.amplitude, greaterThan(prev.amplitude));
        expect(cur.churn, greaterThanOrEqualTo(prev.churn));
        expect(cur.cores, greaterThanOrEqualTo(prev.cores));
      }
    });

    test('只有最熱的兩段有火星，最熱那段最多', () {
      expect(kHeatOrbBands[0].embers, 0);
      expect(kHeatOrbBands[1].embers, 0);
      expect(kHeatOrbBands[2].embers, 0);
      expect(kHeatOrbBands[3].embers, greaterThan(0));
      expect(kHeatOrbBands[4].embers,
          greaterThan(kHeatOrbBands[3].embers));
    });

    test('只有最熱那段帶火焰行為', () {
      for (final band in kHeatOrbBands.take(kHeatOrbBands.length - 1)) {
        expect(band.flame, 0, reason: '${band.name} 不該有向上竄動');
      }
      expect(kHeatOrbBands.last.flame, greaterThan(0));
    });

    test('外暈永遠留有紫底透出來（紀律 3：純橘會變貼紙）', () {
      // 五段的外暈都不能是純暖色——藍色通道必須有足夠份量，紫才透得出來。
      for (final band in kHeatOrbBands) {
        expect(
          band.halo.b,
          greaterThan(0.35),
          reason: '${band.name} 的外暈藍色通道太低，會失去紫底、看起來像貼紙',
        );
      }
    });
  });

  group('HeatOrbBand.lerp', () {
    test('兩端點原樣回傳', () {
      final a = kHeatOrbBands.first;
      final b = kHeatOrbBands.last;
      expect(HeatOrbBand.lerp(a, b, 0).cycleSeconds, a.cycleSeconds);
      expect(HeatOrbBand.lerp(a, b, 1).cycleSeconds, b.cycleSeconds);
    });

    test('中間值落在兩端之間——顆數是小數，換段才能淡入而不是啪一聲多一顆', () {
      final a = kHeatOrbBands[2]; // responding: 2 顆核心
      final b = kHeatOrbBands[3]; // warm: 3 顆核心
      final mid = HeatOrbBand.lerp(a, b, 0.5);
      expect(mid.cores, greaterThan(a.cores));
      expect(mid.cores, lessThan(b.cores));
      expect(mid.cycleSeconds, lessThan(a.cycleSeconds));
      expect(mid.cycleSeconds, greaterThan(b.cycleSeconds));
    });
  });

  group('heatOrbCoreAngle 換段連續性', () {
    // 迴歸鎖：這裡曾經用 cores.ceil() 當排位分母，導致顆數一從 2.0 跨到
    // 2.001，既有第二顆內核就在同一格從 180° 跳到 120°。淡入係數只顧到新
    // 內核的透明度，顧不到舊內核的位置——600ms 溶接因此名存實亡。
    test('顆數剛跨過 2.0 的那一格，第二顆內核不跳位', () {
      final before = heatOrbCoreAngle(phase: 0, index: 1, cores: 2.0);
      final after = heatOrbCoreAngle(phase: 0, index: 1, cores: 2.001);
      expect(before, closeTo(math.pi, 1e-9), reason: '2 顆時應該對開 180°');
      // 舊寫法在這裡是 60°（1.047 rad）的硬跳；門檻取 0.01 rad（約 0.57°）
      // 遠低於可見範圍，又不會誤殺正常的連續位移。
      expect((before - after).abs(), lessThan(0.01),
          reason: '跨過整數邊界不該產生可見跳動');
    });

    test('2 → 3 顆的整段轉場：角度單調收斂，且沒有任何一格跳超過 1°', () {
      const steps = 200;
      const oneDegree = math.pi / 180;
      var prev = heatOrbCoreAngle(phase: 0, index: 1, cores: 2.0);
      for (var s = 1; s <= steps; s++) {
        final cores = 2.0 + s / steps;
        final cur = heatOrbCoreAngle(phase: 0, index: 1, cores: cores);
        expect(cur, lessThan(prev), reason: 'cores=$cores 角度應持續收斂');
        expect((prev - cur).abs(), lessThan(oneDegree),
            reason: 'cores=$cores 出現視覺可見的跳動');
        prev = cur;
      }
      expect(prev, closeTo(2 * math.pi / 3, 1e-9),
          reason: '3 顆時應該三等分 120°');
    });

    test('整數顆數仍是標準等分', () {
      expect(heatOrbCoreAngle(phase: 0, index: 1, cores: 3),
          closeTo(2 * math.pi / 3, 1e-9));
      expect(heatOrbCoreAngle(phase: 0, index: 2, cores: 3),
          closeTo(4 * math.pi / 3, 1e-9));
      expect(heatOrbCoreAngle(phase: 0, index: 0, cores: 1), 0);
    });

    test('相位只是整體旋轉，不影響顆與顆之間的相對排位', () {
      final gapAtZero = heatOrbCoreAngle(phase: 0, index: 1, cores: 2.5) -
          heatOrbCoreAngle(phase: 0, index: 0, cores: 2.5);
      final gapAtHalf = heatOrbCoreAngle(phase: 0.5, index: 1, cores: 2.5) -
          heatOrbCoreAngle(phase: 0.5, index: 0, cores: 2.5);
      expect(gapAtZero, closeTo(gapAtHalf, 1e-9));
    });
  });

  group('HeatOrb widget', () {
    testWidgets('reduce motion：停在靜止幀，pumpAndSettle 會收斂', (t) async {
      await t.pumpWidget(motionFreeApp(
        home: const Scaffold(
          body: Center(child: HeatOrb(heat: 85)),
        ),
      ));

      // 這一行不 timeout 就是通過：關動畫後不能再有排程中的 frame，否則所有
      // 渲染這張卡的畫面測試都會被拖垮。
      await t.pumpAndSettle();
      expect(find.byType(HeatOrb), findsOneWidget);
      expect(t.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('動畫開著時持續排程 frame（真的在呼吸）', (t) async {
      await t.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: HeatOrb(heat: 85))),
      ));
      await t.pump(const Duration(milliseconds: 16));
      expect(t.binding.hasScheduledFrame, isTrue);
    });

    testWidgets('五段都畫得出來，不丟例外', (t) async {
      for (final heat in const [0, 40, 60, 75, 90]) {
        await t.pumpWidget(motionFreeApp(
          home: Scaffold(body: Center(child: HeatOrb(heat: heat))),
        ));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: 'heat=$heat 繪製失敗');
      }
    });

    testWidgets('null heat 也畫得出來（尚未分析＝最冷那段）', (t) async {
      await t.pumpWidget(motionFreeApp(
        home: const Scaffold(body: Center(child: HeatOrb(heat: null))),
      ));
      await t.pumpAndSettle();
      expect(find.byType(HeatOrb), findsOneWidget);
    });

    testWidgets('換分數換段不丟例外（溶接路徑）', (t) async {
      await t.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: HeatOrb(heat: 20))),
      ));
      await t.pump(const Duration(milliseconds: 100));

      await t.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: HeatOrb(heat: 88))),
      ));
      // 跨越整個 600ms 溶接窗口。
      await t.pump(const Duration(milliseconds: 300));
      await t.pump(const Duration(milliseconds: 400));

      expect(find.byType(HeatOrb), findsOneWidget);
    });

    testWidgets('尺寸為 0 不丟例外', (t) async {
      await t.pumpWidget(motionFreeApp(
        home: const Scaffold(
          body: Center(child: HeatOrb(heat: 50, size: 0)),
        ),
      ));
      await t.pumpAndSettle();
      expect(find.byType(HeatOrb), findsOneWidget);
    });
  });
}
