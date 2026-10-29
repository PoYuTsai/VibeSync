// 抽卡卡片典藏材質的純函式（規格 docs/plans/2026-10-28-card-collectible-material-spec.md）：
// 姿態 → 光（§6.4）、全息色序（§6.5）、玻璃反光位置（§7.5）、切面星的十個面（§7.7）；
// 卡背（§5.4、§6）的素材解碼大小、轉化擴散、額外發光、圖層組合（稀有度誠實）與遮罩通道。

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/core/theme/practice_reveal_palette.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_girl_rarity.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_card_material.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_reveal_card.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_reveal_theme.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_reveal_timing.dart';

/// 單色假素材（測試不解真的 WebP）。
Future<ui.Image> _solid(Color color, {int width = 12, int height = 18}) {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = color,
  );
  return recorder.endRecording().toImage(width, height);
}

/// 把 [paint] 畫在黑底上，讀左上角那一點的 RGBA。
Future<List<int>> _pixel(void Function(Canvas canvas, Rect rect) paint) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const rect = Rect.fromLTWH(0, 0, 4, 4);
  canvas.drawRect(rect, Paint()..color = Colors.black);
  paint(canvas, rect);
  final image = await recorder.endRecording().toImage(4, 4);
  final data = await image.toByteData();
  image.dispose();
  return data!.buffer.asUint8List(0, 4).toList();
}

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

  group('卡背素材（§5.4、§6.1）', () {
    test('成品圖與 light 解成卡片像素寬（上限 1200），遮罩與泛光解一半，雜訊磚原尺寸', () {
      for (final slot in [
        PracticeCardMaterialSlot.n,
        PracticeCardMaterialSlot.r,
        PracticeCardMaterialSlot.sr,
        PracticeCardMaterialSlot.light,
      ]) {
        final provider = slot.provider(1062) as ResizeImage;
        expect(provider.width, 1062, reason: slot.name);
        expect(provider.height, isNull, reason: '${slot.name} 等比例');
        expect((provider.imageProvider as AssetImage).assetName, slot.asset);
      }
      expect(
        (PracticeCardMaterialSlot.n.provider(1500) as ResizeImage).width,
        1200,
      );
      expect(
        (PracticeCardMaterialSlot.glowMask.provider(1063) as ResizeImage).width,
        532,
      );
      expect(
        (PracticeCardMaterialSlot.glow.provider(1062) as ResizeImage).width,
        531,
      );
      expect(PracticeCardMaterialSlot.noise.provider(1062), isA<AssetImage>());
    });

    test('儀式掛上先解 N 那組；R、SR 按下翻牌才解、收卡釋放', () {
      expect(
        {
          ...PracticeCardMaterialSlot.base,
          ...PracticeCardMaterialSlot.tiers,
        },
        PracticeCardMaterialSlot.values.toSet(),
      );
      expect(
        PracticeCardMaterialSlot.base
            .intersection(PracticeCardMaterialSlot.tiers),
        isEmpty,
      );
      expect(PracticeCardMaterialSlot.tiers, {
        PracticeCardMaterialSlot.r,
        PracticeCardMaterialSlot.sr,
      });
    });

    test('七張素材都在，大小不超過上限（合計 ≤ 2.3 MB）', () {
      const limits = {
        PracticeCardMaterialSlot.n: 600 * 1024,
        PracticeCardMaterialSlot.r: 600 * 1024,
        PracticeCardMaterialSlot.sr: 600 * 1024,
        PracticeCardMaterialSlot.light: 300 * 1024,
        PracticeCardMaterialSlot.glowMask: 80 * 1024,
        PracticeCardMaterialSlot.glow: 60 * 1024,
        PracticeCardMaterialSlot.noise: 20 * 1024,
      };
      var total = 0;
      for (final slot in PracticeCardMaterialSlot.values) {
        final file = File(slot.asset);
        expect(file.existsSync(), isTrue, reason: slot.asset);
        final bytes = file.lengthSync();
        expect(bytes, lessThanOrEqualTo(limits[slot]!), reason: slot.asset);
        total += bytes;
      }
      expect(total, lessThanOrEqualTo(2300 * 1024));
    });
  });

  group('轉化擴散（§6.3）', () {
    const size = Size(354, 531);
    final halfDiag = size.center(Offset.zero).distance;

    test('t＝0 半徑 0、t＝1 超過 1.2×半對角線（蓋滿整張卡）、半徑單調', () {
      expect(practiceCardDiffusion(0, size).radius, 0);
      expect(
        practiceCardDiffusion(1, size).radius,
        greaterThanOrEqualTo(1.2 * halfDiag - 1e-9),
      );
      var last = -1.0;
      for (var t = 0.0; t <= 1.0001; t += 0.05) {
        final r = practiceCardDiffusion(t, size).radius;
        expect(r, greaterThan(last), reason: 't $t');
        last = r;
      }
      expect(practiceCardDiffusion(0.5, size).soft, closeTo(0.18 * halfDiag, 1e-9));
    });

    test('前緣光環：開始與結束都是 0，中段最亮 0.65', () {
      expect(practiceCardDiffusion(0, size).ringAlpha, closeTo(0, 1e-9));
      expect(practiceCardDiffusion(1, size).ringAlpha, closeTo(0, 1e-9));
      expect(practiceCardDiffusion(0.5, size).ringAlpha, closeTo(0.65, 1e-9));
      expect(
        practiceCardDiffusion(0.5, size).ringWidth,
        closeTo(0.06 * halfDiag, 1e-9),
      );
    });
  });

  group('額外發光（§6.6）', () {
    test('等待：徽記 0.30 是靜止值（成品圖已經畫進去），呼吸與心跳多出來的才發光', () {
      expect(PracticeCardBackEnergy.waiting(0.30).isZero, isTrue);
      final beat = PracticeCardBackEnergy.waiting(0.57);
      expect(beat.emblem, closeTo(0.27, 1e-9));
      expect(beat.bloom, closeTo(0.27, 1e-9));
      expect(beat.frame, 0);
      expect(beat.lines, 0);
    });

    test('N 只有徽記：蓄力留到翻牌、銀光脈衝 0.80 → 1.00 → 0.85；外框與線路不亮', () {
      for (var ms = 0.0; ms <= PracticeRevealTiming.flipPeakMs; ms += 25) {
        final e = practiceCardBackEnergy(ms, PracticeGirlRarity.n);
        expect(e.frame, 0, reason: '$ms ms');
        expect(e.lines, 0, reason: '$ms ms');
      }
      expect(
        practiceCardBackEnergy(PracticeRevealTiming.chargeEndMs,
                PracticeGirlRarity.n)
            .emblem,
        closeTo(0.5, 1e-9),
      );
      expect(
        practiceCardBackEnergy(PracticeRevealTiming.silverPulsePeakMs,
                PracticeGirlRarity.n)
            .emblem,
        closeTo(0.7, 1e-9),
      );
      expect(
        practiceCardBackEnergy(PracticeRevealTiming.flipStartMs,
                PracticeGirlRarity.n)
            .emblem,
        closeTo(0.55, 1e-9),
      );
    });

    test('R：染藍時徽記、外框、線路、泛光一起升到 1，染完 280 ms 退回靜止', () {
      const rarity = PracticeGirlRarity.r;
      expect(practiceCardBackDyePulse(PracticeRevealTiming.dyeBlueMs, rarity),
          0);
      expect(
        practiceCardBackDyePulse(PracticeRevealTiming.dyeBlueEndMs, rarity),
        closeTo(1, 1e-9),
      );
      final after = practiceCardBackEnergy(
        PracticeRevealTiming.dyeBlueEndMs + 280,
        rarity,
      );
      expect(after.frame, closeTo(0, 1e-9));
      expect(after.lines, closeTo(0, 1e-9));
      expect(after.emblem, closeTo(0.5, 1e-9), reason: '只剩蓄力');
    });

    test('SR：染藍的脈衝撐到染金結束才退——升一次、降一次，不多一次閃光', () {
      const rarity = PracticeGirlRarity.sr;
      var last = 0.0;
      var falling = false;
      for (var ms = 0.0; ms <= PracticeRevealTiming.flipPeakMs; ms += 10) {
        final pulse = practiceCardBackDyePulse(ms, rarity);
        if (pulse < last - 1e-12) falling = true;
        if (falling) {
          expect(pulse, lessThanOrEqualTo(last + 1e-12), reason: '$ms ms 又升');
        }
        last = pulse;
      }
      expect(
        practiceCardBackDyePulse(PracticeRevealTiming.dyeGoldEndMs, rarity),
        closeTo(1, 1e-9),
      );
      expect(
        practiceCardBackDyePulse(PracticeRevealTiming.dyeGoldEndMs + 280, rarity),
        closeTo(0, 1e-9),
      );
    });
  });

  group('PracticeCardBackPainter（§6.2）', () {
    late PracticeCardMaterialImages all;

    setUpAll(() async {
      all = PracticeCardMaterialImages({
        for (final slot in PracticeCardMaterialSlot.values)
          slot: await _solid(
            switch (slot) {
              PracticeCardMaterialSlot.light => const Color(0xFFC08080),
              PracticeCardMaterialSlot.glowMask => const Color(0xFF808080),
              _ => const Color(0xFF606060),
            },
          ),
      });
    });

    PracticeCardBackPainter painterAt(
      double ms,
      PracticeGirlRarity rarity, {
      PracticeCardMaterialImages? images,
      PracticeRevealEffectTier tier = PracticeRevealEffectTier.medium,
      double yaw = PracticeRevealTiming.waitingYaw,
    }) =>
        PracticeCardBackPainter(
          images: images ?? all,
          dye: practiceRevealDye(ms, rarity),
          light: practiceCardLight(
            yawDeg: yaw,
            pitchDeg: PracticeRevealTiming.waitingPitch,
            front: false,
          ),
          energy: practiceCardBackEnergy(ms, rarity),
          emblemWhite: practiceRevealEmblemWhite(ms),
          tier: tier,
        );

    for (final rarity in PracticeGirlRarity.values) {
      test('稀有度誠實（${rarity.label}）：每 50 ms 取樣，N 沒有藍金、R 沒有金、SR 的金不早於 R0＋850',
          () {
        final seen = <PracticeCardBackLayer>{};
        for (var ms = 0.0; ms <= PracticeRevealTiming.flipPeakMs; ms += 50) {
          final layers = painterAt(ms, rarity).layers;
          seen.addAll(layers);
          expect(
            layers.first,
            isIn(const [
              PracticeCardBackLayer.base,
              PracticeCardBackLayer.blueWipe,
              PracticeCardBackLayer.goldWipe,
            ]),
            reason: '最底層一定是一張成品圖（$ms ms）',
          );
          if (rarity == PracticeGirlRarity.n) {
            expect(layers, isNot(contains(PracticeCardBackLayer.blueWipe)));
          }
          if (rarity != PracticeGirlRarity.sr ||
              ms <= PracticeRevealTiming.dyeGoldMs) {
            expect(layers, isNot(contains(PracticeCardBackLayer.goldWipe)),
                reason: '$ms ms');
            expect(layers, isNot(contains(PracticeCardBackLayer.holo)),
                reason: '$ms ms');
          }
        }
        expect(
          seen.contains(PracticeCardBackLayer.blueWipe),
          rarity != PracticeGirlRarity.n,
        );
        expect(
          seen.contains(PracticeCardBackLayer.goldWipe),
          rarity == PracticeGirlRarity.sr,
        );
        expect(
          seen.contains(PracticeCardBackLayer.holo),
          rarity == PracticeGirlRarity.sr,
        );
        expect(seen, contains(PracticeCardBackLayer.emblemWhite));
      });
    }

    test('轉化完只畫最上面那一階的成品圖，不重複疊整張圖', () {
      const flip = PracticeRevealTiming.flipStartMs;
      expect(painterAt(flip, PracticeGirlRarity.n).layers.first,
          PracticeCardBackLayer.base);
      final r = painterAt(flip, PracticeGirlRarity.r).layers;
      expect(r.first, PracticeCardBackLayer.blueWipe);
      expect(r, isNot(contains(PracticeCardBackLayer.base)));
      final sr = painterAt(flip, PracticeGirlRarity.sr).layers;
      expect(sr.first, PracticeCardBackLayer.goldWipe);
      expect(sr, isNot(contains(PracticeCardBackLayer.blueWipe)));
      // 染金進行中：底下是染完的藍，不必再畫 N。
      final midGold = painterAt(925, PracticeGirlRarity.sr).layers;
      expect(midGold.take(2), [
        PracticeCardBackLayer.blueWipe,
        PracticeCardBackLayer.goldWipe,
      ]);
    });

    test('擴散進行中才有前緣光環；轉化完直接畫成品圖', () {
      const rarity = PracticeGirlRarity.sr;
      expect(painterAt(660, rarity).layers,
          contains(PracticeCardBackLayer.wipeRing));
      expect(painterAt(780, rarity).layers,
          isNot(contains(PracticeCardBackLayer.wipeRing)));
      expect(painterAt(925, rarity).layers,
          contains(PracticeCardBackLayer.wipeRing));
      expect(painterAt(PracticeRevealTiming.flipStartMs, rarity).layers,
          isNot(contains(PracticeCardBackLayer.wipeRing)));
    });

    test('素材還沒解好：只畫深色底（§6.8），畫得出來不丟例外', () async {
      final painter = painterAt(
        900,
        PracticeGirlRarity.sr,
        images: PracticeCardMaterialImages.none,
      );
      expect(painter.layers, [PracticeCardBackLayer.fallback]);
      final pixel = await _pixel((canvas, rect) => painter.paint(canvas, rect.size));
      expect(pixel, [0x19, 0x1A, 0x1E, 0xFF]);
    });

    test('R、SR 成品圖還沒解好：維持上一階，不跳格', () {
      final noTiers = all
          .withImage(PracticeCardMaterialSlot.r, null)
          .withImage(PracticeCardMaterialSlot.sr, null);
      final layers = painterAt(900, PracticeGirlRarity.sr, images: noTiers).layers;
      expect(layers, isNot(contains(PracticeCardBackLayer.blueWipe)));
      expect(layers, isNot(contains(PracticeCardBackLayer.goldWipe)));
      expect(layers, isNot(contains(PracticeCardBackLayer.holo)));
      final noSr = all.withImage(PracticeCardMaterialSlot.sr, null);
      expect(
        painterAt(PracticeRevealTiming.flipStartMs, PracticeGirlRarity.sr,
                images: noSr)
            .layers,
        allOf(
          contains(PracticeCardBackLayer.blueWipe),
          isNot(contains(PracticeCardBackLayer.goldWipe)),
        ),
      );
    });

    test('低檔不畫浮雕補光與 SR 全息（§6.9）', () {
      final high = painterAt(
        PracticeRevealTiming.flipStartMs,
        PracticeGirlRarity.sr,
        yaw: -20,
      ).layers;
      final low = painterAt(
        PracticeRevealTiming.flipStartMs,
        PracticeGirlRarity.sr,
        yaw: -20,
        tier: PracticeRevealEffectTier.low,
      ).layers;
      expect(high, containsAll([
        PracticeCardBackLayer.relief,
        PracticeCardBackLayer.holo,
      ]));
      expect(low, isNot(contains(PracticeCardBackLayer.relief)));
      expect(low, isNot(contains(PracticeCardBackLayer.holo)));
      expect(low, contains(PracticeCardBackLayer.specular));
    });

    test('高光帶離開卡片就不畫；等待基準姿態不畫浮雕補光', () {
      final rest = painterAt(0, PracticeGirlRarity.n).layers;
      expect(rest, contains(PracticeCardBackLayer.specular));
      expect(rest, isNot(contains(PracticeCardBackLayer.relief)));
      // 翻牌前半卡片轉到側面：高光帶已經從左上離開。
      expect(painterAt(1300, PracticeGirlRarity.n, yaw: 60).layers,
          isNot(contains(PracticeCardBackLayer.specular)));
    });

    test('狀態不變 → shouldRepaint 為 false（停住零動畫幀）；光、染色、素材一變就重畫', () {
      final a = painterAt(900, PracticeGirlRarity.sr);
      expect(a.shouldRepaint(painterAt(900, PracticeGirlRarity.sr)), isFalse);
      expect(
        a.shouldRepaint(painterAt(900, PracticeGirlRarity.sr, yaw: -11)),
        isTrue,
      );
      expect(a.shouldRepaint(painterAt(901, PracticeGirlRarity.sr)), isTrue);
      expect(
        a.shouldRepaint(
          painterAt(900, PracticeGirlRarity.sr,
              images: all.withImage(PracticeCardMaterialSlot.noise, null)),
        ),
        isTrue,
      );
    });

    test('額外發光用 screen 疊：本來就亮的金屬只微微提亮，不會跟暗處一樣加到爆白', () async {
      Future<int> lit(Color base) async {
        final painter = PracticeCardBackPainter(
          images: PracticeCardMaterialImages({
            PracticeCardMaterialSlot.n: await _solid(base),
            // R 0.5＝沒有浮雕差、B 0＝沒有高光遮罩：只看額外發光
            PracticeCardMaterialSlot.light:
                await _solid(const Color(0xFF808000)),
            PracticeCardMaterialSlot.glowMask: await _solid(Colors.white),
            PracticeCardMaterialSlot.glow: await _solid(Colors.white),
          }),
          dye: (blue: 0.0, gold: 0.0),
          light: const PracticeCardLight(band: 5, relief: 0, holoPhase: 0),
          energy: const PracticeCardBackEnergy(emblem: 1, bloom: 1),
        );
        final px =
            await _pixel((canvas, rect) => painter.paint(canvas, rect.size));
        return px[0];
      }

      final dark = await lit(const Color(0xFF202020));
      final bright = await lit(const Color(0xFFE0E0E0));
      expect(bright, lessThan(250), reason: 'plus 會直接加到 255');
      expect(bright - 0xE0, lessThan((dark - 0x20) ~/ 3));
    });

    test('浮雕補光的亮半邊染這一階金屬的亮色：SR 是淡金，不是白光', () async {
      final painter = PracticeCardBackPainter(
        images: PracticeCardMaterialImages({
          for (final slot in [
            PracticeCardMaterialSlot.n,
            PracticeCardMaterialSlot.r,
            PracticeCardMaterialSlot.sr,
          ])
            slot: await _solid(Colors.black),
          // R 1＝浮雕補光差最大（變亮的那一半）、G 0＝沒有全息、B 0＝沒有高光遮罩
          PracticeCardMaterialSlot.light: await _solid(const Color(0xFFFF0000)),
        }),
        dye: (blue: 1.0, gold: 1.0),
        light: const PracticeCardLight(band: 5, relief: 1, holoPhase: 0),
      );
      final px =
          await _pixel((canvas, rect) => painter.paint(canvas, rect.size));
      expect(px[0], greaterThan(100));
      expect(px[2], lessThan(px[0] - 20), reason: '淡金（#FDF2BA）：藍比紅少');
    });

    test('每一層都畫得出來（假素材，揭曉全程與等待）', () async {
      for (final rarity in PracticeGirlRarity.values) {
        for (var ms = 0.0; ms <= PracticeRevealTiming.flipPeakMs; ms += 100) {
          final painter = painterAt(ms, rarity, yaw: -10 - ms / 100);
          final recorder = ui.PictureRecorder();
          painter.paint(Canvas(recorder), const Size(36, 54));
          final image = await recorder.endRecording().toImage(36, 54);
          image.dispose();
        }
      }
    });
  });

  group('遮罩通道 → 透明度（附錄 §18.2）', () {
    late ui.Image mask;

    setUpAll(() async {
      mask = await _solid(const Color(0xFFC000FF), width: 4, height: 4);
    });

    Future<int> red(ColorFilter filter, [BlendMode mode = BlendMode.srcOver]) async {
      final px = await _pixel(
        (canvas, rect) => canvas.drawImageRect(
          mask,
          rect,
          rect,
          Paint()
            ..blendMode = mode
            ..colorFilter = filter,
        ),
      );
      return px[0];
    }

    test('practiceChannelAlpha 只取指定的通道', () async {
      expect(await red(practiceChannelAlpha(0, Colors.white, 1)),
          closeTo(0xC0, 2));
      expect(await red(practiceChannelAlpha(1, Colors.white, 1)), 0);
      expect(await red(practiceChannelAlpha(2, Colors.white, 1)),
          closeTo(0xFF, 1));
      expect(await red(practiceChannelAlpha(2, Colors.white, 0.5)),
          closeTo(0x80, 2));
    });

    test('浮雕補光：R 大於 0.5 的一半才有透明度，小於 0.5 的一半是 0', () async {
      // R＝0xC0（0.753）：upper α＝2×0.753−1≈0.506；lower α 夾成 0。
      expect(
        await red(
          practiceReliefHalf(upper: true, color: Colors.white, strength: 1),
          BlendMode.plus,
        ),
        closeTo(129, 3),
      );
      expect(
        await red(
          practiceReliefHalf(upper: false, color: Colors.white, strength: 1),
          BlendMode.plus,
        ),
        0,
      );
    });
  });
}
