// test/widget/features/partner/partner_list_screen_test.dart
//
// Hermetic widget tests for PartnerListScreen.
//
// Card receives an already-computed PartnerAggregateView (lifted-aggregate
// API) so tests only need: one override for partnerListProvider plus one
// override per partner id for partnerAggregateProvider — not a per-partner
// override per row. (Codex r1 P1.3b)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/domain/extensions/partner_aggregates.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/partner/presentation/screens/partner_list_screen.dart';

Partner _p(String id, String name) => Partner(
      id: id,
      name: name,
      createdAt: DateTime(2026, 4, 20),
      updatedAt: DateTime(2026, 4, 20),
      ownerUserId: 'u1',
    );

PartnerAggregateView _agg({int rounds = 0, int? heat}) => PartnerAggregateView(
      unionInterests: const [],
      unionTraits: const [],
      unionNotes: null,
      latestHeat: heat,
      totalRounds: rounds,
      totalMessages: 0,
      lastInteraction: null,
    );

void main() {
  testWidgets('empty state: shows "還沒有對象" hint', (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerListProvider.overrideWith((_) => const <Partner>[]),
      ],
      child: const MaterialApp(home: Scaffold(body: PartnerListScreen())),
    ));
    await t.pumpAndSettle();
    expect(find.textContaining('還沒有對象'), findsOneWidget);
  });

  testWidgets('renders one PartnerListCard per partner with aggregate',
      (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerListProvider
            .overrideWith((_) => [_p('a', 'Alice'), _p('b', 'Bob')]),
        partnerAggregateProvider('a')
            .overrideWith((_) => _agg(rounds: 3, heat: 70)),
        partnerAggregateProvider('b').overrideWith((_) => _agg(rounds: 1)),
      ],
      child: const MaterialApp(home: Scaffold(body: PartnerListScreen())),
    ));
    await t.pumpAndSettle();
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.textContaining('3 段對話'), findsOneWidget);
    expect(find.textContaining('1 段對話'), findsOneWidget);
  });

  testWidgets('list preserves order from partnerListProvider', (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerListProvider
            .overrideWith((_) => [_p('z', 'Zoe'), _p('a', 'Alice')]),
        partnerAggregateProvider('z').overrideWith((_) => _agg()),
        partnerAggregateProvider('a').overrideWith((_) => _agg()),
      ],
      child: const MaterialApp(home: Scaffold(body: PartnerListScreen())),
    ));
    await t.pumpAndSettle();
    final zoe = t.getTopLeft(find.text('Zoe'));
    final alice = t.getTopLeft(find.text('Alice'));
    expect(zoe.dy < alice.dy, isTrue, reason: 'Zoe must render above Alice');
  });
}
