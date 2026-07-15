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

    test('0..30 → 投入偏低 (boundary 0 / 30)', () {
      expect(PartnerHeatMessaging.labelFor(0), '投入偏低');
      expect(PartnerHeatMessaging.labelFor(15), '投入偏低');
      expect(PartnerHeatMessaging.labelFor(30), '投入偏低');
    });

    test('31..60 → 有在回應 (boundary 31 / 60)', () {
      expect(PartnerHeatMessaging.labelFor(31), '有在回應');
      expect(PartnerHeatMessaging.labelFor(45), '有在回應');
      expect(PartnerHeatMessaging.labelFor(60), '有在回應');
    });

    test('61..80 → 投入明顯 (boundary 61 / 80)', () {
      expect(PartnerHeatMessaging.labelFor(61), '投入明顯');
      expect(PartnerHeatMessaging.labelFor(75), '投入明顯');
      expect(PartnerHeatMessaging.labelFor(80), '投入明顯');
    });

    test('81..100 → 高度投入 (boundary 81 / 100)', () {
      expect(PartnerHeatMessaging.labelFor(81), '高度投入');
      expect(PartnerHeatMessaging.labelFor(95), '高度投入');
      expect(PartnerHeatMessaging.labelFor(100), '高度投入');
    });
  });

  group('PartnerHeatMessaging.subtitleFor', () {
    test('null → 分析第一段互動後…', () {
      expect(
        PartnerHeatMessaging.subtitleFor(null),
        '分析第一段互動後，這裡會顯示對方這次的投入度',
      );
    });

    test('0..30 → 這次文字訊號較少', () {
      expect(PartnerHeatMessaging.subtitleFor(0), '這次文字訊號較少');
      expect(PartnerHeatMessaging.subtitleFor(30), '這次文字訊號較少');
    });

    test('31..60 → 這次有回應…', () {
      expect(PartnerHeatMessaging.subtitleFor(31), '這次有回應，投入訊號普通');
      expect(PartnerHeatMessaging.subtitleFor(60), '這次有回應，投入訊號普通');
    });

    test('61..80 → 這次有多個明顯的投入訊號', () {
      expect(PartnerHeatMessaging.subtitleFor(61), '這次有多個明顯的投入訊號');
      expect(PartnerHeatMessaging.subtitleFor(80), '這次有多個明顯的投入訊號');
    });

    test('81..100 → 這次文字訊號呈現高度投入', () {
      expect(PartnerHeatMessaging.subtitleFor(81), '這次文字訊號呈現高度投入');
      expect(PartnerHeatMessaging.subtitleFor(100), '這次文字訊號呈現高度投入');
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
        find.text('分析第一段互動後，這裡會顯示對方這次的投入度'),
        findsOneWidget,
      );
      expect(find.text('對方這次的投入度'), findsOneWidget);
      expect(
        find.text('只反映這次互動中的文字訊號，不代表關係進度。'),
        findsOneWidget,
      );
    });

    testWidgets('heat=75 → "75" + 投入明顯 + scoped subtitle', (t) async {
      await t.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: PartnerHeatHeroCard(heat: 75),
        ),
      ));

      expect(find.text('75'), findsOneWidget);
      expect(find.text('投入明顯'), findsOneWidget);
      expect(find.text('這次有多個明顯的投入訊號'), findsOneWidget);
    });

    testWidgets('heat=95 → "95" + 高度投入', (t) async {
      await t.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: PartnerHeatHeroCard(heat: 95),
        ),
      ));

      expect(find.text('95'), findsOneWidget);
      expect(find.text('高度投入'), findsOneWidget);
    });
  });
}
