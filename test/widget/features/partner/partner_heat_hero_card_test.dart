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
//      主數字現在是 0→heat 的跑動（CountUpText），所以 render 斷言一律先把
//      畫面帶到終態再看終值；跑動本身另外鎖在第 3 組。
//      注意：卡片右側的 HeatOrb 是持續呼吸的光球，pumpAndSettle 永遠不會收斂。
//      只看終態的組別用 motionFreeApp（等價於使用者開了「減少動態效果」），
//      要驗證跑動過程的組別則用明確的 pump(duration)。
//   3. Count-up — 開場從 0 起跑、收斂停在 heat；null 沒有東西可跑；
//      animate:false（捲動回收後重建）不重播。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vibesync/features/partner/presentation/widgets/partner_heat_hero_card.dart';

import '../../../helpers/motion_free_app.dart';

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

    test('81..90 → 高度投入；legacy 超界值仍歸入同段', () {
      expect(PartnerHeatMessaging.labelFor(81), '高度投入');
      expect(PartnerHeatMessaging.labelFor(90), '高度投入');
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

    test('81..90 → 這次文字訊號呈現高度投入', () {
      expect(PartnerHeatMessaging.subtitleFor(81), '這次文字訊號呈現高度投入');
      expect(PartnerHeatMessaging.subtitleFor(90), '這次文字訊號呈現高度投入');
    });
  });

  group('PartnerHeatMessaging.numberFor', () {
    test('null → "--"', () {
      expect(PartnerHeatMessaging.numberFor(null), '--');
    });

    test('int → 0–90 可見範圍，legacy 100 clamp 成 90', () {
      expect(PartnerHeatMessaging.numberFor(0), '0');
      expect(PartnerHeatMessaging.numberFor(85), '85');
      expect(PartnerHeatMessaging.numberFor(100), '90');
    });
  });

  group('PartnerHeatHeroCard render', () {
    testWidgets('null heat → "--" + 待分析 + null subtitle', (t) async {
      await t.pumpWidget(motionFreeApp(
        home: const Scaffold(
          body: PartnerHeatHeroCard(heat: null),
        ),
      ));

      await t.pumpAndSettle();

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
      await t.pumpWidget(motionFreeApp(
        home: const Scaffold(
          body: PartnerHeatHeroCard(heat: 75),
        ),
      ));
      await t.pumpAndSettle();

      expect(find.text('75'), findsOneWidget);
      expect(find.text('投入明顯'), findsOneWidget);
      expect(find.text('這次有多個明顯的投入訊號'), findsOneWidget);
    });

    testWidgets('legacy heat=95 → 可見滿分 "90" + 高度投入', (t) async {
      await t.pumpWidget(motionFreeApp(
        home: const Scaffold(
          body: PartnerHeatHeroCard(heat: 95),
        ),
      ));
      await t.pumpAndSettle();

      expect(find.text('90'), findsOneWidget);
      expect(find.text('95'), findsNothing);
      expect(find.text('高度投入'), findsOneWidget);
    });
  });

  group('PartnerHeatHeroCard 數字跑動', () {
    testWidgets('開場從 0 起跑，收斂後停在 heat', (t) async {
      await t.pumpWidget(const MaterialApp(
        home: Scaffold(body: PartnerHeatHeroCard(heat: 36)),
      ));

      // 第一格是 0：這就是「打開頁面看到數字從 0 衝上來」的起點。
      expect(find.text('0'), findsOneWidget);
      expect(find.text('36'), findsNothing);

      await t.pump(const Duration(milliseconds: 300));
      final mid = int.parse(t.widget<Text>(_numberFinder()).data!);
      expect(mid, greaterThan(0));
      expect(mid, lessThan(36));

      // 不能用 pumpAndSettle：這一組要讓動畫真的跑，而卡片右側的 HeatOrb 是
      // 持續呼吸的光球，永遠不會收斂。改用明確時長把數字跑完。
      await t.pump(const Duration(milliseconds: 1400));
      expect(find.text('36'), findsOneWidget);
    });

    testWidgets('null heat 沒有東西可以跑，直接顯示 --', (t) async {
      await t.pumpWidget(const MaterialApp(
        home: Scaffold(body: PartnerHeatHeroCard(heat: null)),
      ));

      expect(find.text('--'), findsOneWidget);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('animate: false（捲動回收後重建）直接是終值，不重播', (t) async {
      await t.pumpWidget(const MaterialApp(
        home: Scaffold(body: PartnerHeatHeroCard(heat: 36, animate: false)),
      ));

      expect(find.text('36'), findsOneWidget);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('關閉動畫（reduce motion）直接落在終值', (t) async {
      await t.pumpWidget(const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(body: PartnerHeatHeroCard(heat: 36)),
        ),
      ));

      expect(find.text('36'), findsOneWidget);
      expect(find.text('0'), findsNothing);
    });
  });
}

/// 卡片裡唯一一個純數字的 Text（其他都是中文字串）。
Finder _numberFinder() => find.byWidgetPredicate(
      (w) => w is Text && w.data != null && int.tryParse(w.data!) != null,
    );
