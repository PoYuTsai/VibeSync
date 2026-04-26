// test/widget/features/partner/partner_detail_screen_test.dart
//
// Hermetic widget tests for PartnerDetailScreen.
// Overrides the three narrow providers; no Hive required.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/presentation/widgets/new_conversation_sheet.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/domain/extensions/partner_aggregates.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/partner/presentation/screens/partner_detail_screen.dart';
import 'package:vibesync/features/partner/presentation/widgets/partner_radar_summary_card.dart';
import 'package:vibesync/features/partner/presentation/widgets/partner_traits_card.dart';

Partner _p() => Partner(
      id: 'p1',
      name: 'Alice',
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
  testWidgets('header shows partner name + ⋮ menu (disabled items)',
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

    expect(find.text('Alice'), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsOneWidget);

    await t.tap(find.byIcon(Icons.more_vert));
    await t.pumpAndSettle();
    // ⋮ items appear with the "即將推出" label
    expect(find.text('合併到其他對象（即將推出）'), findsOneWidget);
    expect(find.text('編輯對象（即將推出）'), findsOneWidget);
    expect(find.text('刪除對象（即將推出）'), findsOneWidget);
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
    expect(find.text('第 a 段'), findsOneWidget);
    expect(find.text('第 b 段'), findsOneWidget);
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
