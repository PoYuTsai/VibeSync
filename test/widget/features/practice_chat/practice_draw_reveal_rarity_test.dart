// 翻牌揭曉「結果卡」的稀有度呈現（V3：外框光暈／稀有度牌／只畫亮星；典藏材質規格
// docs/plans/2026-10-28-card-collectible-material-spec.md §7：拋光外框、牌收進卡內、切面星、字級）。
//
// 紅線：只驗結果卡停住時的靜態裝飾，不碰翻牌演出時間軸（beat 常數／controller 皆不涉入）。
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_girl_catalog.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_girl_profile.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_girl_rarity.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_card_material.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_draw_ceremony.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_rarity_style.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_reveal_card.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_reveal_theme.dart';

void main() {
  // 錨點與 catalog 指定同步：004=SR、010=R、001=N（見 practice_persona.ts）。
  final sr = practiceGirlProfiles[3]; // practice_girl_004
  final r = practiceGirlProfiles[9]; // practice_girl_010
  final n = practiceGirlProfiles.first; // practice_girl_001

  group('practiceRarityColor', () {
    test('SR 金／R 青藍／N 中性銀灰（與圖鑑 _rarityColor 同一真相）', () {
      // 2026-08-09 改版：N 去藍味退成銀灰、R 改青藍（暗紫背景上與 N 拉開），
      // 階梯＝銀灰→藍→金。
      expect(
          practiceRarityColor(PracticeGirlRarity.sr), const Color(0xFFFFB34D));
      expect(
          practiceRarityColor(PracticeGirlRarity.n), const Color(0xFFA9B0B8));
      // R 用 AppColors.cold 青藍；只驗三色互異避免鎖死主題常數。
      expect(
        practiceRarityColor(PracticeGirlRarity.r),
        isNot(practiceRarityColor(PracticeGirlRarity.sr)),
      );
      expect(
        practiceRarityColor(PracticeGirlRarity.r),
        isNot(practiceRarityColor(PracticeGirlRarity.n)),
      );
    });
  });

  /// 切面星每顆一個 key（典藏材質規格 §7.7）：亮了幾顆就有幾個，空星不畫。
  int litStars() {
    var count = 0;
    while (find
        .byKey(ValueKey('practice-draw-ceremony-star-$count'))
        .evaluate()
        .isNotEmpty) {
      count++;
    }
    return count;
  }

  Future<void> pumpGrandCard(
    WidgetTester tester,
    PracticeGirlProfile girl,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: debugCeremonyCardFront(
              girl: girl,
              width: 300,
              height: 450,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('揭曉結果卡稀有度呈現（停住時）', () {
    testWidgets('SR 卡：稀有度牌顯 SR、只畫 4 顆亮星（D6=A 不畫空星）', (tester) async {
      expect(sr.rarity, PracticeGirlRarity.sr); // 錨點保險
      await pumpGrandCard(tester, sr);

      final badge =
          find.byKey(const ValueKey('practice-draw-ceremony-rarity-badge'));
      expect(badge, findsOneWidget);
      expect(
        find.descendant(of: badge, matching: find.text('SR')),
        findsOneWidget,
      );

      final stars =
          find.byKey(const ValueKey('practice-draw-ceremony-rarity-stars'));
      expect(stars, findsOneWidget);
      expect(litStars(), 4);
      // 空星不畫：亮星以外沒有其他星形。
      expect(
        find.descendant(
            of: stars, matching: find.byIcon(Icons.star_outline_rounded)),
        findsNothing,
      );
    });

    testWidgets('R 卡：badge 顯 R、3 亮星', (tester) async {
      expect(r.rarity, PracticeGirlRarity.r);
      await pumpGrandCard(tester, r);
      final badge =
          find.byKey(const ValueKey('practice-draw-ceremony-rarity-badge'));
      expect(
        find.descendant(of: badge, matching: find.text('R')),
        findsOneWidget,
      );
      expect(litStars(), 3);
    });

    testWidgets('N 卡：稀有度牌顯 N、2 顆亮星；外光用 N 主題的銀', (tester) async {
      expect(n.rarity, PracticeGirlRarity.n);
      await pumpGrandCard(tester, n);
      final badge =
          find.byKey(const ValueKey('practice-draw-ceremony-rarity-badge'));
      expect(
        find.descendant(of: badge, matching: find.text('N')),
        findsOneWidget,
      );
      expect(litStars(), 2);

      // 外框外光套揭曉主題色：結果卡外框 Container 的 boxShadow 帶 N 主題的銀。
      final front = tester.widget<Container>(
        find.byKey(const ValueKey('practice-draw-ceremony-front')),
      );
      final deco = front.decoration! as BoxDecoration;
      final nGlow = PracticeRevealTheme.of(PracticeGirlRarity.n).glow;
      expect(
        deco.boxShadow!.any(
          (s) =>
              (s.color.toARGB32() & 0x00FFFFFF) ==
              (nGlow.toARGB32() & 0x00FFFFFF),
        ),
        isTrue,
        reason: '結果卡外光應套 N 主題色',
      );
    });

    testWidgets('剛翻開落定（還沒烙印）時沒有稀有度牌、星星還沒點亮', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: debugCeremonyCardFront(
                girl: sr,
                width: 300,
                height: 450,
                settled: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('practice-draw-ceremony-rarity-badge')),
        findsNothing,
      );
      final scales = tester
          .widgetList<Transform>(
            find.descendant(
              of: find
                  .byKey(const ValueKey('practice-draw-ceremony-rarity-stars')),
              matching: find.byType(Transform),
            ),
          )
          .map((t) => t.transform.entry(0, 0));
      expect(scales, everyElement(0));
    });
  });

  group('新角色與重複角色（V3.1 規格 §5.14）', () {
    const newTag = ValueKey('practice-draw-ceremony-new-tag');
    const badge = ValueKey('practice-draw-ceremony-rarity-badge');

    Future<void> pumpCard(WidgetTester tester, {bool? isNew}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: debugCeremonyCardFront(
                girl: sr,
                width: 300,
                height: 450,
                isNew: isNew,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('新角色：六角牌右邊 6 px 掛 NEW、跟牌垂直置中（一起壓在卡片上緣），資訊欄沒有「已收藏」',
        (tester) async {
      await pumpCard(tester, isNew: true);

      expect(find.byKey(newTag), findsOneWidget);
      final card = tester.getRect(
        find.byKey(const ValueKey('practice-draw-ceremony-front')),
      );
      final tag = tester.getRect(find.byKey(newTag));
      final badgeRect = tester.getRect(find.byKey(badge));
      expect(tag.left - badgeRect.right, closeTo(6, 0.5));
      expect(tag.center.dy, closeTo(badgeRect.center.dy, 0.5));
      // 跟牌一起收在卡片內（典藏材質規格 §7.3、§7.4）。
      expect(tag.top, greaterThan(card.top));
      expect(tag.right, lessThan(card.right));
      expect(
        tag.overlaps(tester.getRect(
            find.byKey(const ValueKey('practice-draw-ceremony-info')))),
        isFalse,
      );
      expect(find.textContaining('已收藏'), findsNothing);
    });

    testWidgets('重複角色：不掛 NEW，基本資訊那行最後是「已收藏」', (tester) async {
      await pumpCard(tester, isNew: false);

      expect(find.byKey(newTag), findsNothing);
      expect(find.textContaining(RegExp(r' · 已收藏$')), findsOneWidget);
    });

    testWidgets('重複角色：小螢幕＋字放大時先省略基本資訊，「已收藏」整個看得到', (tester) async {
      // 最擠的組合：iPhone SE 的卡寬、卡面字級上限 1.3 倍、SR 四顆星＋最長的職業。
      const screen = Size(375, 667);
      final nina = practiceGirlProfiles
          .firstWhere((p) => p.profileId == 'practice_girl_008'); // 牙醫診所助理
      final card = practiceCeremonyCardSize(screen);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: screen,
              textScaler: TextScaler.linear(1.3),
            ),
            child: Scaffold(
              backgroundColor: Colors.black,
              body: Center(
                child: debugCeremonyCardFront(
                  girl: nina,
                  width: card.width,
                  height: card.height,
                  isNew: false,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final collected = find.text(' · 已收藏');
      expect(
        tester.renderObject<RenderParagraph>(collected).didExceedMaxLines,
        isFalse,
      );
      expect(
        tester
            .renderObject<RenderParagraph>(
              find.textContaining(nina.professionLabel),
            )
            .didExceedMaxLines,
        isTrue,
      );
      final info = tester.getRect(
        find.byKey(const ValueKey('practice-draw-ceremony-info')),
      );
      final tag = tester.getRect(collected);
      expect(
        info.contains(tag.topLeft) && info.contains(tag.bottomRight),
        isTrue,
      );
    });

    testWidgets('不知道新舊（沒有抽牌前的紀錄）：NEW、「已收藏」都不畫', (tester) async {
      await pumpCard(tester);

      expect(find.byKey(newTag), findsNothing);
      expect(find.textContaining('已收藏'), findsNothing);
    });
  });

  group('典藏材質（規格 docs/plans/2026-10-28-card-collectible-material-spec.md §7）',
      () {
    Rect frontRect(WidgetTester tester) => tester.getRect(
          find.byKey(const ValueKey('practice-draw-ceremony-front')),
        );

    testWidgets('六角牌收在卡片左上角內（左 12、上 16），寬 0.20×卡寬（夾 60–80）、高 0.62×寬',
        (tester) async {
      await pumpGrandCard(tester, sr); // 300 寬的卡 → 牌寬 60（剛好在下限）
      final card = frontRect(tester);
      final badge = tester.getRect(
        find.byKey(const ValueKey('practice-draw-ceremony-rarity-badge')),
      );
      expect(badge.left - card.left, closeTo(12, 0.5));
      expect(badge.top - card.top, closeTo(16, 0.5));
      expect(badge.width, closeTo(60, 0.5));
      expect(badge.height, closeTo(60 * 0.62, 0.5));
      expect(practiceRevealBadgeWidth(354), closeTo(70.8, 1e-9));
      expect(practiceRevealBadgeWidth(240), 60);
      expect(practiceRevealBadgeWidth(500), 80);
      // SR 落地小光環的圓心就是牌的中心。
      expect(
        card.topLeft + practiceRevealBadgeCenter(card.size),
        offsetMoreOrLessEquals(badge.center, epsilon: 0.5),
      );
    });

    testWidgets('切面星 18 pt、中心距 24（間距 6）', (tester) async {
      await pumpGrandCard(tester, sr);
      final rects = [
        for (var i = 0; i < 4; i++)
          tester
              .getRect(find.byKey(ValueKey('practice-draw-ceremony-star-$i'))),
      ];
      for (final r in rects) {
        expect(r.width, closeTo(18, 0.01));
        expect(r.height, closeTo(18, 0.01));
      }
      for (var i = 1; i < rects.length; i++) {
        expect(rects[i].center.dx - rects[i - 1].center.dx, closeTo(24, 0.01));
      }
    });

    testWidgets('資訊欄字級：名字 24 w800、基本資訊 15（M5 照示意圖）', (tester) async {
      await pumpGrandCard(tester, sr);
      final name = tester.widget<Text>(find.text(sr.displayName));
      expect(name.style!.fontSize, 24);
      expect(name.style!.fontWeight, FontWeight.w800);
      final meta = tester.widget<Text>(find.textContaining('${sr.age} · '));
      expect(meta.style!.fontSize, 15);
    });

    testWidgets('拋光外框用該稀有度的外框色；只有 SR 有全息邊；停住時受光點在左上（225°）', (tester) async {
      for (final girl in [n, r, sr]) {
        await pumpGrandCard(tester, girl);
        final rim = tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((p) => p.foregroundPainter)
            .whereType<PracticeCardRimPainter>()
            .single;
        final theme = PracticeRevealTheme.of(girl.rarity);
        expect(rim.dark, theme.rimDark);
        expect(rim.mid, theme.rimMid);
        expect(rim.hi, theme.rimHi);
        expect(rim.holo, girl.rarity == PracticeGirlRarity.sr);
        expect(rim.light, PracticeCardLight.settled);
        expect(rim.light.glintDeg, closeTo(225, 1e-9));
      }
    });
  });
}
