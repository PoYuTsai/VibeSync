// 抽卡卡片典藏材質的純函式（規格 docs/plans/2026-10-28-card-collectible-material-spec.md）：
// 姿態 → 光（§6.4）、全息色序（§6.5）、玻璃反光位置（§7.5）、切面星的十個面（§7.7）。

import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/core/theme/practice_reveal_palette.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_card_material.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_reveal_card.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_reveal_timing.dart';

void main() {
  group('practiceCardLight（§6.4）', () {
    test('卡面落定（yaw 180、pitch 0）＝停住的光：受光點在左上 225°', () {
      final light = practiceCardLight(yawDeg: 180, pitchDeg: 0, front: true);
      expect(light, PracticeCardLight.settled);
      expect(light.glintDeg, closeTo(225, 1e-9));
    });

    test('卡背以等待姿態為基準：等待中心點回到同一個 band', () {
      final light = practiceCardLight(
        yawDeg: PracticeRevealTiming.waitingYaw,
        pitchDeg: PracticeRevealTiming.waitingPitch,
        front: false,
      );
      expect(light.band, closeTo(0.35, 1e-9));
      expect(light.relief, 0);
    });

    test('band 隨 yaw 單調遞減：翻牌時高光從右下掃到左上；落定時從右下滑回來', () {
      double band(double yaw, {bool front = false}) =>
          practiceCardLight(yawDeg: yaw, pitchDeg: 4, front: front).band;
      for (var yaw = -30.0; yaw < 90; yaw += 5) {
        expect(band(yaw + 5), lessThan(band(yaw)), reason: '卡背 yaw $yaw');
      }
      for (var yaw = 95.0; yaw < 180; yaw += 5) {
        expect(band(yaw + 5, front: true), lessThan(band(yaw, front: true)),
            reason: '卡面 yaw $yaw');
      }
      // 翻牌前的回拉（yaw ≈ −25°）高光在右下，翻到 0° 已離開卡片左上。
      expect(band(-25), greaterThan(0.8));
      expect(band(0), lessThan(0));
    });

    test('外框受光點：側立時停在右下，落定時沿右邊、上緣滑到左上，不繞著外框轉圈', () {
      double glint(double yaw, {bool front = true}) =>
          practiceCardLight(yawDeg: yaw, pitchDeg: 0, front: front).glintDeg;
      // 卡面剛轉過側立（yaw 90°）：band 遠在卡外，受光點停在右下角（225°＋180°）。
      expect(glint(90), closeTo(405, 1e-9));
      for (var yaw = 90.0; yaw < 180; yaw += 5) {
        expect(glint(yaw + 5), lessThanOrEqualTo(glint(yaw)),
            reason: 'yaw $yaw');
      }
      expect(glint(180), closeTo(225, 1e-9));
      // 任何姿態（卡背翻牌也一樣）都只離左上半圈以內。
      for (var yaw = -90.0; yaw <= 270; yaw += 15) {
        for (final front in [false, true]) {
          expect(
            glint(yaw, front: front),
            inInclusiveRange(45.0, 405.0),
            reason: '${front ? '卡面' : '卡背'} yaw $yaw',
          );
        }
      }
    });

    test('浮雕補光夾在 −1..1；同一姿態算兩次結果相同', () {
      for (var yaw = -90.0; yaw <= 270; yaw += 15) {
        final a = practiceCardLight(yawDeg: yaw, pitchDeg: 9, front: false);
        final b = practiceCardLight(yawDeg: yaw, pitchDeg: 9, front: false);
        expect(a.relief, inInclusiveRange(-1.0, 1.0));
        expect(a, b);
      }
    });
  });

  group('practiceHoloColorAt（§6.5）', () {
    test('五色循環：玫瑰 → 洋紅 → 紫 → 天空藍 → 香檳，週期 1', () {
      // 比 8-bit ARGB：插值在交界處會有浮點尾數。
      int argb(double t) => practiceHoloColorAt(t).toARGB32();
      expect(argb(0), PracticeRevealPalette.holoRose.toARGB32());
      expect(argb(0.2), PracticeRevealPalette.holoMagenta.toARGB32());
      expect(argb(0.4), PracticeRevealPalette.holoPlum.toARGB32());
      expect(argb(0.6), PracticeRevealPalette.holoSky.toARGB32());
      expect(argb(0.8), PracticeRevealPalette.srHoloChampagne.toARGB32());
      expect(argb(1.0), PracticeRevealPalette.holoRose.toARGB32());
      expect(argb(-0.8), PracticeRevealPalette.holoMagenta.toARGB32());
    });
  });

  group('practiceInfoBarReflection（§7.5）', () {
    test('停住時在欄寬 0.72；卡面還在轉時在右邊外面，落定才滑進來', () {
      expect(
        practiceInfoBarReflection(PracticeCardLight.settled),
        closeTo(0.72, 1e-9),
      );
      final turning = practiceCardLight(yawDeg: 150, pitchDeg: 3, front: true);
      expect(practiceInfoBarReflection(turning), greaterThan(1.3));
    });
  });

  group('practiceFacetStar（§7.7）', () {
    const center = Offset(9, 9);
    const radius = 9.0;
    final faces = practiceFacetStar(center, radius);

    test('十個面，亮度拉成 0（最暗）..1（最亮）', () {
      expect(faces, hasLength(10));
      final lights = faces.map((f) => f.light).toList();
      expect(lights.reduce((a, b) => a < b ? a : b), closeTo(0, 1e-9));
      expect(lights.reduce((a, b) => a > b ? a : b), closeTo(1, 1e-9));
      for (final f in faces) {
        expect(f.points, hasLength(3));
        expect(f.points.first, center);
        for (final p in f.points) {
          expect((p - center).distance, lessThanOrEqualTo(radius + 1e-9));
        }
      }
    });

    test('光從左上來：最上面那個尖角，左半面比右半面亮', () {
      // 第 0 個尖角朝上：faces[0] 是左半（內角在 −126°）、faces[1] 是右半。
      expect(faces[0].light, greaterThan(faces[1].light));
    });
  });
}
