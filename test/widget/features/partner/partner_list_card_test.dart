import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vibesync/core/theme/app_typography.dart';
import 'package:vibesync/features/analysis/domain/entities/guide_v3_result.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/domain/extensions/partner_aggregates.dart';
import 'package:vibesync/features/partner/presentation/widgets/japanese_led_signal.dart';
import 'package:vibesync/features/partner/presentation/widgets/partner_list_card.dart';
import 'package:vibesync/shared/widgets/brand/liquid_motion_frame.dart';

Partner _p(String id, String name) => Partner(
      id: id,
      name: name,
      createdAt: DateTime(2026, 4, 20),
      updatedAt: DateTime(2026, 4, 20),
      ownerUserId: 'u1',
    );

PartnerAggregateView _agg({
  List<String> interests = const [],
  List<String> traits = const [],
  int? heat,
  int rounds = 0,
  DateTime? lastInteraction,
  bool latestIsGuideV3 = false,
  PartnerGuideV3Signals? signals,
}) =>
    PartnerAggregateView(
      unionInterests: interests,
      unionTraits: traits,
      unionNotes: null,
      latestHeat: heat,
      totalRounds: rounds,
      totalMessages: 0,
      lastInteraction: lastInteraction,
      latestIsGuideV3: latestIsGuideV3,
      latestGuideV3Signals: signals,
    );

