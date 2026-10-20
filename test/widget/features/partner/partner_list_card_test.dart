import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vibesync/features/analysis/domain/entities/guide_v3_result.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/domain/extensions/partner_aggregates.dart';
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

Future<void> _pump(WidgetTester t, Widget child) async {
  await t.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: SizedBox(width: 400, child: child),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

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
      expect(
          find.descendant(of: pill, matching: find.text('黃燈')), findsOneWidget,
          reason: decision.wire);
      expect(find.descendant(of: pill, matching: find.text(status)),
          findsOneWidget,
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
    expect(
        find.descendant(of: pill, matching: find.text('輪到你回')), findsOneWidget);
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
}
