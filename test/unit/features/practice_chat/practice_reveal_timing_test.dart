import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';
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
    test('翻牌閃光只在峰值附近', () {
      expect(practiceRevealFlipFlash(1350), closeTo(1, 1e-9));
      expect(practiceRevealFlipFlash(1000), lessThan(0.01));
      expect(practiceRevealFlipFlash(1700), lessThan(0.01));
    });

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
}
