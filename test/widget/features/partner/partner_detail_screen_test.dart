// test/widget/features/partner/partner_detail_screen_test.dart
//
// Hermetic widget tests for PartnerDetailScreen.
// Overrides the three narrow providers; no Hive required.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/presentation/widgets/new_conversation_sheet.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/domain/extensions/partner_aggregates.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/partner/presentation/screens/partner_detail_screen.dart';
import 'package:vibesync/features/partner/presentation/widgets/partner_conversation_tile.dart';
import 'package:vibesync/features/partner/presentation/widgets/partner_radar_summary_card.dart';
import 'package:vibesync/features/partner/presentation/widgets/partner_traits_card.dart';

Partner _p() => Partner(
      id: 'p1',
      name: 'Alice',
      createdAt: DateTime(2026, 4, 20),
      updatedAt: DateTime(2026, 4, 20),
      ownerUserId: 'u1',
    );

Partner _other(String id, String name) => Partner(
      id: id,
      name: name,
      createdAt: DateTime(2026, 4, 20),
      updatedAt: DateTime(2026, 4, 20),
      ownerUserId: 'u1',
    );

Conversation _conv(String id) => Conversation(
      id: id,
      name: '第 $id 段',
      messages: const [],
      createdAt: DateTime(2026, 4, 20),
      updatedAt: DateTime(2026, 4, 20),
    );

