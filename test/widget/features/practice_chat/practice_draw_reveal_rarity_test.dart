// 翻牌揭曉「結果卡」的稀有度呈現（V3：外框光暈／膠囊稀有度牌／只畫亮星）。
//
// 紅線：只驗結果卡停住時的靜態裝飾，不碰翻牌演出時間軸（beat 常數／controller 皆不涉入）。
import 'package:flutter/material.dart';
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
}
