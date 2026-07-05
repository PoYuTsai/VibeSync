// 翻牌揭曉「結果卡」的稀有度呈現（邊框／光暈／badge／星等）。
//
// 紅線：只驗結果卡的靜態裝飾，不碰翻牌演出時間軸（beat 常數／controller 皆不涉入）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_girl_catalog.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_girl_profile.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_girl_rarity.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_draw_ceremony.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_rarity_style.dart';

void main() {
  // 錨點與 catalog 指定同步：004=SR、010=R、001=N（見 practice_persona.ts）。
  final sr = practiceGirlProfiles[3]; // practice_girl_004
  final r = practiceGirlProfiles[9]; // practice_girl_010
  final n = practiceGirlProfiles.first; // practice_girl_001

  group('practiceRarityColor', () {
    test('SR 金／R 紫／N 冷灰藍（與圖鑑 _rarityColor 同一真相）', () {
      expect(practiceRarityColor(PracticeGirlRarity.sr),
          const Color(0xFFFFB34D));
      expect(practiceRarityColor(PracticeGirlRarity.n),
          const Color(0xFF8FA0BE));
      // R 用品牌紫（AppColors.primaryLight）；只驗三色互異避免鎖死主題常數。
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
            child: debugCeremonyGrandCardFront(
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

  group('揭曉結果卡（grand）稀有度呈現', () {
    testWidgets('SR 卡：badge 顯 SR、4 亮星 1 空星', (tester) async {
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
        findsNWidgets(1),
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

    testWidgets('N 卡：badge 顯 N、2 亮星；邊框光暈用 N 冷灰藍', (tester) async {
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

      // 邊框/光暈套 rarity 色：结果卡外框 Container 的 boxShadow 帶 N 色。
      final front = tester.widget<Container>(
        find.byKey(const ValueKey('practice-draw-ceremony-front')),
      );
      final deco = front.decoration! as BoxDecoration;
      final nColor = practiceRarityColor(PracticeGirlRarity.n);
      expect(
        deco.boxShadow!.any(
          (s) =>
              (s.color.toARGB32() & 0x00FFFFFF) ==
              (nColor.toARGB32() & 0x00FFFFFF),
        ),
        isTrue,
        reason: 'grand 卡光暈應套 N 稀有度色',
      );
    });
  });
}
