// test/widget/features/partner/partner_list_card_test.dart
//
// PartnerListCard 視覺還原 5 件套 widget tests (Phase 4 Task 2).
//
// Card stays pure render — receives Partner + already-computed
// PartnerAggregateView via constructor (lifted-aggregate API).
// No ProviderScope override needed because the card never `ref.watch`es.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vibesync/core/theme/app_colors.dart';
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
  testWidgets(
      'renders 5 visual pieces given Partner + non-empty aggregate',
      (t) async {
    await _pump(
      t,
      PartnerListCard(
        partner: _p('a', 'Alice'),
        aggregate: _agg(
          interests: const ['咖啡'],
          traits: const ['溫柔'],
          heat: 70,
          rounds: 3,
          lastInteraction: DateTime(2026, 1, 5),
        ),
        onTap: () {},
        onDelete: () {},
      ),
    );

    // Piece 1: avatar — first character of name
    expect(find.text('A'), findsOneWidget);
    // Piece 2: name
    expect(find.text('Alice'), findsOneWidget);
    // Piece 3: relative date — > 7 days ago, fixed past date renders MM/dd
    expect(find.text('01/05'), findsOneWidget);
    // Piece 4: heat indicator (hot range emoji + number)
    expect(find.text('🔥'), findsOneWidget);
    expect(find.text('70'), findsOneWidget);
    // Piece 5: tag preview joined by " · "
    expect(find.text('咖啡 · 溫柔'), findsOneWidget);
    // Piece 6: trailing delete icon
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
  });

  testWidgets('falls back to "🌡️ 待分析" when latestHeat is null', (t) async {
    await _pump(
      t,
      PartnerListCard(
        partner: _p('a', 'Alice'),
        aggregate: _agg(),
        onTap: () {},
      ),
    );

    expect(find.text('🌡️'), findsOneWidget);
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

    // Interleave: [i0, t0, i1] — cap at 3 reached after adding i1.
    expect(find.text('i0 · t0 · i1'), findsOneWidget);
  });

  testWidgets(
      'keeps at least one trait when both interests and traits exist',
      (t) async {
    await _pump(
      t,
      PartnerListCard(
        partner: _p('a', 'Alice'),
        aggregate: _agg(
          interests: const ['咖啡', '電影', '健身'],
          traits: const ['溫柔', '幽默'],
        ),
        onTap: () {},
      ),
    );

    // Even with 3 interests, the interleave guarantees t0 lands in the preview.
    final preview = find.text('咖啡 · 溫柔 · 電影');
    expect(preview, findsOneWidget);
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

  testWidgets('does not render delete icon when onDelete is null',
      (t) async {
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

  testWidgets('uses glass hint color for "待分析" fallback', (t) async {
    await _pump(
      t,
      PartnerListCard(
        partner: _p('a', 'Alice'),
        aggregate: _agg(),
        onTap: () {},
      ),
    );
    final waiting = t.widget<Text>(find.text('待分析'));
    expect(waiting.style?.color, AppColors.glassTextHint);
  });
}
