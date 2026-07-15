import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/domain/extensions/partner_aggregates.dart';
import 'package:vibesync/features/partner/presentation/widgets/partner_list_card.dart';

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
}) =>
    PartnerAggregateView(
      unionInterests: interests,
      unionTraits: traits,
      unionNotes: null,
      latestHeat: heat,
      totalRounds: rounds,
      totalMessages: 0,
      lastInteraction: lastInteraction,
    );

Future<void> _pump(WidgetTester t, Widget child) async {
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SizedBox(width: 400, child: child),
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('renders core visual pieces given Partner + aggregate',
      (t) async {
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
  });

  testWidgets('avatar fallback keeps names readable across languages',
      (t) async {
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

  testWidgets('falls back to a pending-analysis pill when latestHeat is null',
      (t) async {
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
  });

  testWidgets('keeps at least one trait when both interests and traits exist',
      (t) async {
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
