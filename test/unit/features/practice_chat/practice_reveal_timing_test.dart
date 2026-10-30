import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_girl_rarity.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_reveal_timing.dart';

/// V3 揭曉時間軸（規格 §4）與 V3.1 第一刀的光效曲線（V3.1 規格 §5）：純函式，免 widget
/// harness。
void main() {
  const n = PracticeGirlRarity.n;
  const r = PracticeGirlRarity.r;
  const sr = PracticeGirlRarity.sr;

  group('時間軸常數', () {
    test('揭曉 2.7 s、收卡 0.7 s（V3.1 §4）、入場 0.5 s', () {
      expect(PracticeRevealTiming.reveal, const Duration(milliseconds: 2700));
      expect(PracticeRevealTiming.archive, const Duration(milliseconds: 700));
      expect(PracticeRevealTiming.intro, const Duration(milliseconds: 500));
    });

    test('揭曉節點嚴格依序：蓄力 → 翻牌 → 落定 → 資訊 → 提示 → 結束', () {
      const beats = [
        PracticeRevealTiming.chargeEndMs,
        PracticeRevealTiming.flipStartMs,
        PracticeRevealTiming.srBuildMs,
        PracticeRevealTiming.flipPeakMs,
        PracticeRevealTiming.flipEndMs,
        PracticeRevealTiming.infoStartMs,
        PracticeRevealTiming.infoEndMs,
        PracticeRevealTiming.hintStartMs,
      ];
      for (var i = 1; i < beats.length; i++) {
        expect(beats[i], greaterThan(beats[i - 1]), reason: 'beat[$i]');
      }
      expect(beats.last, lessThan(PracticeRevealTiming.revealMs));
      // SR celebrate 三下共 200 ms：第三下要正好落在翻牌峰值。
      expect(
        PracticeRevealTiming.srBuildMs + 200,
        PracticeRevealTiming.flipPeakMs,
      );
      // 翻牌落定前不能跳過。
      expect(PracticeRevealTiming.skipFromMs, PracticeRevealTiming.flipEndMs);
    });

    test('收卡節點依序：細線 → 光球 → 起飛 → 落位（仍在 450）→ 落位光 → 收掉', () {
      expect(
        PracticeRevealTiming.archiveLineEndMs,
        lessThan(PracticeRevealTiming.collapseEndMs),
      );
      expect(
        PracticeRevealTiming.collapseEndMs,
        PracticeRevealTiming.flightStartMs,
      );
      expect(PracticeRevealTiming.landMs, 450);
      expect(
        PracticeRevealTiming.landMs + PracticeRevealTiming.landBurstMs,
        lessThanOrEqualTo(PracticeRevealTiming.archiveMs),
      );
      expect(
        PracticeRevealTiming.landRing1EndMs,
        lessThanOrEqualTo(PracticeRevealTiming.archiveMs),
      );
      expect(
        PracticeRevealTiming.landMs,
        greaterThan(PracticeRevealTiming.flightStartMs),
      );
      expect(
        PracticeRevealTiming.archiveMs,
        greaterThan(PracticeRevealTiming.landMs),
      );
      expect(
        PracticeRevealTiming.backdropOutEndMs,
        lessThanOrEqualTo(PracticeRevealTiming.archiveMs),
      );
    });
  });

  group('卡片姿態', () {
    test('起點靜止、蓄力縮到 0.90 並後仰 9°、偏 −15°（V3.1 §5.9）', () {
      final start = practiceRevealPose(0);
      expect(start.yaw, closeTo(0, 1e-9));
      expect(start.pitch, closeTo(0, 1e-9));
      expect(start.scale, closeTo(1, 1e-9));

      for (final ms in [600.0, 900.0, 1100.0]) {
        final pose = practiceRevealPose(ms);
        expect(pose.yaw, closeTo(-15, 1e-9), reason: '$ms');
        expect(pose.pitch, closeTo(9, 1e-9), reason: '$ms');
        expect(pose.scale, closeTo(0.90, 1e-9), reason: '$ms');
      }
    });

    test('翻牌前半先往回拉再衝（easeInBack 預備動作）', () {
      final anticipation = [
        for (var ms = 1110.0; ms < 1250; ms += 10) practiceRevealPose(ms).yaw,
      ].reduce((a, b) => a < b ? a : b);
      expect(anticipation, lessThan(-20));
      expect(anticipation, greaterThan(-30));
    });

    test('峰值正好側立 90°，兩側連續', () {
      // Cubic.transform 以二分逼近（誤差界 0.001），端點附近最多差零點幾度；
      // 那一刻卡片側立看不見，肉眼無感。
      expect(practiceRevealPose(1349.999).yaw, closeTo(90, 0.5));
      expect(practiceRevealPose(1350).yaw, closeTo(90, 1e-9));
      expect(practiceRevealPose(1350.001).yaw, closeTo(90, 0.5));
    });

    test('翻牌後半單調轉到 180°，縮放與後仰歸位', () {
      var last = practiceRevealPose(1350).yaw;
      for (var ms = 1360.0; ms <= 1800; ms += 10) {
        final yaw = practiceRevealPose(ms).yaw;
        expect(yaw, greaterThanOrEqualTo(last), reason: '$ms');
        last = yaw;
      }
      final settled = practiceRevealPose(1800);
      expect(settled.yaw, closeTo(180, 1e-9));
      expect(settled.pitch, closeTo(0, 1e-9));
      expect(settled.scale, closeTo(1, 1e-9));
      final end = practiceRevealPose(PracticeRevealTiming.revealMs);
      expect(end.yaw, closeTo(180, 1e-9));
    });

    test('全程只翻一次：正面一出現，卡背不再回來', () {
      var flips = 0;
      var front = practiceRevealShowsFront(0);
      expect(front, isFalse);
      for (var ms = 0.0; ms <= PracticeRevealTiming.revealMs; ms += 5) {
        final now = practiceRevealShowsFront(ms);
        if (now != front) {
          flips++;
          expect(now, isTrue, reason: '只能從卡背翻到正面（$ms ms）');
        }
        front = now;
      }
      expect(flips, 1);
      expect(practiceRevealShowsFront(1350), isFalse);
      expect(practiceRevealShowsFront(1360), isTrue);
    });
  });

  group('揭曉各層進度', () {
    test('照片翻開時 1.08，1.5 s 起緩縮到 1.00', () {
      expect(practiceRevealPhotoScale(1350), closeTo(1.08, 1e-9));
      expect(practiceRevealPhotoScale(1500), closeTo(1.08, 1e-9));
      expect(
        practiceRevealPhotoScale(PracticeRevealTiming.revealMs),
        closeTo(1, 1e-9),
      );
      var last = practiceRevealPhotoScale(1500);
      for (var ms = 1510.0; ms <= PracticeRevealTiming.revealMs; ms += 10) {
        final s = practiceRevealPhotoScale(ms);
        expect(s, lessThanOrEqualTo(last), reason: '$ms');
        last = s;
      }
    });

    test('資訊欄 1.85 s 才浮出、2.15 s 到位', () {
      expect(practiceRevealInfoAppear(1849), 0);
      expect(practiceRevealInfoAppear(2000), inExclusiveRange(0, 1));
      expect(practiceRevealInfoAppear(2150), 1);
    });

    test('點擊提示 2.4 s 起淡入、揭曉結束時全亮', () {
      expect(practiceRevealHintIn(2399), 0);
      expect(practiceRevealHintIn(PracticeRevealTiming.revealMs), 1);
    });

    test('蓄力亮度 0 → 1，蓄力結束後維持', () {
      expect(practiceRevealChargeGlow(0), 0);
      expect(practiceRevealChargeGlow(600), 1);
      expect(practiceRevealChargeGlow(2000), 1);
    });
  });

  group('drawing 進場', () {
    test('背景 0.3 s 內暗下、卡背 0.1–0.5 s 入場、0.3 s 內淡入', () {
      expect(practiceIntroBackdrop(0), 0);
      expect(practiceIntroBackdrop(300), 1);
      expect(practiceIntroCard(100), 0);
      expect(practiceIntroCard(500), 1);
      expect(practiceIntroCardOpacity(100), 0);
      expect(practiceIntroCardOpacity(300), 1);
    });

    test('等待字樣只有等超過 0.9 s 才淡入', () {
      expect(practiceCaptionIn(899), 0);
      expect(practiceCaptionIn(1200), 1);
    });
  });

  group('收卡', () {
    test('卡片 0.12 s 內轉成細線（0.7 倍），0.15 s 縮到 0.15 並淡出（V3.1 §5.12）', () {
      expect(practiceArchiveCardScale(0), 1);
      expect(practiceArchiveCardScale(120), closeTo(0.7, 1e-9));
      expect(practiceArchiveCardScale(150), closeTo(0.15, 1e-9));
      var last = 2.0;
      for (var ms = 0.0; ms <= 150; ms += 2) {
        final scale = practiceArchiveCardScale(ms);
        expect(scale, lessThanOrEqualTo(last), reason: '$ms');
        last = scale;
      }
      expect(practiceArchiveCardOpacity(119), 1);
      expect(practiceArchiveCardOpacity(150), 0);
    });

    test('細線階段卡片單調轉向側面：0 → 80°（加在正面的 180° 上），之後停在 80°', () {
      expect(practiceArchiveCardYaw(0), 0);
      var last = -1.0;
      for (var ms = 0.0; ms <= 120; ms += 2) {
        final yaw = practiceArchiveCardYaw(ms);
        expect(yaw, greaterThanOrEqualTo(last), reason: '$ms');
        last = yaw;
      }
      expect(practiceArchiveCardYaw(120), closeTo(80, 1e-9));
      expect(practiceArchiveCardYaw(450), closeTo(80, 1e-9));
    });

    test('背景 0.15–0.5 s 退場、光球 0.15–0.45 s 飛行', () {
      expect(practiceArchiveBackdrop(150), 1);
      expect(practiceArchiveBackdrop(500), 0);
      expect(practiceArchiveFlightT(150), 0);
      expect(practiceArchiveFlightT(450), 1);
    });

    test('三次貝茲弧線的控制點：第一個在卡片左下外側、第二個在目標格外側，都夾在畫面內縮 24 px 內', () {
      const stage = Size(390, 844);
      const card = Size(300, 450);
      const origin = Offset(195, 380);
      for (final target in [
        Rect.fromCenter(
            center: const Offset(100, 700), width: 110, height: 150),
        Rect.fromCenter(
            center: const Offset(300, 700), width: 110, height: 150),
        Rect.fromCenter(center: const Offset(20, 20), width: 110, height: 150),
        Rect.fromCenter(
            center: const Offset(370, 820), width: 110, height: 150),
      ]) {
        final c = practiceArchiveControls(origin, target, card, stage);
        for (final p in [c.c1, c.c2]) {
          expect(p.dx, inInclusiveRange(24, stage.width - 24), reason: '$p');
          expect(p.dy, inInclusiveRange(24, stage.height - 24), reason: '$p');
        }
      }
      final target = Rect.fromCenter(
          center: const Offset(300, 700), width: 110, height: 150);
      final c = practiceArchiveControls(origin, target, card, stage);
      // 第一個控制點在卡片中心的左下方：光球先往左下甩出去。
      expect(c.c1.dx, lessThan(origin.dx));
      expect(c.c1.dy, greaterThan(origin.dy));
      // 目標在右半邊：第二個控制點在它右上外側，光球繞半圈從外側進那一格。
      expect(c.c2.dx, greaterThan(target.right));
      expect(c.c2.dy, lessThan(target.top));
    });

    test('三次貝茲曲線兩端落在起點與終點', () {
      const p0 = Offset(10, 20);
      const p1 = Offset(200, 50);
      const p2 = Offset(250, 300);
      const p3 = Offset(300, 400);
      expect(practiceCubicBezier(p0, p1, p2, p3, 0), p0);
      expect(practiceCubicBezier(p0, p1, p2, p3, 1), p3);
    });
  });

  group('卡背染色（只升到真實稀有度）', () {
    test('N 全程銀、R 不會出現金、SR 先藍再金；全程只升不退', () {
      var lastBlue = 0.0;
      var lastGold = 0.0;
      for (var ms = 0.0; ms <= PracticeRevealTiming.revealMs; ms += 10) {
        expect(practiceRevealDye(ms, n), (blue: 0.0, gold: 0.0), reason: '$ms');
        expect(practiceRevealDye(ms, r).gold, 0, reason: '$ms');
        final dye = practiceRevealDye(ms, sr);
        expect(dye.blue, greaterThanOrEqualTo(lastBlue), reason: '$ms');
        expect(dye.gold, greaterThanOrEqualTo(lastGold), reason: '$ms');
        lastBlue = dye.blue;
        lastGold = dye.gold;
      }
      expect(practiceRevealDye(599, r).blue, 0);
      expect(practiceRevealDye(720, r).blue, 1);
      expect(practiceRevealDye(849, sr).gold, 0);
      expect(practiceRevealDye(1000, sr), (blue: 1.0, gold: 1.0));
    });

    test('徽記亮度：蓄力 0.35 → 0.80；N 脈衝到 1.0 再退到 0.85；R／SR 衝到 1.0', () {
      for (final rarity in PracticeGirlRarity.values) {
        expect(practiceRevealEmblemGlow(0, rarity), closeTo(0.35, 1e-9));
        expect(practiceRevealEmblemGlow(600, rarity), closeTo(0.80, 1e-9));
        // 染色段起點連續。
        expect(
          practiceRevealEmblemGlow(599.9, rarity),
          closeTo(practiceRevealEmblemGlow(600, rarity), 1e-3),
        );
      }
      expect(practiceRevealEmblemGlow(700, n), closeTo(1.0, 1e-9));
      expect(practiceRevealEmblemGlow(800, n), closeTo(0.85, 1e-9));
      expect(practiceRevealEmblemGlow(1200, n), closeTo(0.85, 1e-9));
      for (final rarity in [r, sr]) {
        expect(practiceRevealEmblemGlow(720, rarity), closeTo(1.0, 1e-9));
        expect(practiceRevealEmblemGlow(1200, rarity), closeTo(1.0, 1e-9));
      }
    });

    test('環境光 1.00 → 藍 1.15 → 金 1.35', () {
      expect(practiceRevealAmbientScale(2000, n), 1);
      expect(practiceRevealAmbientScale(2000, r), closeTo(1.15, 1e-9));
      expect(practiceRevealAmbientScale(2000, sr), closeTo(1.35, 1e-9));
    });
  });

  group('翻牌峰值：光刃與十字（V3.1 §5.5）', () {
    test('光刃 N／R 280 ms、SR 350 ms：20 ms 張到最寬，後段快收', () {
      expect(PracticeRevealTiming.bladeOpenMs, 20);
      for (final rarity in PracticeGirlRarity.values) {
        final total = practiceRevealBladeMs(rarity);
        expect(practiceRevealBladeWidth(1300, rarity), 0);
        expect(practiceRevealBladeWidth(1350, rarity), 0);
        expect(practiceRevealBladeWidth(1360, rarity), greaterThan(0.5));
        expect(practiceRevealBladeWidth(1370, rarity), closeTo(1, 1e-9));
        expect(practiceRevealBladeWidth(1350 + total, rarity), 0);
        // 先快後慢：收的那段走到一半時外暈已經只剩不到 20%，照片很快露出來。
        final half = 1370 + (total - 20) / 2;
        expect(practiceRevealBladeWidth(half, rarity), lessThan(0.2));
        expect(practiceRevealBladeCore(1349, rarity), 0);
        expect(practiceRevealBladeCore(1350, rarity), closeTo(3, 1e-9));
        expect(practiceRevealBladeCore(1349 + total, rarity), closeTo(1, 0.02));
        expect(practiceRevealBladeCore(1350 + total, rarity), 0);
        expect(practiceRevealBladeCoreAlpha(1400, rarity), 1);
        expect(
          practiceRevealBladeCoreAlpha(1350 + total - 25, rarity),
          closeTo(0.5, 1e-9),
        );
      }
      expect(practiceRevealBladeMs(n), 280);
      expect(practiceRevealBladeMs(r), 280);
      expect(practiceRevealBladeMs(sr), 350);
    });

    test('十字只有 SR、400 ms 鐘形', () {
      for (var ms = 1300.0; ms <= 1800; ms += 5) {
        expect(practiceRevealCross(ms, n), 0);
        expect(practiceRevealCross(ms, r), 0);
      }
      expect(practiceRevealCross(1550, sr), closeTo(1, 1e-9));
      expect(practiceRevealCross(1750, sr), 0);
    });
  });

  group('卡面：掃光、六角牌、星星', () {
    test('全息掃光 1.7–2.4 s 從卡片左外側掃到右外側', () {
      expect(practiceRevealSheenX(1700), isNull);
      expect(practiceRevealSheenX(2400), isNull);
      var last = -2.0;
      for (var ms = 1710.0; ms < 2400; ms += 10) {
        final x = practiceRevealSheenX(ms)!;
        expect(x, greaterThan(last), reason: '$ms');
        expect(x, inInclusiveRange(-1.2, 1.2));
        last = x;
      }
    });

    test(
        '六角牌 1.94 s 前不存在；120 ms 從畫面外飛到落點（easeIn、1.4 → 1.0），再 160 ms 回彈（V3.1 §5.10）',
        () {
      expect(practiceRevealStamped(1939), isFalse);
      expect(practiceRevealStamped(1940), isTrue);
      expect(practiceRevealStampFlight(1940), 0);
      expect(practiceRevealStampFlight(2000), lessThan(0.5)); // 越飛越快＝砸下去
      expect(practiceRevealStampFlight(2060), 1);
      expect(practiceRevealStampFlight(2700), 1);
      expect(practiceRevealStampScale(1940), closeTo(1.4, 1e-9));
      expect(practiceRevealStampScale(2060), closeTo(1.0, 1e-9));
      var min = 2.0;
      for (var ms = 2060.0; ms <= 2220; ms += 2) {
        min = math.min(min, practiceRevealStampScale(ms));
      }
      expect(min, lessThan(1.0));
      expect(min, greaterThanOrEqualTo(0.95 - 1e-9));
      expect(practiceRevealStampScale(2220), closeTo(1.0, 1e-9));
      expect(practiceRevealStampScale(2700), closeTo(1.0, 1e-9));
      // 牌落地到第一顆星隔 90 ms，兩下觸覺分得開。
      expect(
        PracticeRevealTiming.starsStartMs - PracticeRevealTiming.stampLandMs,
        90,
      );
    });

    test('星星 2.15 s 起每 80 ms 一顆：0 → 1.35 → 1.00，停住前全部到位（V3.1 §5.11）', () {
      for (var i = 0; i < 4; i++) {
        final start = PracticeRevealTiming.starsStartMs + 80 * i;
        expect(practiceRevealStarStartMs(i), start);
        expect(practiceRevealStarScale(start, i), 0);
        expect(
          practiceRevealStarScale(
              start + 0.6 * PracticeRevealTiming.starPopMs, i),
          closeTo(1.35, 1e-9),
        );
        expect(
            practiceRevealStarScale(start + PracticeRevealTiming.starPopMs, i),
            1);
        expect(practiceRevealStarScale(PracticeRevealTiming.revealMs, i), 1);
        expect(practiceRevealStarPulse(PracticeRevealTiming.revealMs, i), 0);
      }
    });

    test('星星點亮時的四芒星光 250 ms（α 0.9 → 0、轉 30°）、小光點 300 ms，停住前都結束', () {
      for (var i = 0; i < 4; i++) {
        final start = practiceRevealStarStartMs(i);
        expect(practiceRevealStarSparkle(start, i), isNull);
        final early = practiceRevealStarSparkle(start + 1, i)!;
        expect(early.alpha, closeTo(0.9, 0.01));
        final late = practiceRevealStarSparkle(start + 249, i)!;
        expect(late.turnDeg, closeTo(30, 0.2));
        expect(late.alpha, lessThan(0.05));
        expect(practiceRevealStarSparkle(start + 250, i), isNull);
        for (var dot = 0; dot < PracticeRevealTiming.starDotCount; dot++) {
          expect(practiceRevealStarDot(start, i, dot), isNull);
          expect(practiceRevealStarDot(start + 150, i, dot), isNotNull);
          expect(practiceRevealStarDot(start + 300, i, dot), isNull);
          expect(
            practiceRevealStarDot(start + 299, i, dot)!.offset.distance,
            lessThanOrEqualTo(14),
          );
        }
        expect(start + 300, lessThan(PracticeRevealTiming.revealMs));
      }
    });

    test('NEW 小標在牌落地之後浮現（§4 時間軸 2150–2300），停住前到位（V3.1 §5.14）', () {
      expect(
        PracticeRevealTiming.newTagStartMs,
        greaterThan(PracticeRevealTiming.stampLandMs),
      );
      expect(practiceRevealNewTagAppear(PracticeRevealTiming.newTagStartMs), 0);
      expect(practiceRevealNewTagAppear(PracticeRevealTiming.newTagEndMs), 1);
      expect(
        PracticeRevealTiming.newTagEndMs,
        lessThan(PracticeRevealTiming.revealMs),
      );
    });

    test('第一句話：資訊欄到位才開始，100 ms 淡入、等速打字、停住前打完（V3.1 §5.13）', () {
      expect(
        PracticeRevealTiming.introLineStartMs,
        PracticeRevealTiming.infoEndMs,
      );
      expect(
        PracticeRevealTiming.introLineEndMs,
        lessThan(PracticeRevealTiming.revealMs),
      );
      const start = PracticeRevealTiming.introLineStartMs;
      expect(practiceRevealIntroLineOpacity(start), 0);
      expect(practiceRevealIntroLineOpacity(start + 100), 1);
      expect(practiceRevealIntroLineTyped(start), 0);
      expect(practiceRevealIntroLineTyped(start + 250), closeTo(0.5, 1e-9));
      expect(
        practiceRevealIntroLineTyped(PracticeRevealTiming.introLineEndMs),
        1,
      );
      var last = -1.0;
      for (var ms = start; ms <= PracticeRevealTiming.revealMs; ms += 10) {
        final typed = practiceRevealIntroLineTyped(ms);
        expect(typed, greaterThanOrEqualTo(last), reason: '$ms');
        last = typed;
      }
    });
  });

  group('收卡：變成光、光球、星點', () {
    test('資訊 80 ms 內淡掉、卡面 120 ms 內變成光（細線發光）', () {
      expect(practiceArchiveInfoOpacity(0), 1);
      expect(practiceArchiveInfoOpacity(80), 0);
      expect(practiceArchiveCardLight(0), 0);
      expect(practiceArchiveCardLight(120), 1);
    });

    test('光球 120 ms 起在卡片中心從 14 長到 18，飛行中縮到 10', () {
      expect(practiceArchiveOrbRadius(119), 0);
      expect(practiceArchiveOrbRadius(120), closeTo(14, 1e-9));
      expect(practiceArchiveOrbRadius(150), closeTo(18, 1e-9));
      expect(practiceArchiveOrbRadius(450), closeTo(10, 1e-9));
    });

    test('14 顆星點在光球經過 t＝i/15 時灑出（V3.1 §5.12）', () {
      expect(PracticeRevealTiming.sparkleCount, 14);
      var last = PracticeRevealTiming.flightStartMs;
      for (var i = 1; i <= PracticeRevealTiming.sparkleCount; i++) {
        final ms = practiceArchiveSparkleSpawnMs(i);
        expect(ms, greaterThan(last), reason: 'sparkle $i');
        expect(ms, lessThan(PracticeRevealTiming.landMs));
        // Flutter 的 Cubic 求值本身在 x 上只到 ±0.001，曲線中段斜率約 3。
        expect(practiceArchiveFlightT(ms), closeTo(i / 15, 5e-3));
        last = ms;
      }
    });

    test('星點灑出時間表先算好，和逐顆反解的結果一致', () {
      expect(kPracticeArchiveSparkleSpawnMs,
          hasLength(PracticeRevealTiming.sparkleCount));
      for (var i = 1; i <= PracticeRevealTiming.sparkleCount; i++) {
        expect(kPracticeArchiveSparkleSpawnMs[i - 1],
            practiceArchiveSparkleSpawnMs(i));
      }
    });

    test('三次貝茲切線：起點朝第一個控制點、終點從第二個控制點出來', () {
      const p0 = Offset(0, 0);
      const p1 = Offset(100, 0);
      const p2 = Offset(100, 100);
      const p3 = Offset(200, 100);
      expect(
        practiceCubicBezierTangent(p0, p1, p2, p3, 0),
        const Offset(300, 0),
      );
      expect(
        practiceCubicBezierTangent(p0, p1, p2, p3, 1),
        const Offset(300, 0),
      );
    });

    test('落位：大四芒星爆光 450 ms 起 250 ms、兩圈光環 450–650／500–700，收卡結束前都收完', () {
      expect(practiceArchiveLandBurst(450), isNull);
      final peak = practiceArchiveLandBurst(450 + 0.25 * 250)!;
      expect(peak.alpha, closeTo(1, 1e-9));
      expect(practiceArchiveLandBurst(449 + 250)!.scale, closeTo(1, 0.01));
      expect(practiceArchiveLandBurst(700), isNull);
      expect(practiceArchiveLandRing(450, 0), isNull);
      expect(practiceArchiveLandRing(550, 0), closeTo(0.5, 1e-9));
      expect(practiceArchiveLandRing(650, 0), isNull);
      expect(practiceArchiveLandRing(499, 1), isNull);
      expect(practiceArchiveLandRing(600, 1), closeTo(0.5, 1e-9));
      expect(practiceArchiveLandRing(700, 1), isNull);
    });
  });

  group('泛光（V3.1 §5.1）', () {
    test(
        '後層：蓄力 0 → 0.3；R／SR 染藍衝到 0.75；SR 染金 0.9；翻牌峰值 N 0.35／R 0.6／SR 0.9；400 ms 後退回 0.3 並停住',
        () {
      for (final rarity in PracticeGirlRarity.values) {
        expect(practiceRevealBloomBack(0, rarity), 0);
        expect(practiceRevealBloomBack(600, rarity), closeTo(0.3, 1e-9));
        expect(
          practiceRevealBloomBack(599.9, rarity),
          closeTo(practiceRevealBloomBack(600, rarity), 1e-3),
        );
        expect(practiceRevealBloomBack(1750, rarity), closeTo(0.3, 1e-9));
        // 停住時靜止：1.75 s 之後一直是 0.3。
        for (var ms = 1750.0; ms <= PracticeRevealTiming.revealMs; ms += 50) {
          expect(
            practiceRevealBloomBack(ms, rarity),
            closeTo(0.3, 1e-9),
            reason: '$ms',
          );
        }
      }
      expect(practiceRevealBloomBack(720, r), closeTo(0.75, 1e-9));
      expect(practiceRevealBloomBack(720, sr), closeTo(0.75, 1e-9));
      expect(practiceRevealBloomBack(1000, sr), closeTo(0.9, 1e-9));
      expect(practiceRevealBloomBack(1100, r), closeTo(0.45, 1e-9));
      expect(practiceRevealBloomBack(1100, sr), closeTo(0.5, 1e-9));
      expect(practiceRevealBloomBack(1350, n), closeTo(0.35, 1e-9));
      expect(practiceRevealBloomBack(1350, r), closeTo(0.6, 1e-9));
      expect(practiceRevealBloomBack(1350, sr), closeTo(0.9, 1e-9));
    });

    test('前層：側立前 50 ms 才起亮（只升）、側立最亮（N 0.15／R 0.25／SR 0.35），之後 300 ms 退掉（只降）',
        () {
      const start = PracticeRevealTiming.flipPeakMs -
          PracticeRevealTiming.bloomFrontLeadMs;
      const end = PracticeRevealTiming.flipPeakMs +
          PracticeRevealTiming.bloomFrontFadeMs;
      expect(start, 1300);
      expect(end, 1650);
      for (final rarity in PracticeGirlRarity.values) {
        var last = 0.0;
        for (var ms = 0.0; ms <= PracticeRevealTiming.revealMs; ms += 1) {
          final v = practiceRevealBloomFront(ms, rarity);
          expect(v, lessThanOrEqualTo(0.35), reason: '$ms');
          if (ms <= start || ms >= end) expect(v, 0, reason: '$ms');
          if (ms > start && ms <= PracticeRevealTiming.flipPeakMs) {
            expect(v, greaterThanOrEqualTo(last), reason: '側立前只升（$ms）');
          } else if (ms > PracticeRevealTiming.flipPeakMs) {
            expect(v, lessThanOrEqualTo(last), reason: '側立後只降（$ms）');
          }
          last = v;
        }
      }
      expect(practiceRevealBloomFront(1350, n), closeTo(0.15, 1e-9));
      expect(practiceRevealBloomFront(1350, r), closeTo(0.25, 1e-9));
      expect(practiceRevealBloomFront(1350, sr), closeTo(0.35, 1e-9));
    });
  });

  group('徽記白光與整張卡染色（V3.1 §5.2、§5.3）', () {
    test('徽記白光 560 → 600 衝到 0.95、720 退掉；三種稀有度共用同一條（不洩漏稀有度）', () {
      expect(practiceRevealEmblemWhite(560), 0);
      expect(practiceRevealEmblemWhite(600), closeTo(0.95, 1e-9));
      expect(practiceRevealEmblemWhite(720), 0);
      for (var ms = 0.0; ms <= PracticeRevealTiming.revealMs; ms += 5) {
        final v = practiceRevealEmblemWhite(ms);
        expect(v, inInclusiveRange(0, 0.95), reason: '$ms');
        if (ms <= 560 || ms >= 720) expect(v, 0, reason: '$ms');
      }
    });

    test('閃光安全（曲線）：翻牌前卡背只有徽記白光一下；側立前 50 ms 之前卡面前面不疊光；翻牌的光各亮一次', () {
      // 閃光次數要量畫面（tools/practice-reveal-flash-check，V3.1 §3、§12.2）：光刃、
      // 泛光、衝擊波疊上去之後只看曲線數不出來。這裡守住量測結果靠的三件事：
      // 1. 翻牌前卡背的白光只有徽記白光一下（V3 SR 染金那一下白色爆閃已拿掉，不然 SR
      //    是白光、金、翻牌三下）。
      // 2. 卡片側立前 [PracticeRevealTiming.bloomFrontLeadMs] 之前，卡面前面不疊任何光：
      //    前層泛光提早亮會先把卡面提亮，側立一暗、光刃再一亮，就多一次閃光。
      // 3. 前層泛光、光刃、十字光各自只亮一次（先升後降，不重複閃）。
      int peaks(double Function(double ms) light, double from) {
        var count = 0;
        var prev = light(from);
        var rising = false;
        for (var ms = from + 1; ms <= PracticeRevealTiming.revealMs; ms += 1) {
          final v = light(ms);
          if (v < prev - 1e-12 && rising) count++;
          if (v > prev + 1e-12) rising = true;
          if (v < prev - 1e-12) rising = false;
          prev = v;
        }
        return count;
      }

      const lead = PracticeRevealTiming.flipPeakMs -
          PracticeRevealTiming.bloomFrontLeadMs;
      expect(
        peaks((ms) => ms < lead ? practiceRevealEmblemWhite(ms) : 0, 0),
        1,
      );
      for (final rarity in PracticeGirlRarity.values) {
        for (var ms = 0.0; ms <= lead; ms += 1) {
          expect(practiceRevealBloomFront(ms, rarity), 0, reason: '$ms');
          expect(practiceRevealBladeWidth(ms, rarity), 0, reason: '$ms');
          expect(practiceRevealBladeCore(ms, rarity), 0, reason: '$ms');
          expect(practiceRevealCross(ms, rarity), 0, reason: '$ms');
          expect(practiceRevealShockwaves(ms, rarity, 450), isEmpty);
        }
        for (final light in <double Function(double)>[
          (ms) => practiceRevealBloomFront(ms, rarity),
          (ms) => practiceRevealBladeWidth(ms, rarity),
          (ms) => practiceRevealCross(ms, rarity),
        ]) {
          expect(peaks(light, lead), lessThanOrEqualTo(1), reason: '$rarity');
        }
      }
    });
  });

  group('衝擊波光環（V3.1 §5.6）', () {
    const cardHeight = 450.0;

    test('N 沒有；R 翻牌峰值 1 圈 400 ms 到 1.1×卡高；SR 2 圈（隔 120 ms、各 500 ms）到 1.3×卡高',
        () {
      for (var ms = 0.0; ms <= PracticeRevealTiming.revealMs; ms += 5) {
        expect(practiceRevealShockwaves(ms, n, cardHeight), isEmpty);
        expect(practiceRevealBadgeRing(ms, n), isNull);
        expect(practiceRevealBadgeRing(ms, r), isNull);
      }
      expect(practiceRevealShockwaves(1350, r, cardHeight), isEmpty);
      expect(practiceRevealShockwaves(1500, r, cardHeight), hasLength(1));
      expect(practiceRevealShockwaves(1750, r, cardHeight), isEmpty);
      expect(practiceRevealShockwaves(1400, sr, cardHeight), hasLength(1));
      expect(practiceRevealShockwaves(1500, sr, cardHeight), hasLength(2));
      expect(practiceRevealShockwaves(1850, sr, cardHeight), hasLength(1));
      expect(practiceRevealShockwaves(1970, sr, cardHeight), isEmpty);
    });

    test('半徑單調變大、線寬 12 → 1、α 0.85 → 0；停住前全部結束', () {
      for (final (rarity, total, end) in [
        (r, 400.0, 1.1 * cardHeight),
        (sr, 500.0, 1.3 * cardHeight),
      ]) {
        var lastRadius = 0.0;
        var lastWidth = 13.0;
        var lastAlpha = 1.0;
        for (var t = 1.0; t < total; t += 5) {
          final ring =
              practiceRevealShockwaves(1350 + t, rarity, cardHeight).first;
          expect(ring.radius, greaterThan(lastRadius), reason: '$t');
          expect(ring.radius, lessThanOrEqualTo(end));
          expect(ring.width, lessThan(lastWidth));
          expect(ring.alpha, lessThan(lastAlpha));
          lastRadius = ring.radius;
          lastWidth = ring.width;
          lastAlpha = ring.alpha;
        }
        expect(lastRadius, closeTo(end, 1));
        expect(lastWidth, closeTo(1, 0.2));
        expect(lastAlpha, lessThan(0.02));
      }
      for (var ms = 2000.0; ms <= PracticeRevealTiming.revealMs; ms += 5) {
        expect(practiceRevealShockwaves(ms, sr, cardHeight), isEmpty);
      }
    });

    test('SR 牌落地的小光環：落地起 300 ms、半徑 20 → 60 px', () {
      expect(practiceRevealBadgeRing(2060, sr), isNull);
      expect(practiceRevealBadgeRing(2061, sr)!.radius, closeTo(20, 1));
      expect(practiceRevealBadgeRing(2359, sr)!.radius, closeTo(60, 0.5));
      expect(practiceRevealBadgeRing(2360, sr), isNull);
    });
  });

  group('等待心跳（V3.1 §5.15）', () {
    test('卡背入場走完（500）起每 900 ms 一組，兩下相隔 140 ms，最多 6 組', () {
      expect(kPracticeHeartbeatBeats, 12);
      expect(practiceHeartbeatBeatMs(0), 500);
      expect(practiceHeartbeatBeatMs(1), 640);
      expect(practiceHeartbeatBeatMs(2), 1400);
      expect(practiceHeartbeatBeatMs(3), 1540);
      expect(practiceHeartbeatBeatMs(11), 500 + 900 * 5 + 140);
      // 一圈等待呼吸（2.7 s）正好三組。
      expect(
        practiceHeartbeatBeatMs(6) - practiceHeartbeatBeatMs(0),
        2700,
      );
    });

    test('畫面：第一下放大 1.2%、第二下 0.8%（60 ms 衝上、90 ms 回落），顫動 ±0.8 px，徽記加亮', () {
      expect(practiceHeartbeatPulse(0), (scale: 1.0, dx: 0.0, emblem: 0.0));
      expect(practiceHeartbeatPulse(499), (scale: 1.0, dx: 0.0, emblem: 0.0));
      expect(practiceHeartbeatPulse(560).scale, closeTo(1.012, 1e-9));
      expect(practiceHeartbeatPulse(560).emblem, closeTo(0.12, 1e-9));
      expect(practiceHeartbeatPulse(700).scale, closeTo(1.008, 1e-9));
      // 第二下在第一下快落回時接上（640）；兩組之間完全靜止。
      expect(practiceHeartbeatPulse(1000), (scale: 1.0, dx: 0.0, emblem: 0.0));
      for (var ms = 0.0; ms <= 6000; ms += 1) {
        final pulse = practiceHeartbeatPulse(ms);
        expect(pulse.dx.abs(), lessThanOrEqualTo(0.8), reason: '$ms');
        expect(pulse.scale, inInclusiveRange(1, 1.012 + 1e-9), reason: '$ms');
        expect(pulse.emblem, inInclusiveRange(0, 0.12 + 1e-9), reason: '$ms');
      }
      // 第 6 組之後全部歸零，不一直跳。
      final afterLast = practiceHeartbeatBeatMs(11) + 150;
      expect(
        practiceHeartbeatPulse(afterLast),
        (scale: 1.0, dx: 0.0, emblem: 0.0),
      );
      expect(practiceHeartbeatPulse(9000), (scale: 1.0, dx: 0.0, emblem: 0.0));
    });
  });
}
