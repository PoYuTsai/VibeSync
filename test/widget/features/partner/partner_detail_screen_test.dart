// test/widget/features/partner/partner_detail_screen_test.dart
//
// Hermetic widget tests for PartnerDetailScreen.
// Overrides the three narrow providers; no Hive required.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:vibesync/features/conversation/data/providers/conversation_write_controller.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/presentation/widgets/new_conversation_sheet.dart';
import 'package:vibesync/features/partner/data/providers/partner_write_controller.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/domain/extensions/partner_aggregates.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/partner/presentation/screens/partner_detail_screen.dart';
import 'package:vibesync/features/partner/presentation/widgets/partner_conversation_tile.dart';
import 'package:vibesync/features/partner/presentation/widgets/partner_data_quality_banner.dart';
import 'package:vibesync/features/partner/presentation/widgets/partner_heat_hero_card.dart';
import 'package:vibesync/features/partner/presentation/widgets/partner_radar_summary_card.dart';
import 'package:vibesync/features/partner/presentation/widgets/partner_traits_card.dart';
import 'package:vibesync/features/user_profile/data/providers/data_quality_flag_provider.dart';
import 'package:vibesync/features/user_profile/data/providers/partner_style_providers.dart';
import 'package:vibesync/features/user_profile/data/repositories/partner_style_repository.dart';
import 'package:vibesync/features/user_profile/domain/entities/partner_data_quality_state.dart';
import 'package:vibesync/features/user_profile/domain/entities/partner_style_override.dart';

import '_fakes/recording_conversation_write_controller.dart';
import '_fakes/recording_partner_write_controller.dart';

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

class _FakeStyleRepo implements PartnerStyleRepository {
  final Map<String, PartnerStyleOverride> byPartner = {};
  @override
  Future<PartnerStyleOverride?> load(String partnerId) async =>
      byPartner[partnerId];
  @override
  Future<void> save(PartnerStyleOverride o) async {
    if (o.isEmpty) {
      byPartner.remove(o.partnerId);
    } else {
      byPartner[o.partnerId] = o;
    }
  }

  @override
  Future<void> delete(String partnerId) async => byPartner.remove(partnerId);
  @override
  Future<void> clearAll() async => byPartner.clear();
}

