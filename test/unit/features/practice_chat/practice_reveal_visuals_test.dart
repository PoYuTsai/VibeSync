import 'dart:ui' show Color, Size;

import 'package:flutter/painting.dart' show TextScaler;
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/core/theme/practice_reveal_palette.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_girl_rarity.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_reveal_card.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_reveal_painters.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_reveal_theme.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_reveal_timing.dart';

/// V3 揭曉外觀的純邏輯（規格 §6.3、§7）：稀有度主題、卡背染色、星塵。
void main() {
  group('稀有度主題', () {
    test('N／R／SR 各自一組，星塵顆數與掃光強度隨稀有度遞增，只有 SR 有全息', () {
      final themes = [
        for (final r in [
          PracticeGirlRarity.n,
          PracticeGirlRarity.r,
          PracticeGirlRarity.sr,
        ])
          PracticeRevealTheme.of(r),
      ];
      expect(themes.map((t) => t.burstCount), [20, 26, 34]);
      expect(themes.map((t) => t.ambientAlpha), [0.22, 0.32, 0.45]);
      expect(themes.map((t) => t.sheenStrength), [0.35, 0.55, 0.85]);
      expect(themes.map((t) => t.holo), [false, false, true]);
      // D9=A：揭曉的 R 用較亮的電光藍，和圖鑑的 #64B5F6 分開。
      expect(themes[1].backTint, PracticeRevealPalette.rBackTint);
      expect(themes[1].backTint, isNot(const Color(0xFF64B5F6)));
    });
  });

  group('卡背顏色（只升到真實稀有度）', () {
    double distance(Color a, Color b) =>
        (a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs();

    test('N 全程銀；R 只會銀 → 藍、絕不靠近金；SR 最後落在金', () {
      final silver = PracticeRevealBackColors.silver;
      for (var ms = 0.0; ms <= PracticeRevealTiming.revealMs; ms += 10) {
        final nColors = PracticeRevealBackColors.at(ms, PracticeGirlRarity.n);
        expect(nColors.tint, silver.tint, reason: 'N $ms');
        expect(nColors.holo, 0);

        final rColors = PracticeRevealBackColors.at(ms, PracticeGirlRarity.r);
        expect(
          distance(rColors.tint, PracticeRevealPalette.srBackTint),
          greaterThan(0.3),
          reason: 'R 不會出現金（$ms）',
        );
        expect(rColors.holo, 0);
      }
      final rEnd = PracticeRevealBackColors.at(2000, PracticeGirlRarity.r);
      expect(rEnd.tint, PracticeRevealPalette.rBackTint);
      final srEnd = PracticeRevealBackColors.at(2000, PracticeGirlRarity.sr);
      expect(srEnd.tint, PracticeRevealPalette.srBackTint);
      expect(srEnd.holo, 1);
      expect(srEnd.ambientAlpha, closeTo(0.45, 1e-9));
    });

    test('SR 先藍後金：染金前（0.85 s 前）就是 R 的藍', () {
      final srBlue = PracticeRevealBackColors.at(800, PracticeGirlRarity.sr);
      expect(srBlue.tint, PracticeRevealPalette.rBackTint);
      expect(srBlue.holo, 0);
    });
  });

  group('爆發星塵', () {
    const card = Size(351, 526.5);

    test('同一時間點算兩次完全一樣（零 Random）', () {
      for (var i = 0; i < 34; i++) {
        for (final tau in [0.0, 30.0, 400.0, 1100.0]) {
          expect(
            practiceRevealBurstParticle(i, tau, card),
            practiceRevealBurstParticle(i, tau, card),
          );
        }
      }
    });

    test('側立前不存在；停住前（側立後 1.3 s）全部燃盡', () {
      for (var i = 0; i < 34; i++) {
        expect(practiceRevealBurstParticle(i, -1, card), isNull);
        expect(
          practiceRevealBurstParticle(i, kPracticeRevealBurstMaxLifeMs, card),
          isNull,
        );
      }
      expect(
        PracticeRevealTiming.flipPeakMs + kPracticeRevealBurstMaxLifeMs,
        lessThan(PracticeRevealTiming.revealMs),
      );
    });

    test('從卡片中心垂直軸噴出；失焦大光斑不透明度壓在 0.25 以下', () {
      var bokeh = 0;
      for (var i = 0; i < 34; i++) {
        final start = practiceRevealBurstParticle(i, 0, card)!;
        expect(start.offset.dx, 0);
        expect(start.offset.dy.abs(), lessThanOrEqualTo(card.height * 0.4));
        for (var tau = 0.0; tau < kPracticeRevealBurstMaxLifeMs; tau += 50) {
          final p = practiceRevealBurstParticle(i, tau, card);
          if (p == null) continue;
          if (p.bokeh) {
            expect(p.alpha, lessThanOrEqualTo(0.25));
            bokeh++;
          }
        }
      }
      expect(bokeh, greaterThan(0), reason: '尺寸分布要有少量失焦大光斑');
    });
  });

  group('環境星塵', () {
    const area = Size(390, 844);

    test('接圈那一刻透明：循環無縫', () {
      for (var i = 0; i < kPracticeRevealAmbientDustCount; i++) {
        // 讓第 i 顆的局部相位 u 落在 0（剛接圈）。
        final phase = -(i + 1) * 0.6180339887;
        final p = practiceRevealAmbientParticle(i, phase, area);
        expect(p.alpha, closeTo(0, 1e-6), reason: 'dust $i');
      }
    });

    test('位置在畫面內、往上漂、不透明度 0.15–0.45', () {
      for (var i = 0; i < kPracticeRevealAmbientDustCount; i++) {
        final a = practiceRevealAmbientParticle(i, 0.2, area);
        final b = practiceRevealAmbientParticle(i, 0.21, area);
        expect(a.offset.dx, inInclusiveRange(0, area.width));
        expect(a.offset.dy, inInclusiveRange(0, area.height));
        expect(a.alpha, lessThanOrEqualTo(0.45));
        if (b.offset != a.offset && (b.offset - a.offset).distance < 10) {
          expect(b.offset.dy, lessThan(a.offset.dy), reason: 'dust $i 往上漂');
        }
        expect(b.offset.dx, a.offset.dx);
      }
    });

    test('同一相位算兩次完全一樣', () {
      for (var i = 0; i < kPracticeRevealAmbientDustCount; i++) {
        expect(
          practiceRevealAmbientParticle(i, 1.37, area),
          practiceRevealAmbientParticle(i, 1.37, area),
        );
      }
    });
  });

  group('第一句話對話框放得下幾行（V3.1 §5.13）', () {
    // 一行 13 × 1.4 = 18.2 px；尖角 6＋上下內距 16＝22 px。
    test('兩行要 58.4 px、一行要 40.2 px，再少就不顯示；最多兩行', () {
      const scaler = TextScaler.noScaling;
      expect(practiceIntroBubbleLines(120, scaler), 2);
      expect(practiceIntroBubbleLines(58.5, scaler), 2);
      expect(practiceIntroBubbleLines(58.3, scaler), 1);
      expect(practiceIntroBubbleLines(40.3, scaler), 1);
      expect(practiceIntroBubbleLines(40.1, scaler), 0);
      expect(practiceIntroBubbleLines(-10, scaler), 0);
    });

    test('系統字級放大時行高跟著變高，同樣的空間放得下的行數變少', () {
      // 1.3 倍：一行 23.66 px，兩行要 69.32 px。
      const scaler = TextScaler.linear(1.3);
      expect(practiceIntroBubbleLines(69.4, scaler), 2);
      expect(practiceIntroBubbleLines(60, scaler), 1);
    });
  });
}