Future<void> _pump(
  WidgetTester t,
  Widget child, {
  double width = 400,
  double textScale = 1.0,
}) async {
  await t.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(
            disableAnimations: true,
            textScaler: TextScaler.linear(textScale),
          ),
          child: SizedBox(width: width, child: child),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

/// 最近一次是 v3 的對象卡；燈號與決定分開給（燈色和要不要回是兩套資料）。
Widget _v3Card({GuideV3Light? light, required GuideV3Decision decision}) =>
    PartnerListCard(
      partner: _p('a', 'Alice'),
      aggregate: _agg(
        interests: const ['咖啡'],
        latestIsGuideV3: true,
        signals: PartnerGuideV3Signals(decision: decision, light: light),
      ),
      onTap: () {},
      onDelete: () {},
    );

/// 改版前（ed94a198）燈號膠囊的外框：上下 4 內距＋1 邊框，包一行 12 號粗體。
/// 用來確認拿掉膠囊後那一列的高度沒變（卡片其他東西不會移動）。
Widget _legacyPill(String status) => Material(
      type: MaterialType.transparency,
      child: Container(
        key: const ValueKey('legacy-pill'),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white),
        ),
        child: Text(
          status,
          style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
    );

final _statusRow = find.byKey(const ValueKey('partner-card-v3-status'));

void main() {
  testWidgets('renders core visual pieces given Partner + aggregate', (
    t,
  ) async {
    await _pump(
      t,
      PartnerListCard(
        partner: _p('a', 'Alice'),
        aggregate: _agg(
          interests: const ['coffee'],
          traits: const ['bold'],
          heat: 70,
          rounds: 3,
          lastInteraction: DateTime(2026, 1, 5),
        ),
        onTap: () {},
        onDelete: () {},
      ),
    );

    expect(find.text('AL'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('01/05'), findsOneWidget);
    expect(find.byIcon(Icons.local_fire_department_rounded), findsOneWidget);
    expect(find.text('本次投入 70'), findsOneWidget);
    expect(find.text('coffee · bold'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    expect(find.byType(LiquidMotionFrame), findsOneWidget);
    expect(
      find.byKey(const ValueKey('partner-avatar-liquid-a')),
      findsOneWidget,
    );
  });

  testWidgets('avatar fallback keeps names readable across languages', (
    t,
  ) async {
    await _pump(
      t,
      Column(
        children: [
          PartnerListCard(
            partner: _p('a', '小美同學'),
            aggregate: _agg(),
            onTap: () {},
          ),
          PartnerListCard(
            partner: _p('b', 'Bruce Chiang'),
            aggregate: _agg(),
            onTap: () {},
          ),
          PartnerListCard(
            partner: _p('c', 'testa'),
            aggregate: _agg(),
            onTap: () {},
          ),
        ],
      ),
    );

    expect(find.text('小美'), findsOneWidget);
    expect(find.text('小美同學'), findsOneWidget);
    expect(find.text('BC'), findsOneWidget);
    expect(find.text('TE'), findsOneWidget);
  });

  testWidgets('falls back to a pending-analysis pill when latestHeat is null', (
    t,
  ) async {
    await _pump(
      t,
      PartnerListCard(
        partner: _p('a', 'Alice'),
        aggregate: _agg(),
        onTap: () {},
      ),
    );

    expect(find.byIcon(Icons.insights_rounded), findsOneWidget);
    expect(find.text('待分析'), findsOneWidget);
  });

  testWidgets('v3 分析過的對象不顯示熱度膠囊，也不寫「待分析」', (t) async {
    await _pump(
      t,
      PartnerListCard(
        partner: _p('a', 'Alice'),
        aggregate: _agg(
          interests: const ['咖啡'],
          latestIsGuideV3: true,
        ),
        onTap: () {},
      ),
    );

    expect(find.text('待分析'), findsNothing);
    expect(find.textContaining('本次投入'), findsNothing);
    expect(find.byIcon(Icons.insights_rounded), findsNothing);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('咖啡'), findsOneWidget);
  });

  testWidgets('v3 最新一次的決定變成短狀態，放在燈號旁邊；不分方案', (t) async {
    const cases = {
      GuideV3Decision.send: '輪到你回',
      GuideV3Decision.close: '輪到你回',
      GuideV3Decision.hold: '先等她',
      GuideV3Decision.stop: '先停',
    };
    for (final MapEntry(key: decision, value: status) in cases.entries) {
      await _pump(
        t,
        PartnerListCard(
          partner: _p('a', 'Alice'),
          aggregate: _agg(
            latestIsGuideV3: true,
            signals: PartnerGuideV3Signals(
              decision: decision,
              light: GuideV3Light.yellow,
            ),
          ),
          onTap: () {},
        ),
      );

      final pill = find.byKey(const ValueKey('partner-card-v3-status'));
      expect(pill, findsOneWidget, reason: decision.wire);
      // 燈色與狀態合成一句（Bruce 2026-10-21 燈號標籤規格），旁邊的信號機亮黃燈。
      expect(find.descendant(of: pill, matching: find.text('黃燈 $status')),
          findsOneWidget,
          reason: decision.wire);
      expect(
          t
              .widget<JapaneseLedSignal>(find.descendant(
                  of: pill, matching: find.byType(JapaneseLedSignal)))
              .light,
          GuideV3Light.yellow,
          reason: decision.wire);
      expect(find.text('待分析'), findsNothing);
      expect(find.textContaining('本次投入'), findsNothing);
    }
  });

  testWidgets('v3 帶了熱度（Bruce 2026-10-19 路線二）：首頁卡照樣放燈號＋短狀態，不換回熱度膠囊', (t) async {
    await _pump(
      t,
      PartnerListCard(
        partner: _p('a', 'Alice'),
        aggregate: _agg(
          heat: 65,
          latestIsGuideV3: true,
          signals: const PartnerGuideV3Signals(
            decision: GuideV3Decision.send,
            light: GuideV3Light.green,
          ),
        ),
        onTap: () {},
      ),
    );

    final pill = find.byKey(const ValueKey('partner-card-v3-status'));
    expect(find.descendant(of: pill, matching: find.text('綠燈 輪到你回')),
        findsOneWidget);
    expect(find.textContaining('本次投入'), findsNothing);
  });

  testWidgets('v3 燈號讀不懂：只寫狀態；關心什麼都不多放', (t) async {
    await _pump(
      t,
      PartnerListCard(
        partner: _p('a', 'Alice'),
        aggregate: _agg(
          latestIsGuideV3: true,
          signals: const PartnerGuideV3Signals(decision: GuideV3Decision.send),
        ),
        onTap: () {},
      ),
    );
    expect(find.text('輪到你回'), findsOneWidget);
    expect(find.textContaining('燈'), findsNothing);
    // 不猜顏色、不畫三顆全暗的信號機；字用中性的白。
    expect(find.byType(JapaneseLedSignal), findsNothing);
    expect(
      t.widget<Text>(find.text('輪到你回')).style?.color,
      Colors.white.withValues(alpha: 0.88),
    );

    await _pump(
      t,
      PartnerListCard(
        partner: _p('a', 'Alice'),
        aggregate: _agg(
          latestIsGuideV3: true,
          signals: const PartnerGuideV3Signals(decision: GuideV3Decision.care),
        ),
        onTap: () {},
      ),
    );
    expect(find.byKey(const ValueKey('partner-card-v3-status')), findsNothing);
    expect(find.text('待分析'), findsNothing);
    expect(find.text('Alice'), findsOneWidget);
  });

  testWidgets(
    'shows interleaved interests+traits joined by " · " as preview, capped at 3',
    (t) async {
      await _pump(
        t,
        PartnerListCard(
          partner: _p('a', 'Alice'),
          aggregate: _agg(
            interests: const ['i0', 'i1', 'i2', 'i3', 'i4'],
            traits: const ['t0', 't1', 't2', 't3', 't4'],
            heat: 50,
          ),
          onTap: () {},
        ),
      );

      expect(find.text('i0 · t0 · i1'), findsOneWidget);
    },
  );

  testWidgets('keeps at least one trait when both interests and traits exist', (
    t,
  ) async {
    await _pump(
      t,
      PartnerListCard(
        partner: _p('a', 'Alice'),
        aggregate: _agg(
          interests: const ['food', 'travel', 'film'],
          traits: const ['active', 'warm'],
        ),
        onTap: () {},
      ),
    );

    expect(find.text('food · active · travel'), findsOneWidget);
  });

  testWidgets('tap delete fires onDelete callback', (t) async {
    var fired = 0;
    await _pump(
      t,
      PartnerListCard(
        partner: _p('a', 'Alice'),
        aggregate: _agg(),
        onTap: () {},
        onDelete: () => fired++,
      ),
    );

    await t.tap(find.byIcon(Icons.delete_outline));
    await t.pumpAndSettle();
    expect(fired, 1);
  });

  testWidgets('does not render delete icon when onDelete is null', (t) async {
    await _pump(
      t,
      PartnerListCard(
        partner: _p('a', 'Alice'),
        aggregate: _agg(),
        onTap: () {},
      ),
    );

    expect(find.byIcon(Icons.delete_outline), findsNothing);
  });

  testWidgets('uses premium pending-analysis text styling', (t) async {
    await _pump(
      t,
      PartnerListCard(
        partner: _p('a', 'Alice'),
        aggregate: _agg(),
        onTap: () {},
      ),
    );

    final waiting = t.widget<Text>(find.text('待分析'));
    expect(waiting.style?.color, Colors.white.withValues(alpha: 0.70));
    expect(waiting.style?.fontWeight, FontWeight.w700);
  });

  group('v3 燈號標籤（Bruce 2026-10-21 燈號標籤規格）', () {
    testWidgets('三種標準案例：信號機亮對的燈，整句同色霓虹字', (t) async {
      const cases = [
        (GuideV3Light.yellow, GuideV3Decision.send, '黃燈 輪到你回'),
        (GuideV3Light.green, GuideV3Decision.send, '綠燈 輪到你回'),
        (GuideV3Light.red, GuideV3Decision.hold, '紅燈 先等她'),
      ];
      for (final (light, decision, text) in cases) {
        await _pump(t, _v3Card(light: light, decision: decision));

        final label = t.widget<Text>(
          find.descendant(of: _statusRow, matching: find.text(text)),
        );
        final tone = partnerSignalColor(light);
        expect(label.style?.color, tone, reason: text);
        expect(label.style?.fontSize, 13, reason: text);
        expect(label.style?.fontWeight, FontWeight.w700, reason: text);
        final shadows = label.style!.shadows!;
        expect(shadows, hasLength(2), reason: text);
        for (final shadow in shadows) {
          expect(shadow.color.withValues(alpha: 1), tone, reason: text);
          expect(shadow.offset, Offset.zero, reason: text);
        }
        expect(label.maxLines, 1, reason: text);
        expect(label.overflow, TextOverflow.ellipsis, reason: text);

        final signal = find.descendant(
          of: _statusRow,
          matching: find.byType(JapaneseLedSignal),
        );
        expect(t.widget<JapaneseLedSignal>(signal).light, light, reason: text);
        expect(t.getSize(signal), const Size(42, 16), reason: text);
      }
    });

    testWidgets('燈色和要不要回分開算：資料允許的其他組合照資料顯示', (t) async {
      const cases = [
        (GuideV3Light.yellow, GuideV3Decision.hold, '黃燈 先等她'),
        (GuideV3Light.green, GuideV3Decision.stop, '綠燈 先停'),
        (GuideV3Light.red, GuideV3Decision.close, '紅燈 輪到你回'),
      ];
      for (final (light, decision, text) in cases) {
        await _pump(t, _v3Card(light: light, decision: decision));
        expect(
          find.descendant(of: _statusRow, matching: find.text(text)),
          findsOneWidget,
          reason: text,
        );
        expect(
          t.widget<JapaneseLedSignal>(find.byType(JapaneseLedSignal)).light,
          light,
          reason: text,
        );
      }
    });

    testWidgets('沒有膠囊：無底色無框；信號機對齊姓名左緣，字在右邊 6、垂直置中', (t) async {
      await _pump(
        t,
        _v3Card(light: GuideV3Light.yellow, decision: GuideV3Decision.send),
      );

      expect(
        find.descendant(of: _statusRow, matching: find.byType(DecoratedBox)),
        findsNothing,
      );
      final signal = t.getRect(find.byType(JapaneseLedSignal));
      final label = t.getRect(find.text('黃燈 輪到你回'));
      final row = t.getRect(_statusRow);
      expect(signal.left, t.getTopLeft(find.text('Alice')).dx);
      expect(label.left, signal.right + 6);
      expect(signal.center.dy, moreOrLessEquals(row.center.dy));
      expect(label.center.dy, moreOrLessEquals(row.center.dy));
    });

    testWidgets('那一列的高度跟原本膠囊一樣（字縮放 1.0／1.3／2.0，燈號讀不懂也一樣）', (t) async {
      for (final scale in const [1.0, 1.3, 2.0]) {
        for (final light in const [GuideV3Light.yellow, null]) {
          await _pump(
            t,
            Column(
              children: [
                _v3Card(light: light, decision: GuideV3Decision.send),
                _legacyPill('輪到你回'),
              ],
            ),
            textScale: scale,
          );
          expect(
            t.getSize(_statusRow).height,
            t.getSize(find.byKey(const ValueKey('legacy-pill'))).height,
            reason: 'scale $scale, light $light',
          );
        }
      }
    });

    testWidgets('VoiceOver 念成一句；信號機是裝飾，不另外念', (t) async {
      final semantics = t.ensureSemantics();
      await _pump(
        t,
        _v3Card(light: GuideV3Light.yellow, decision: GuideV3Decision.send),
      );

      final node = t.getSemantics(find.text('黃燈 輪到你回'));
      expect(node.label, contains('黃燈 輪到你回'));
      expect('黃燈'.allMatches(node.label), hasLength(1));
      expect(find.bySemanticsLabel(RegExp(r'^黃燈$')), findsNothing);
      expect(find.bySemanticsLabel(RegExp(r'^輪到你回$')), findsNothing);
      semantics.dispose();
    });

    testWidgets('窄卡與大字：維持一行、放不下就省略，不溢出也不加高', (t) async {
      // 288 = 320 寬手機扣掉首頁左右各 16 邊距後的卡片寬。
      for (final scale in const [1.0, 1.3, 2.0]) {
        await _pump(
          t,
          _v3Card(light: GuideV3Light.yellow, decision: GuideV3Decision.send),
          width: 288,
          textScale: scale,
        );
        expect(t.takeException(), isNull, reason: 'scale $scale');
        final label = t.getRect(find.text('黃燈 輪到你回'));
        final row = t.getRect(_statusRow);
        expect(label.height, moreOrLessEquals(13 * scale * 1.2, epsilon: 1),
            reason: 'scale $scale');
        expect(label.height, lessThanOrEqualTo(row.height),
            reason: 'scale $scale');
        expect(label.right, lessThanOrEqualTo(row.right + 0.01),
            reason: 'scale $scale');
      }
    });
  });
}
