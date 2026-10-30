import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/core/theme/app_typography.dart';
import 'package:vibesync/core/theme/practice_reveal_palette.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_girl_rarity.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_reveal_card.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_reveal_painters.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_reveal_theme.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_reveal_timing.dart';

/// V3 揭曉外觀的純邏輯（規格 §6.3、§7）：稀有度主題、環境光跟著卡背染色、星塵。
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
      // V3.1 §5.7、§9：高檔 N 24、R 48、SR 160；中檔 SR 80；低檔上限 48。預設中檔。
      expect(kPracticeRevealEffectTier, PracticeRevealEffectTier.medium);
      expect(themes.map((t) => t.burstCounts), [
        (high: 24, medium: 24, low: 24),
        (high: 48, medium: 48, low: 48),
        (high: 160, medium: 80, low: 48),
      ]);
      expect(themes.map((t) => t.burstCount), [24, 48, 80]);
      expect(themes.map((t) => t.burstSpeed), [1.0, 1.2, 1.7]);
      // V3.1 §5.5：光刃外暈最寬 N 0.6、R 0.7、SR 0.8×卡寬。
      expect(themes.map((t) => t.bladeWidth), [0.6, 0.7, 0.8]);
      expect(themes.map((t) => t.ambientAlpha), [0.22, 0.32, 0.45]);
      expect(themes.map((t) => t.sheenStrength), [0.35, 0.55, 0.85]);
      expect(themes.map((t) => t.holo), [false, false, true]);
      // D9=A：揭曉的 R 用較亮的電光藍，和圖鑑的 #64B5F6 分開（典藏材質 M9 起衝擊波跟環境光同色）。
      expect(themes[1].shockwave, PracticeRevealPalette.rGlow);
      expect(themes[1].shockwave, isNot(const Color(0xFF64B5F6)));
    });

    test('泛光層數：高、中檔前後兩層，低檔只畫後層（§9）；檔位可在測試覆寫', () {
      expect(practiceRevealBloomLayers(PracticeRevealEffectTier.high), 2);
      expect(practiceRevealBloomLayers(PracticeRevealEffectTier.medium), 2);
      expect(practiceRevealBloomLayers(PracticeRevealEffectTier.low), 1);
      expect(practiceRevealEffectTier, kPracticeRevealEffectTier);

      debugPracticeRevealEffectTierOverride = PracticeRevealEffectTier.low;
      addTearDown(() => debugPracticeRevealEffectTierOverride = null);
      expect(practiceRevealEffectTier, PracticeRevealEffectTier.low);
      expect(PracticeRevealTheme.of(PracticeGirlRarity.sr).burstCount, 48);
    });
  });

  group('環境光跟著卡背染色（只升到真實稀有度）', () {
    double distance(Color a, Color b) =>
        (a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs();

    test('N 全程銀；R 只會銀 → 藍、絕不靠近金；SR 最後落在金', () {
      final silver = PracticeRevealBackColors.silver;
      for (var ms = 0.0; ms <= PracticeRevealTiming.revealMs; ms += 10) {
        final nColors = PracticeRevealBackColors.at(ms, PracticeGirlRarity.n);
        expect(nColors.glow, silver.glow, reason: 'N $ms');

        final rColors = PracticeRevealBackColors.at(ms, PracticeGirlRarity.r);
        expect(
          distance(rColors.glow, PracticeRevealPalette.srGlow),
          greaterThan(0.3),
          reason: 'R 不會出現金（$ms）',
        );
      }
      final rEnd = PracticeRevealBackColors.at(2000, PracticeGirlRarity.r);
      expect(rEnd.glow, PracticeRevealPalette.rGlow);
      final srEnd = PracticeRevealBackColors.at(2000, PracticeGirlRarity.sr);
      expect(srEnd.glow, PracticeRevealPalette.srGlow);
      expect(srEnd.ambientAlpha, closeTo(0.45, 1e-9));
    });

    test('SR 先藍後金：染金前（0.85 s 前）就是 R 的藍', () {
      final srBlue = PracticeRevealBackColors.at(800, PracticeGirlRarity.sr);
      expect(srBlue.glow, PracticeRevealPalette.rGlow);
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

  group('升階光點（V3.1 §5.3）', () {
    const card = Size(300, 450);

    test('染藍後才出生、翻牌峰值前全部燃盡；1.5–3 px；同一時間點算兩次完全一樣', () {
      var seen = 0;
      for (var ms = 0.0; ms <= PracticeRevealTiming.revealMs; ms += 10) {
        for (var i = 0; i < kPracticeRevealRiseDotCount; i++) {
          final p = practiceRevealRiseDot(i, ms, card);
          final again = practiceRevealRiseDot(i, ms, card);
          expect(p?.offset, again?.offset);
          expect(p?.alpha, again?.alpha);
          if (p == null) continue;
          seen++;
          expect(ms, greaterThan(PracticeRevealTiming.dyeBlueEndMs));
          expect(ms, lessThan(PracticeRevealTiming.flipPeakMs));
          expect(p.radius * 2, inInclusiveRange(1.5, 3.0));
          expect(p.alpha, inInclusiveRange(0, 0.9));
          // 繞著卡片四周（外擴 6 px）出生，往上飄、左右輕晃。
          expect(p.offset.dx.abs(), lessThanOrEqualTo(card.width / 2 + 6 + 3));
          expect(p.offset.dy, lessThanOrEqualTo(card.height / 2 + 6));
          expect(p.offset.dy, greaterThan(-card.height / 2 - 6 - 40));
        }
      }
      expect(seen, greaterThan(0));
    });

    test('不只左右邊：卡片上下兩邊也有光點出生', () {
      var topOrBottom = 0;
      for (var i = 0; i < kPracticeRevealRiseDotCount; i++) {
        for (var ms = 721.0; ms < 1350; ms += 5) {
          final p = practiceRevealRiseDot(i, ms, card);
          if (p == null) continue;
          if (p.offset.dx.abs() < card.width / 2) topOrBottom++;
          break;
        }
      }
      expect(topOrBottom, greaterThan(0));
    });
  });

  group('每幀粒子合計（V3.1 §9）', () {
    test('各檔位同一幀的粒子合計不超過上限：高 300、中 180、低 120', () {
      // 升階光點只在翻牌峰值前、爆發星塵只在峰值後，兩者不會同一幀出現。
      for (var ms = 0.0; ms <= PracticeRevealTiming.revealMs; ms += 10) {
        final rise = practiceRevealRiseDot(0, ms, const Size(300, 450));
        if (ms >= PracticeRevealTiming.flipPeakMs) expect(rise, isNull);
      }
      final sr = PracticeRevealTheme.sr.burstCounts;
      for (final (count, cap) in [
        (sr.high, 300),
        (sr.medium, 180),
        (sr.low, 120),
      ]) {
        final perFrame = kPracticeRevealAmbientDustCount +
            (count > kPracticeRevealRiseDotCount
                ? count
                : kPracticeRevealRiseDotCount);
        expect(perFrame, lessThanOrEqualTo(cap), reason: '$count');
      }
      for (final theme in [PracticeRevealTheme.n, PracticeRevealTheme.r]) {
        expect(theme.burstCounts.low, lessThanOrEqualTo(48));
      }
    });
  });

  group('收卡光尾（V3.1 §5.12）', () {
    test('光球端 16 px、尾端 0，由粗到細', () {
      expect(practiceArchiveTailWidth(0), 16);
      expect(practiceArchiveTailWidth(1), 0);
      var last = double.infinity;
      for (var f = 0.0; f <= 1; f += 0.05) {
        final w = practiceArchiveTailWidth(f);
        expect(w, lessThan(last), reason: '$f');
        last = w;
      }
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
    // 內文 15 × 1.4 = 21 px 一行；尖角 6＋上下內距 16＝22 px。
    test('兩行要 64 px、一行要 43 px，再少就不顯示；最多兩行', () {
      const scaler = TextScaler.noScaling;
      expect(practiceIntroBubbleLines(120, scaler), 2);
      expect(practiceIntroBubbleLines(64.1, scaler), 2);
      expect(practiceIntroBubbleLines(63.9, scaler), 1);
      expect(practiceIntroBubbleLines(43.1, scaler), 1);
      expect(practiceIntroBubbleLines(42.9, scaler), 0);
      expect(practiceIntroBubbleLines(-10, scaler), 0);
    });

    test('系統字級放大時行高跟著變高，同樣的空間放得下的行數變少', () {
      // 1.3 倍：一行 27.3 px，兩行要 76.6 px。
      const scaler = TextScaler.linear(1.3);
      expect(practiceIntroBubbleLines(76.7, scaler), 2);
      expect(practiceIntroBubbleLines(70, scaler), 1);
    });
  });

  group('第一句話兩行等長（V3.1 §5.13）', () {
    // 22 字：不收窄的話 390 寬一行排 21 字，第二行只剩「。」或「點。」。
    const twoLines = '排班有點不固定，但遇到有趣的人會想多聊一點。';
    const maxWidth = 319.0; // 390 寬的卡片（351）扣掉左右內距 16
    final style =
        AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600);

    List<double> lineWidths(String text, double width) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        maxLines: 2,
      )..layout(maxWidth: width);
      final widths = [for (final m in painter.computeLineMetrics()) m.width];
      painter.dispose();
      return widths;
    }

    double balanced(String text, {int maxLines = 2}) =>
        practiceIntroBalancedWidth(
          text: text,
          style: style,
          textScaler: TextScaler.noScaling,
          textDirection: TextDirection.ltr,
          maxLines: maxLines,
          maxWidth: maxWidth,
        );

    testWidgets('要折兩行時收窄到兩行差不到一個字', (tester) async {
      final unbalanced = lineWidths(twoLines, maxWidth);
      expect(unbalanced, hasLength(2));
      expect(unbalanced.last, lessThan(unbalanced.first / 4));

      final width = balanced(twoLines);
      expect(width, lessThan(maxWidth));
      final widths = lineWidths(twoLines, width);
      expect(widths, hasLength(2));
      expect((widths.first - widths.last).abs(), lessThanOrEqualTo(15.5));
    });

    testWidgets('一行放得下、兩行也放不下要省略、或只准一行時，照原本的寬度', (tester) async {
      expect(balanced('手沖咖啡是我的本命。'), maxWidth);
      expect(balanced(twoLines * 3), maxWidth);
      expect(balanced(twoLines, maxLines: 1), maxWidth);
    });

    Future<RenderParagraph> pumpBubble(
      WidgetTester tester, {
      bool boldText = false,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(boldText: boldText),
            child: child!,
          ),
          home: const Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: 351,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: PracticeRevealIntroBubble(
                    text: twoLines,
                    typed: 1,
                    maxLines: 2,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      return tester.renderObject<RenderParagraph>(
        find.byKey(const ValueKey('practice-draw-ceremony-intro-text')),
      );
    }

    testWidgets('對話框在 App 的字樣下排出來也是兩行等長、不被省略', (tester) async {
      final paragraph = await pumpBubble(tester);
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(paragraph.size.width, lessThan(maxWidth * 0.75));
      expect(paragraph.size.height, closeTo(2 * 15 * 1.4, 0.5));
    });

    testWidgets('系統開了「粗體文字」也照樣兩行、不被省略', (tester) async {
      final paragraph = await pumpBubble(tester, boldText: true);
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(paragraph.size.width, lessThan(maxWidth * 0.75));
      expect(paragraph.size.height, closeTo(2 * 15 * 1.4, 0.5));
    });
  });
}