void main() {
  testWidgets('⋮ menu: merge ENABLED, edit+delete still 即將推出', (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerByIdProvider('p1').overrideWith((_) => _p()),
        partnerAggregateProvider('p1')
            .overrideWith((_) => PartnerAggregateView.empty()),
        conversationsByPartnerProvider('p1')
            .overrideWith((_) => const <Conversation>[]),
        partnerListProvider
            .overrideWith((_) => [_p(), _other('q1', 'Bob')]),
      ],
      child: const MaterialApp(home: PartnerDetailScreen(partnerId: 'p1')),
    ));
    await t.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsOneWidget);

    await t.tap(find.byIcon(Icons.more_vert));
    await t.pumpAndSettle();

    expect(find.text('合併重複對象'), findsOneWidget);
    expect(find.text('編輯對象（即將推出）'), findsOneWidget);
    expect(find.text('刪除對象（即將推出）'), findsOneWidget);
  });

  testWidgets('⋮ menu: merge DISABLED when only one partner exists',
      (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerByIdProvider('p1').overrideWith((_) => _p()),
        partnerAggregateProvider('p1')
            .overrideWith((_) => PartnerAggregateView.empty()),
        conversationsByPartnerProvider('p1')
            .overrideWith((_) => const <Conversation>[]),
        partnerListProvider.overrideWith((_) => [_p()]),
      ],
      child: const MaterialApp(home: PartnerDetailScreen(partnerId: 'p1')),
    ));
    await t.pumpAndSettle();

    await t.tap(find.byIcon(Icons.more_vert));
    await t.pumpAndSettle();

    expect(find.text('合併重複對象（需至少 2 個對象）'), findsOneWidget);
    expect(find.text('合併重複對象'), findsNothing);
  });

  testWidgets('⋮ merge tap navigates to /partner/p1/merge', (t) async {
    final router = GoRouter(
      initialLocation: '/partner/p1',
      routes: [
        GoRoute(
          path: '/partner/:partnerId',
          builder: (_, state) => PartnerDetailScreen(
            partnerId: state.pathParameters['partnerId']!,
          ),
        ),
        GoRoute(
          path: '/partner/:partnerId/merge',
          builder: (_, state) => Scaffold(
            body: Text('merge-stub-${state.pathParameters['partnerId']}'),
          ),
        ),
      ],
    );

    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerByIdProvider('p1').overrideWith((_) => _p()),
        partnerAggregateProvider('p1')
            .overrideWith((_) => PartnerAggregateView.empty()),
        conversationsByPartnerProvider('p1')
            .overrideWith((_) => const <Conversation>[]),
        partnerListProvider
            .overrideWith((_) => [_p(), _other('q1', 'Bob')]),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await t.pumpAndSettle();

    await t.tap(find.byIcon(Icons.more_vert));
    await t.pumpAndSettle();
    await t.tap(find.text('合併重複對象'));
    await t.pumpAndSettle();

    expect(find.text('merge-stub-p1'), findsOneWidget);
  });

  testWidgets('renders traits card + radar summary card + new-conversation FAB',
      (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerByIdProvider('p1').overrideWith((_) => _p()),
        partnerAggregateProvider('p1')
            .overrideWith((_) => PartnerAggregateView.empty()),
        conversationsByPartnerProvider('p1')
            .overrideWith((_) => const <Conversation>[]),
      ],
      child: const MaterialApp(home: PartnerDetailScreen(partnerId: 'p1')),
    ));
    await t.pumpAndSettle();

    expect(find.byType(PartnerTraitsCard), findsOneWidget);
    expect(find.byType(PartnerRadarSummaryCard), findsOneWidget);
    expect(find.text('+ 新增對話'), findsOneWidget);
  });

  testWidgets('new-conversation sheet receives current partnerId', (t) async {
    // Default flutter_test surface is 800x600 → modal sheet height 289.5px,
    // sheet content needs ~291px → 1.5px RenderFlex overflow fails the test.
    // Use a phone-realistic size so the sheet has room to render.
    await t.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));

    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerByIdProvider('p1').overrideWith((_) => _p()),
        partnerAggregateProvider('p1')
            .overrideWith((_) => PartnerAggregateView.empty()),
        conversationsByPartnerProvider('p1')
            .overrideWith((_) => const <Conversation>[]),
      ],
      child: const MaterialApp(home: PartnerDetailScreen(partnerId: 'p1')),
    ));
    await t.pumpAndSettle();

    await t.tap(find.byType(FloatingActionButton));
    await t.pumpAndSettle();

    final sheet =
        t.widget<NewConversationSheet>(find.byType(NewConversationSheet));
    expect(sheet.partnerId, 'p1');
  });

  testWidgets('empty conversation list shows hint text', (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerByIdProvider('p1').overrideWith((_) => _p()),
        partnerAggregateProvider('p1')
            .overrideWith((_) => PartnerAggregateView.empty()),
        conversationsByPartnerProvider('p1')
            .overrideWith((_) => const <Conversation>[]),
      ],
      child: const MaterialApp(home: PartnerDetailScreen(partnerId: 'p1')),
    ));
    await t.pumpAndSettle();
    expect(find.textContaining('尚未有對話'), findsOneWidget);
  });

  testWidgets('renders one tile per conversation when list non-empty',
      (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerByIdProvider('p1').overrideWith((_) => _p()),
        partnerAggregateProvider('p1')
            .overrideWith((_) => PartnerAggregateView.empty()),
        conversationsByPartnerProvider('p1')
            .overrideWith((_) => [_conv('a'), _conv('b')]),
      ],
      child: const MaterialApp(home: PartnerDetailScreen(partnerId: 'p1')),
    ));
    await t.pumpAndSettle();
    expect(find.byType(PartnerConversationTile), findsNWidgets(2),
        reason:
            'Tile titles no longer carry conversation.name (per "人 vs 互動" '
            'mental-model fix); verify by widget count instead.');
  });

  testWidgets('tile ⋮ → 改派 opens reassign picker excluding current partner',
      (t) async {
    await t.binding.setSurfaceSize(const Size(400, 1200));
    addTearDown(() => t.binding.setSurfaceSize(null));

    final attachedConv = Conversation(
      id: 'c1',
      name: '第 a 段',
      messages: const [],
      createdAt: DateTime(2026, 4, 20),
      updatedAt: DateTime(2026, 4, 20),
      partnerId: 'p1',
    );

    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerByIdProvider('p1').overrideWith((_) => _p()),
        partnerAggregateProvider('p1')
            .overrideWith((_) => PartnerAggregateView.empty()),
        conversationsByPartnerProvider('p1')
            .overrideWith((_) => [attachedConv]),
        partnerListProvider
            .overrideWith((_) => [_p(), _other('q1', 'Bob')]),
      ],
      child: const MaterialApp(home: PartnerDetailScreen(partnerId: 'p1')),
    ));
    await t.pumpAndSettle();

    // Header ⋮ is also Icons.more_vert — scope to the tile.
    final tileMenu = find.descendant(
      of: find.byType(PartnerConversationTile),
      matching: find.byIcon(Icons.more_vert),
    );
    expect(tileMenu, findsOneWidget);
    await t.tap(tileMenu);
    await t.pumpAndSettle();

    await t.tap(find.text('改派到其他對象'));
    await t.pumpAndSettle();

    // Reassign sheet rendered: Bob visible (Alice = p1 excluded from picker;
    // header still shows "Alice", so we scope to the picker subtree).
    expect(find.text('Bob'), findsOneWidget);
    final pickerSubtree = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.text('Alice'),
    );
    expect(pickerSubtree, findsNothing);
  });

  testWidgets('partner missing (deleted/merged) shows fallback', (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerByIdProvider('ghost').overrideWith((_) => null),
        partnerAggregateProvider('ghost')
            .overrideWith((_) => PartnerAggregateView.empty()),
        conversationsByPartnerProvider('ghost')
            .overrideWith((_) => const <Conversation>[]),
      ],
      child: const MaterialApp(home: PartnerDetailScreen(partnerId: 'ghost')),
    ));
    await t.pumpAndSettle();
    expect(find.textContaining('找不到對象'), findsOneWidget);
  });
}
