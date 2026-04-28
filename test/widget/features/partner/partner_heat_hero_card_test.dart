// test/widget/features/partner/partner_heat_hero_card_test.dart
//
// PartnerHeatHeroCard unit + widget tests.
//
// Two layers:
//   1. PartnerHeatMessaging static mapping — pure function, boundary-tested.
//      Locks the deterministic "this is the spec" copy contract from
//      Eric's 2026-04-28 visual-polish brief: 5 buckets (null + 4 ranges)
//      × 2 strings (label + subtitle) + numberFor("--" / int.toString).
//   2. Widget render — verifies the card surfaces the mapping outputs and
//      handles the null-heat path without throwing on missing data.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vibesync/features/partner/presentation/widgets/partner_heat_hero_card.dart';

void main() {
  group('PartnerHeatMessaging.labelFor', () {
    test('null → 待分析', () {
      expect(PartnerHeatMessaging.labelFor(null), '待分析');
    });

    test('0..30 → 冷靜觀察 (boundary 0 / 30)', () {
      expect(PartnerHeatMessaging.labelFor(0), '冷靜觀察');
      expect(PartnerHeatMessaging.labelFor(15), '冷靜觀察');
      expect(PartnerHeatMessaging.labelFor(30), '冷靜觀察');
    });

    test('31..60 → 穩定互動 (boundary 31 / 60)', () {
      expect(PartnerHeatMessaging.labelFor(31), '穩定互動');
      expect(PartnerHeatMessaging.labelFor(45), '穩定互動');
      expect(PartnerHeatMessaging.labelFor(60), '穩定互動');
    });

    test('61..80 → 升溫中 (boundary 61 / 80)', () {
      expect(PartnerHeatMessaging.labelFor(61), '升溫中');
      expect(PartnerHeatMessaging.labelFor(75), '升溫中');
      expect(PartnerHeatMessaging.labelFor(80), '升溫中');
    });

    test('81..100 → 高互動熱度 (boundary 81 / 100)', () {
      expect(PartnerHeatMessaging.labelFor(81), '高互動熱度');
      expect(PartnerHeatMessaging.labelFor(95), '高互動熱度');
      expect(PartnerHeatMessaging.labelFor(100), '高互動熱度');
    });
  });

  group('PartnerHeatMessaging.subtitleFor', () {
    test('null → 新增或分析第一段互動後…', () {
      expect(
        PartnerHeatMessaging.subtitleFor(null),
        '新增或分析第一段互動後，這裡會顯示狀態',
      );
    });

    test('0..30 → 先觀察節奏…', () {
      expect(PartnerHeatMessaging.subtitleFor(0), '先觀察節奏，別急著推進');
      expect(PartnerHeatMessaging.subtitleFor(30), '先觀察節奏，別急著推進');
    });

    test('31..60 → 互動穩定…', () {
      expect(PartnerHeatMessaging.subtitleFor(31), '互動穩定，可以慢慢加深');
      expect(PartnerHeatMessaging.subtitleFor(60), '互動穩定，可以慢慢加深');
    });

    test('61..80 → 關係正在升溫中', () {
      expect(PartnerHeatMessaging.subtitleFor(61), '關係正在升溫中');
      expect(PartnerHeatMessaging.subtitleFor(80), '關係正在升溫中');
    });

    test('81..100 → 互動熱度很高…', () {
      expect(PartnerHeatMessaging.subtitleFor(81), '互動熱度很高，適合延續話題');
      expect(PartnerHeatMessaging.subtitleFor(100), '互動熱度很高，適合延續話題');
    });
  });

  group('PartnerHeatMessaging.numberFor', () {
    test('null → "--"', () {
      expect(PartnerHeatMessaging.numberFor(null), '--');
    });

    test('int → toString', () {
      expect(PartnerHeatMessaging.numberFor(0), '0');
      expect(PartnerHeatMessaging.numberFor(85), '85');
      expect(PartnerHeatMessaging.numberFor(100), '100');
    });
  });

  group('PartnerHeatHeroCard render', () {
    testWidgets('null heat → "--" + 待分析 + null subtitle', (t) async {
      await t.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: PartnerHeatHeroCard(heat: null),
        ),
      ));

      expect(find.text('--'), findsOneWidget);
      expect(find.text('待分析'), findsOneWidget);
      expect(
        find.text('新增或分析第一段互動後，這裡會顯示狀態'),
        findsOneWidget,
      );
    });

    testWidgets('heat=75 → "75" + 升溫中 + relational subtitle', (t) async {
      await t.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: PartnerHeatHeroCard(heat: 75),
        ),
      ));

      expect(find.text('75'), findsOneWidget);
      expect(find.text('升溫中'), findsOneWidget);
      expect(find.text('關係正在升溫中'), findsOneWidget);
    });

    testWidgets('heat=95 → "95" + 高互動熱度', (t) async {
      await t.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: PartnerHeatHeroCard(heat: 95),
        ),
      ));

      expect(find.text('95'), findsOneWidget);
      expect(find.text('高互動熱度'), findsOneWidget);
    });
  });
}
