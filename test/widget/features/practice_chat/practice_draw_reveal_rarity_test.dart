// 翻牌揭曉「結果卡」的稀有度呈現（V3：外框光暈／膠囊稀有度牌／只畫亮星）。
//
// 紅線：只驗結果卡停住時的靜態裝飾，不碰翻牌演出時間軸（beat 常數／controller 皆不涉入）。
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_girl_catalog.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_girl_profile.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_girl_rarity.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_draw_ceremony.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_rarity_style.dart';
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
      expect(
        find.descendant(of: stars, matching: find.byIcon(Icons.star_rounded)),
        findsNWidgets(4),
      );
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
      final stars =
          find.byKey(const ValueKey('practice-draw-ceremony-rarity-stars'));
      expect(
        find.descendant(of: stars, matching: find.byIcon(Icons.star_rounded)),
        findsNWidgets(3),
      );
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
      final stars =
          find.byKey(const ValueKey('practice-draw-ceremony-rarity-stars'));
      expect(
        find.descendant(of: stars, matching: find.byIcon(Icons.star_rounded)),
        findsNWidgets(2),
      );

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

    testWidgets('新角色：稀有度牌右邊掛 NEW、在卡片內，資訊欄沒有「已收藏」', (tester) async {
      await pumpCard(tester, isNew: true);

      expect(find.byKey(newTag), findsOneWidget);
      final card = tester.getRect(
        find.byKey(const ValueKey('practice-draw-ceremony-front')),
      );
      final tag = tester.getRect(find.byKey(newTag));
      expect(tag.left, greaterThan(tester.getRect(find.byKey(badge)).right));
      expect(
          card.contains(tag.topLeft) && card.contains(tag.bottomRight), isTrue);
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
}