void main() {
  testWidgets('tile delete confirm calls ConversationWriteController.delete',
      (t) async {
    // Tile lives below the new PartnerStyleEntryCard — give the surface
    // enough height so ListView's cache extent reaches the tile (matches
    // the reassign-tile tests' convention below).
    await t.binding.setSurfaceSize(const Size(400, 1200));
    addTearDown(() => t.binding.setSurfaceSize(null));

    final fake = RecordingConversationWriteController();
    final attachedConv = Conversation(
      id: 'c1',
      name: 'Alice',
      messages: const [],
      createdAt: DateTime(2026, 4, 20),
      updatedAt: DateTime(2026, 4, 20),
      partnerId: 'p1',
    );

    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerStyleRepositoryProvider.overrideWithValue(_FakeStyleRepo()),
        partnerByIdProvider('p1').overrideWith((_) => _p()),
        partnerAggregateProvider('p1')
            .overrideWith((_) => PartnerAggregateView.empty()),
        dataQualityFlagProvider('p1')
            .overrideWith((_) => const DataQualityFlag.unflagged()),
        conversationsByPartnerProvider('p1')
            .overrideWith((_) => [attachedConv]),
        partnerListProvider.overrideWith((_) => [_p(), _other('q1', 'Bob')]),
        conversationWriteControllerProvider.overrideWith(() => fake),
      ],
      child: const MaterialApp(home: PartnerDetailScreen(partnerId: 'p1')),
    ));
    await t.pumpAndSettle();

    final tileMenu = find.descendant(
      of: find.byType(PartnerConversationTile),
      matching: find.byIcon(Icons.more_vert),
    );
    await t.tap(tileMenu);
    await t.pumpAndSettle();
    await t.tap(find.text('刪除對話'));
    await t.pumpAndSettle();
    await t.tap(find.text('確認刪除'));
    await t.pumpAndSettle();

    expect(fake.deleteCalled, isTrue);
    expect(fake.deletedConversation?.id, 'c1');
    expect(find.text('已刪除這段互動紀錄'), findsOneWidget);
  });

  testWidgets('⋮ menu: merge + edit only, no disabled delete item', (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerStyleRepositoryProvider.overrideWithValue(_FakeStyleRepo()),
        partnerByIdProvider('p1').overrideWith((_) => _p()),
        partnerAggregateProvider('p1')
            .overrideWith((_) => PartnerAggregateView.empty()),
        dataQualityFlagProvider('p1')
            .overrideWith((_) => const DataQualityFlag.unflagged()),
        conversationsByPartnerProvider('p1')
            .overrideWith((_) => const <Conversation>[]),
        partnerListProvider.overrideWith((_) => [_p(), _other('q1', 'Bob')]),
      ],
      child: const MaterialApp(home: PartnerDetailScreen(partnerId: 'p1')),
    ));
    await t.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsOneWidget);

    await t.tap(find.byIcon(Icons.more_vert));
    await t.pumpAndSettle();

    expect(find.text('合併重複對象'), findsOneWidget);
    expect(find.text('編輯對象'), findsOneWidget);
    expect(find.text('編輯對象（即將推出）'), findsNothing);
    expect(find.text('刪除對象（即將推出）'), findsNothing);
  });

  testWidgets('⋮ edit → dialog → 儲存 calls updateName + success snackbar',
      (t) async {
    final fake = RecordingPartnerWriteController();

    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerStyleRepositoryProvider.overrideWithValue(_FakeStyleRepo()),
        partnerByIdProvider('p1').overrideWith((_) => _p()),
        partnerAggregateProvider('p1')
            .overrideWith((_) => PartnerAggregateView.empty()),
        dataQualityFlagProvider('p1')
            .overrideWith((_) => const DataQualityFlag.unflagged()),
        conversationsByPartnerProvider('p1')
            .overrideWith((_) => const <Conversation>[]),
        partnerListProvider.overrideWith((_) => [_p()]),
        partnerWriteControllerProvider.overrideWith(() => fake),
      ],
      child: const MaterialApp(home: PartnerDetailScreen(partnerId: 'p1')),
    ));
    await t.pumpAndSettle();

    await t.tap(find.byIcon(Icons.more_vert));
    await t.pumpAndSettle();
    await t.tap(find.text('編輯對象'));
    await t.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    await t.enterText(find.byType(TextField), '  Alicia  ');
    await t.tap(find.text('儲存'));
    await t.pumpAndSettle();

    expect(fake.updateNameCalled, isTrue);
    expect(fake.updatedPartner?.id, 'p1');
    expect(fake.updatedName, 'Alicia',
        reason: 'dialog must trim before handing off to controller');
    expect(find.text('已更新名稱'), findsOneWidget);
  });

  testWidgets('⋮ edit → 取消 does not call updateName', (t) async {
    final fake = RecordingPartnerWriteController();

    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerStyleRepositoryProvider.overrideWithValue(_FakeStyleRepo()),
        partnerByIdProvider('p1').overrideWith((_) => _p()),
        partnerAggregateProvider('p1')
            .overrideWith((_) => PartnerAggregateView.empty()),
        dataQualityFlagProvider('p1')
            .overrideWith((_) => const DataQualityFlag.unflagged()),
        conversationsByPartnerProvider('p1')
            .overrideWith((_) => const <Conversation>[]),
        partnerListProvider.overrideWith((_) => [_p()]),
        partnerWriteControllerProvider.overrideWith(() => fake),
      ],
      child: const MaterialApp(home: PartnerDetailScreen(partnerId: 'p1')),
    ));
    await t.pumpAndSettle();

    await t.tap(find.byIcon(Icons.more_vert));
    await t.pumpAndSettle();
    await t.tap(find.text('編輯對象'));
    await t.pumpAndSettle();
    await t.tap(find.text('取消'));
    await t.pumpAndSettle();

    expect(fake.updateNameCalled, isFalse);
    expect(find.text('已更新名稱'), findsNothing);
  });

  testWidgets('⋮ edit → controller throw shows error snackbar', (t) async {
    final fake = RecordingPartnerWriteController()
      ..throwOnUpdateName = StateError('boom');

    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerStyleRepositoryProvider.overrideWithValue(_FakeStyleRepo()),
        partnerByIdProvider('p1').overrideWith((_) => _p()),
        partnerAggregateProvider('p1')
            .overrideWith((_) => PartnerAggregateView.empty()),
        dataQualityFlagProvider('p1')
            .overrideWith((_) => const DataQualityFlag.unflagged()),
        conversationsByPartnerProvider('p1')
            .overrideWith((_) => const <Conversation>[]),
        partnerListProvider.overrideWith((_) => [_p()]),
        partnerWriteControllerProvider.overrideWith(() => fake),
      ],
      child: const MaterialApp(home: PartnerDetailScreen(partnerId: 'p1')),
    ));
    await t.pumpAndSettle();

    await t.tap(find.byIcon(Icons.more_vert));
    await t.pumpAndSettle();
    await t.tap(find.text('編輯對象'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'Alicia');
    await t.tap(find.text('儲存'));
    await t.pumpAndSettle();

    expect(fake.updateNameCalled, isTrue);
    expect(find.textContaining('更新失敗'), findsOneWidget);
  });

  testWidgets('⋮ menu: merge DISABLED when only one partner exists', (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerStyleRepositoryProvider.overrideWithValue(_FakeStyleRepo()),
        partnerByIdProvider('p1').overrideWith((_) => _p()),
        partnerAggregateProvider('p1')
            .overrideWith((_) => PartnerAggregateView.empty()),
        dataQualityFlagProvider('p1')
            .overrideWith((_) => const DataQualityFlag.unflagged()),
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
        partnerStyleRepositoryProvider.overrideWithValue(_FakeStyleRepo()),
        partnerByIdProvider('p1').overrideWith((_) => _p()),
        partnerAggregateProvider('p1')
            .overrideWith((_) => PartnerAggregateView.empty()),
        dataQualityFlagProvider('p1')
            .overrideWith((_) => const DataQualityFlag.unflagged()),
        conversationsByPartnerProvider('p1')
            .overrideWith((_) => const <Conversation>[]),
        partnerListProvider.overrideWith((_) => [_p(), _other('q1', 'Bob')]),
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

  testWidgets('renders hero + traits + radar + new-conversation FAB',
      (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerStyleRepositoryProvider.overrideWithValue(_FakeStyleRepo()),
        partnerByIdProvider('p1').overrideWith((_) => _p()),
        partnerAggregateProvider('p1')
            .overrideWith((_) => PartnerAggregateView.empty()),
        dataQualityFlagProvider('p1')
            .overrideWith((_) => const DataQualityFlag.unflagged()),
        conversationsByPartnerProvider('p1')
            .overrideWith((_) => const <Conversation>[]),
      ],
      child: const MaterialApp(home: PartnerDetailScreen(partnerId: 'p1')),
    ));
    await t.pumpAndSettle();

    // Post-A2 visual polish — hero comes BEFORE traits/radar.
    expect(find.byType(PartnerHeatHeroCard), findsOneWidget);
    expect(find.byType(PartnerTraitsCard), findsOneWidget);
    expect(find.byType(PartnerRadarSummaryCard), findsOneWidget);
    // FAB copy stays "+ 新增對話" verbatim per ADR-15 vocabulary lock
    // (Path A 2026-04-28). Visual changed (pill + orange), copy did not.
    expect(find.text('+ 新增對話'), findsOneWidget);
    // Empty-aggregate path → hero shows "待分析" (deterministic mapping,
    // never a fake score).
    expect(find.text('待分析'), findsOneWidget);
    expect(find.text('--'), findsOneWidget);
    expect(
      t.getTopLeft(find.byType(PartnerHeatHeroCard)).dy,
      lessThanOrEqualTo(kToolbarHeight),
      reason:
          'hero should sit close under the transparent title bar, not leave '
          'a dead shelf above the heat card.',
    );
  });

  testWidgets('new-conversation sheet receives current partnerId', (t) async {
    // Default flutter_test surface is 800x600 → modal sheet height 289.5px,
    // sheet content needs ~291px → 1.5px RenderFlex overflow fails the test.
    // Use a phone-realistic size so the sheet has room to render.
    await t.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));

    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerStyleRepositoryProvider.overrideWithValue(_FakeStyleRepo()),
        partnerByIdProvider('p1').overrideWith((_) => _p()),
        partnerAggregateProvider('p1')
            .overrideWith((_) => PartnerAggregateView.empty()),
        dataQualityFlagProvider('p1')
            .overrideWith((_) => const DataQualityFlag.unflagged()),
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
        partnerStyleRepositoryProvider.overrideWithValue(_FakeStyleRepo()),
        partnerByIdProvider('p1').overrideWith((_) => _p()),
        partnerAggregateProvider('p1')
            .overrideWith((_) => PartnerAggregateView.empty()),
        dataQualityFlagProvider('p1')
            .overrideWith((_) => const DataQualityFlag.unflagged()),
        conversationsByPartnerProvider('p1')
            .overrideWith((_) => const <Conversation>[]),
      ],
      child: const MaterialApp(home: PartnerDetailScreen(partnerId: 'p1')),
    ));
    await t.pumpAndSettle();
    expect(find.textContaining('還沒有互動紀錄'), findsOneWidget);
  });

  testWidgets('renders one tile per conversation when list non-empty',
      (t) async {
    await t.binding.setSurfaceSize(const Size(400, 1200));
    addTearDown(() => t.binding.setSurfaceSize(null));

    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerStyleRepositoryProvider.overrideWithValue(_FakeStyleRepo()),
        partnerByIdProvider('p1').overrideWith((_) => _p()),
        partnerAggregateProvider('p1')
            .overrideWith((_) => PartnerAggregateView.empty()),
        dataQualityFlagProvider('p1')
            .overrideWith((_) => const DataQualityFlag.unflagged()),
        conversationsByPartnerProvider('p1')
            .overrideWith((_) => [_conv('a'), _conv('b')]),
      ],
      child: const MaterialApp(home: PartnerDetailScreen(partnerId: 'p1')),
    ));
    await t.pumpAndSettle();
    expect(find.byType(PartnerConversationTile), findsNWidgets(2),
        reason: 'Tile titles no longer carry conversation.name (per "人 vs 互動" '
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
        partnerStyleRepositoryProvider.overrideWithValue(_FakeStyleRepo()),
        partnerByIdProvider('p1').overrideWith((_) => _p()),
        partnerAggregateProvider('p1')
            .overrideWith((_) => PartnerAggregateView.empty()),
        dataQualityFlagProvider('p1')
            .overrideWith((_) => const DataQualityFlag.unflagged()),
        conversationsByPartnerProvider('p1')
            .overrideWith((_) => [attachedConv]),
        partnerListProvider.overrideWith((_) => [_p(), _other('q1', 'Bob')]),
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

  testWidgets('reassign picker confirms single-record move before save',
      (t) async {
    await t.binding.setSurfaceSize(const Size(400, 1200));
    addTearDown(() => t.binding.setSurfaceSize(null));

    final fake = RecordingConversationWriteController();
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
        partnerStyleRepositoryProvider.overrideWithValue(_FakeStyleRepo()),
        partnerByIdProvider('p1').overrideWith((_) => _p()),
        partnerAggregateProvider('p1')
            .overrideWith((_) => PartnerAggregateView.empty()),
        dataQualityFlagProvider('p1')
            .overrideWith((_) => const DataQualityFlag.unflagged()),
        conversationsByPartnerProvider('p1')
            .overrideWith((_) => [attachedConv]),
        partnerListProvider.overrideWith((_) => [_p(), _other('q1', 'Bob')]),
        conversationWriteControllerProvider.overrideWith(() => fake),
      ],
      child: const MaterialApp(home: PartnerDetailScreen(partnerId: 'p1')),
    ));
    await t.pumpAndSettle();

    final tileMenu = find.descendant(
      of: find.byType(PartnerConversationTile),
      matching: find.byIcon(Icons.more_vert),
    );
    await t.tap(tileMenu);
    await t.pumpAndSettle();
    await t.tap(find.text('改派到其他對象'));
    await t.pumpAndSettle();

    await t.tap(find.text('Bob'));
    await t.pumpAndSettle();

    expect(find.text('把這段移到「Bob」？'), findsOneWidget);
    expect(find.textContaining('請確認這段聊天真的屬於「Bob」'), findsOneWidget);
    expect(find.textContaining('只會移動目前這一段互動紀錄'), findsOneWidget);
    expect(find.textContaining('不會合併兩張對象卡'), findsOneWidget);
    expect(fake.saveCalled, isFalse);

    await t.tap(find.text('移過去'));
    await t.pumpAndSettle();

    expect(fake.saveCalled, isTrue);
    expect(fake.savedPartnerIdAtCallTime, 'q1');
    expect(fake.savedPreviousPartnerId, 'p1');
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

  // Spec 3 Task 19 — PartnerDataQualityBanner integration on PartnerDetailScreen.
  // The banner sits between PartnerTraitsCard and PartnerStyleEntryCard and
  // only renders when the dataQualityFlagProvider returns a flagged result
  // with a non-null conflictingPair. Action handlers are STUBS in this task
  // (Tasks 20/21 fill them in); these tests verify rendering only.
  testWidgets(
      'PartnerDataQualityBanner appears when dataQualityFlagProvider is flagged',
      (t) async {
    await t.binding.setSurfaceSize(const Size(400, 1400));
    addTearDown(() => t.binding.setSurfaceSize(null));

    final pair = NamePair.canonical('May', 'Anna');

    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerStyleRepositoryProvider.overrideWithValue(_FakeStyleRepo()),
        partnerByIdProvider('p1').overrideWith((_) => _p()),
        partnerAggregateProvider('p1')
            .overrideWith((_) => PartnerAggregateView.empty()),
        dataQualityFlagProvider('p1')
            .overrideWith((_) => DataQualityFlag.flagged(pair)),
        conversationsByPartnerProvider('p1')
            .overrideWith((_) => const <Conversation>[]),
        partnerListProvider.overrideWith((_) => [_p()]),
      ],
      child: const MaterialApp(home: PartnerDetailScreen(partnerId: 'p1')),
    ));
    await t.pumpAndSettle();

    expect(find.byType(PartnerDataQualityBanner), findsOneWidget);
    // Both names from the conflicting pair surface in the banner copy.
    expect(find.textContaining(pair.first), findsOneWidget);
    expect(find.textContaining(pair.second), findsOneWidget);
  });

  testWidgets(
      'PartnerDataQualityBanner is NOT rendered when flag is unflagged',
      (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerStyleRepositoryProvider.overrideWithValue(_FakeStyleRepo()),
        partnerByIdProvider('p1').overrideWith((_) => _p()),
        partnerAggregateProvider('p1')
            .overrideWith((_) => PartnerAggregateView.empty()),
        dataQualityFlagProvider('p1')
            .overrideWith((_) => const DataQualityFlag.unflagged()),
        conversationsByPartnerProvider('p1')
            .overrideWith((_) => const <Conversation>[]),
        partnerListProvider.overrideWith((_) => [_p()]),
      ],
      child: const MaterialApp(home: PartnerDetailScreen(partnerId: 'p1')),
    ));
    await t.pumpAndSettle();

    expect(find.byType(PartnerDataQualityBanner), findsNothing);
  });
}
