import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_girl_rarity.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_reveal_timing.dart';

/// V3 揭曉時間軸（規格 §4）：純函式，免 widget harness。
void main() {
  group('時間軸常數', () {
    test('揭曉 2.7 s、收卡 0.55 s、入場 0.5 s', () {
      expect(PracticeRevealTiming.reveal, const Duration(milliseconds: 2700));
      expect(PracticeRevealTiming.archive, const Duration(milliseconds: 550));
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

    test('收卡節點依序：坍縮 → 起飛 → 落位 → 收掉', () {
      expect(
        PracticeRevealTiming.collapseEndMs,
        PracticeRevealTiming.flightStartMs,
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
    test('起點靜止、蓄力縮到 0.92 並後仰 6°、偏 −8°', () {
      final start = practiceRevealPose(0);
      expect(start.yaw, closeTo(0, 1e-9));
      expect(start.pitch, closeTo(0, 1e-9));
      expect(start.scale, closeTo(1, 1e-9));

      for (final ms in [600.0, 900.0, 1100.0]) {
        final pose = practiceRevealPose(ms);
        expect(pose.yaw, closeTo(-8, 1e-9), reason: '$ms');
        expect(pose.pitch, closeTo(6, 1e-9), reason: '$ms');
        expect(pose.scale, closeTo(0.92, 1e-9), reason: '$ms');
      }
    });

    test('翻牌前半先往回拉再衝（easeInBack 預備動作）', () {
      final anticipation = [
        for (var ms = 1110.0; ms < 1250; ms += 10) practiceRevealPose(ms).yaw,
      ].reduce((a, b) => a < b ? a : b);
      expect(anticipation, lessThan(-12));
      expect(anticipation, greaterThan(-20));
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
    test('卡片 0.15 s 內縮到 0.15 並淡出', () {
      expect(practiceArchiveCardScale(0), 1);
      expect(practiceArchiveCardScale(150), closeTo(0.15, 1e-9));
      expect(practiceArchiveCardOpacity(60), 1);
      expect(practiceArchiveCardOpacity(150), 0);
    });

    test('背景 0.15–0.5 s 退場、光球 0.15–0.45 s 飛行', () {
      expect(practiceArchiveBackdrop(150), 1);
      expect(practiceArchiveBackdrop(500), 0);
      expect(practiceArchiveFlightT(150), 0);
      expect(practiceArchiveFlightT(450), 1);
    });

    test('控制點夾在畫面內縮 24 px 內，並往畫面中線那側鼓', () {
      const stage = Size(390, 844);
      const p0 = Offset(195, 380);
      for (final p2 in const [
        Offset(100, 700),
        Offset(300, 700),
        Offset(20, 20),
        Offset(370, 820),
      ]) {
        final c = practiceArchiveControlPoint(p0, p2, stage);
        expect(c.dx, inInclusiveRange(24, stage.width - 24), reason: '$p2');
        expect(c.dy, inInclusiveRange(24, stage.height - 24), reason: '$p2');
      }
      // 目標在左下：弧線往右（中線那側）鼓。
      final left =
          practiceArchiveControlPoint(p0, const Offset(80, 700), stage);
      final mid = (p0 + const Offset(80, 700)) / 2;
      expect(left.dx, greaterThan(mid.dx));
      // 起點與終點重合：退化成原點，不除以零。
      expect(practiceArchiveControlPoint(p0, p0, stage), p0);
    });

    test('貝茲曲線兩端落在起點與終點', () {
      const p0 = Offset(10, 20);
      const p1 = Offset(200, 50);
      const p2 = Offset(300, 400);
      expect(practiceQuadBezier(p0, p1, p2, 0), p0);
      expect(practiceQuadBezier(p0, p1, p2, 1), p2);
    });
  });

  group('卡背染色（只升到真實稀有度）', () {
    const n = PracticeGirlRarity.n;
    const r = PracticeGirlRarity.r;
    const sr = PracticeGirlRarity.sr;

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
      expect(practiceRevealFrameGlow(0), closeTo(0.25, 1e-9));
      expect(practiceRevealFrameGlow(600), closeTo(0.60, 1e-9));
    });

    test('白色爆閃只有 SR、只在染金那 120 ms', () {
      for (var ms = 0.0; ms <= PracticeRevealTiming.revealMs; ms += 5) {
        expect(practiceRevealGoldFlash(ms, n), 0);
        expect(practiceRevealGoldFlash(ms, r), 0);
        final inWindow = ms > 850 && ms < 970;
        if (!inWindow) {
          expect(practiceRevealGoldFlash(ms, sr), 0, reason: '$ms');
        }
      }
      expect(practiceRevealGoldFlash(886, sr), closeTo(1, 1e-9));
    });

    test('環境光 1.00 → 藍 1.15 → 金 1.35', () {
      expect(practiceRevealAmbientScale(2000, n), 1);
      expect(practiceRevealAmbientScale(2000, r), closeTo(1.15, 1e-9));
      expect(practiceRevealAmbientScale(2000, sr), closeTo(1.35, 1e-9));
    });
  });

  group('翻牌峰值：光刃與十字', () {
    test('光刃只在側立後 250 ms 內：60 ms 張到最寬再收掉', () {
      expect(practiceRevealBladeWidth(1350), 0);
      expect(practiceRevealBladeWidth(1410), closeTo(1, 1e-9));
      expect(practiceRevealBladeWidth(1600), 0);
      expect(practiceRevealBladeWidth(1300), 0);
      expect(practiceRevealBladeCore(1349), 0);
      expect(practiceRevealBladeCore(1350), closeTo(2, 1e-9));
      expect(practiceRevealBladeCore(1599), closeTo(1, 0.01));
      expect(practiceRevealBladeCore(1600), 0);
      expect(practiceRevealBladeCoreAlpha(1400), 1);
      expect(practiceRevealBladeCoreAlpha(1575), closeTo(0.5, 1e-9));
    });

    test('十字只有 SR、180 ms 鐘形', () {
      for (var ms = 1300.0; ms <= 1700; ms += 5) {
        expect(practiceRevealCross(ms, PracticeGirlRarity.n), 0);
        expect(practiceRevealCross(ms, PracticeGirlRarity.r), 0);
      }
      expect(
          practiceRevealCross(1440, PracticeGirlRarity.sr), closeTo(1, 1e-9));
      expect(practiceRevealCross(1530, PracticeGirlRarity.sr), 0);
    });
  });

  group('卡面：掃光、烙印、星星', () {
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

    test('稀有度牌 2.0 s 前不存在；1.6 → 1.0 撞擊，略微壓過 1.0 再回彈', () {
      expect(practiceRevealStamped(1999), isFalse);
      expect(practiceRevealStamped(2000), isTrue);
      expect(practiceRevealStampScale(2000), closeTo(1.6, 1e-9));
      expect(practiceRevealStampScale(2250), closeTo(1.0, 1e-9));
      var min = 2.0;
      for (var ms = 2000.0; ms <= 2250; ms += 2) {
        min = math.min(min, practiceRevealStampScale(ms));
      }
      expect(min, lessThan(1.0));
      expect(practiceRevealStampOpacity(2000), 0);
      expect(practiceRevealStampOpacity(2100), 1);
    });

    test('星星 2.15 s 起每 80 ms 一顆：0 → 1.25 → 1.00，停住前全部到位', () {
      for (var i = 0; i < 4; i++) {
        final start = PracticeRevealTiming.starsStartMs + 80 * i;
        expect(practiceRevealStarStartMs(i), start);
        expect(practiceRevealStarScale(start, i), 0);
        expect(
          practiceRevealStarScale(
              start + 0.6 * PracticeRevealTiming.starPopMs, i),
          closeTo(1.25, 1e-9),
        );
        expect(
            practiceRevealStarScale(start + PracticeRevealTiming.starPopMs, i),
            1);
        expect(practiceRevealStarScale(PracticeRevealTiming.revealMs, i), 1);
        expect(practiceRevealStarPulse(PracticeRevealTiming.revealMs, i), 0);
      }
    });
  });

  group('收卡：變成光、光球、星點', () {
    test('資訊 80 ms 內淡掉、卡面 150 ms 內變成光', () {
      expect(practiceArchiveInfoOpacity(0), 1);
      expect(practiceArchiveInfoOpacity(80), 0);
      expect(practiceArchiveCardLight(0), 0);
      expect(practiceArchiveCardLight(150), 1);
    });

    test('光球 90 ms 起在卡片中心從 14 長到 18，飛行中縮到 10', () {
      expect(practiceArchiveOrbRadius(89), 0);
      expect(practiceArchiveOrbRadius(90), closeTo(14, 1e-9));
      expect(practiceArchiveOrbRadius(150), closeTo(18, 1e-9));
      expect(practiceArchiveOrbRadius(450), closeTo(10, 1e-9));
    });

    test('8 顆星點在光球經過 t＝0.1·i 時灑出', () {
      var last = PracticeRevealTiming.flightStartMs;
      for (var i = 1; i <= PracticeRevealTiming.sparkleCount; i++) {
        final ms = practiceArchiveSparkleSpawnMs(i);
        expect(ms, greaterThan(last), reason: 'sparkle $i');
        expect(ms, lessThan(PracticeRevealTiming.landMs));
        // Flutter 的 Cubic 求值本身在 x 上只到 ±0.001，曲線中段斜率約 3。
        expect(practiceArchiveFlightT(ms), closeTo(0.1 * i, 5e-3));
        last = ms;
      }
    });

    test('貝茲切線：起點朝控制點、終點從控制點出來', () {
      const p0 = Offset(0, 0);
      const p1 = Offset(100, 0);
      const p2 = Offset(100, 100);
      expect(practiceQuadBezierTangent(p0, p1, p2, 0), const Offset(200, 0));
      expect(practiceQuadBezierTangent(p0, p1, p2, 1), const Offset(0, 200));
    });
  });
}
