// test/widget/features/partner/partner_list_screen_test.dart
//
// Hermetic widget tests for PartnerListScreen.
//
// Card receives an already-computed PartnerAggregateView (lifted-aggregate
// API) so tests only need: one override for partnerListProvider plus one
// override per partner id for partnerAggregateProvider AND
// conversationsByPartnerProvider — the latter so the screen can capture the
// real conversationCount (Codex P1.2: false-safe fix).
//
// Phase 4 Task 2 adds delete dialog two-mode coverage. We override
// `partnerRepositoryProvider` with a stubbed repo to keep success/error path
// tests fully hermetic — no Hive, no platform IO.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/partner/data/repositories/partner_repository.dart';
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

PartnerAggregateView _agg({
  int rounds = 0,
  int? heat,
  List<String> interests = const [],
  List<String> traits = const [],
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

Conversation _conv(String id, String partnerId) => Conversation(
      id: id,
      name: 'c-$id',
      ownerUserId: 'u1',
      createdAt: DateTime(2026, 4, 20),
      updatedAt: DateTime(2026, 4, 20),
      messages: const [],
      partnerId: partnerId,
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

  testWidgets(
      'renders one PartnerListCard per partner with restored 5-piece visuals',
      (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerListProvider
            .overrideWith((_) => [_p('a', 'Alice'), _p('b', 'Bob')]),
        partnerAggregateProvider('a').overrideWith(
          (_) => _agg(
            rounds: 3,
            heat: 70,
            interests: const ['咖啡'],
            traits: const ['溫柔'],
          ),
        ),
        partnerAggregateProvider('b').overrideWith((_) => _agg(rounds: 1)),
        conversationsByPartnerProvider('a')
            .overrideWith((_) => const <Conversation>[]),
        conversationsByPartnerProvider('b')
            .overrideWith((_) => const <Conversation>[]),
      ],
      child: const MaterialApp(home: Scaffold(body: PartnerListScreen())),
    ));
    await t.pumpAndSettle();

    // Names
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    // Avatar initials
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    // Heat indicator for Alice (70 → hot 🔥) AND fallback for Bob
    expect(find.text('🔥'), findsOneWidget);
    expect(find.text('70'), findsOneWidget);
    expect(find.text('待分析'), findsOneWidget);
    // Tag preview only on Alice (Bob has empty tags so no preview row)
    expect(find.text('咖啡 · 溫柔'), findsOneWidget);
    // Both rows have a delete icon (onDelete is non-null in screen)
    expect(find.byIcon(Icons.delete_outline), findsNWidgets(2));
  });

  testWidgets('list preserves order from partnerListProvider', (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerListProvider
            .overrideWith((_) => [_p('z', 'Zoe'), _p('a', 'Alice')]),
        partnerAggregateProvider('z').overrideWith((_) => _agg()),
        partnerAggregateProvider('a').overrideWith((_) => _agg()),
        conversationsByPartnerProvider('z')
            .overrideWith((_) => const <Conversation>[]),
        conversationsByPartnerProvider('a')
            .overrideWith((_) => const <Conversation>[]),
      ],
      child: const MaterialApp(home: Scaffold(body: PartnerListScreen())),
    ));
    await t.pumpAndSettle();
    final zoe = t.getTopLeft(find.text('Zoe'));
    final alice = t.getTopLeft(find.text('Alice'));
    expect(zoe.dy < alice.dy, isTrue, reason: 'Zoe must render above Alice');
  });

  // ─── Delete dialog two-mode coverage (Phase 4 Task 2) ────────────────────

  group('delete dialog two-mode', () {
    testWidgets(
        'tapping delete with conversationCount==0 shows confirm dialog',
        (t) async {
      await t.pumpWidget(ProviderScope(
        overrides: [
          partnerListProvider.overrideWith((_) => [_p('a', 'Alice')]),
          partnerAggregateProvider('a').overrideWith((_) => _agg()),
          conversationsByPartnerProvider('a')
              .overrideWith((_) => const <Conversation>[]),
        ],
        child: const MaterialApp(home: Scaffold(body: PartnerListScreen())),
      ));
      await t.pumpAndSettle();

      await t.tap(find.byIcon(Icons.delete_outline));
      await t.pumpAndSettle();

      // Confirm dialog has destructive Delete + Cancel buttons.
      expect(find.textContaining('確定刪除'), findsOneWidget);
      // Alice appears in the dialog title text plus the underlying card row.
      expect(find.textContaining('Alice'), findsWidgets);
      expect(find.text('取消'), findsOneWidget);
      expect(find.text('刪除'), findsOneWidget);
    });

    testWidgets(
        'tapping delete with conversationCount>0 shows informational dialog '
        '(no destructive action) even if aggregate.totalRounds==0',
        (t) async {
      await t.pumpWidget(ProviderScope(
        overrides: [
          partnerListProvider.overrideWith((_) => [_p('a', 'Alice')]),
          // Aggregate reports zero rounds (zero-round conversation case).
          partnerAggregateProvider('a').overrideWith((_) => _agg(rounds: 0)),
          // But there IS a conversation row referencing this partner.
          conversationsByPartnerProvider('a')
              .overrideWith((_) => [_conv('c1', 'a'), _conv('c2', 'a')]),
        ],
        child: const MaterialApp(home: Scaffold(body: PartnerListScreen())),
      ));
      await t.pumpAndSettle();

      await t.tap(find.byIcon(Icons.delete_outline));
      await t.pumpAndSettle();

      // Informational dialog: no "刪除" button, only "知道了" / OK.
      // "無法刪除" appears in both title + content sentence, so widgets > 1.
      expect(find.textContaining('還有 2 個對話'), findsOneWidget);
      expect(find.textContaining('無法刪除'), findsWidgets);
      expect(find.text('刪除'), findsNothing);
      expect(find.text('知道了'), findsOneWidget);
    });

    testWidgets(
        'confirm dialog → controller.delete called → SnackBar success',
        (t) async {
      final fake = _FakePartnerRepo();
      await t.pumpWidget(ProviderScope(
        overrides: [
          partnerRepositoryProvider.overrideWithValue(fake),
          partnerListProvider.overrideWith((_) => [_p('a', 'Alice')]),
          partnerAggregateProvider('a').overrideWith((_) => _agg()),
          conversationsByPartnerProvider('a')
              .overrideWith((_) => const <Conversation>[]),
        ],
        child: const MaterialApp(home: Scaffold(body: PartnerListScreen())),
      ));
      await t.pumpAndSettle();

      await t.tap(find.byIcon(Icons.delete_outline));
      await t.pumpAndSettle();

      await t.tap(find.text('刪除'));
      await t.pumpAndSettle();

      expect(fake.deletedIds, ['a']);
      expect(find.textContaining('已刪除'), findsOneWidget);
    });

    testWidgets(
        'confirm dialog → controller.delete throws '
        'PartnerHasConversationsException → defensive SnackBar', (t) async {
      // Race: at dialog-open time we believe count==0, but the repo throws
      // because a conversation got created concurrently.
      final throwing = _FakePartnerRepo(throwBlockCount: 4);

      await t.pumpWidget(ProviderScope(
        overrides: [
          partnerRepositoryProvider.overrideWithValue(throwing),
          partnerListProvider.overrideWith((_) => [_p('a', 'Alice')]),
          partnerAggregateProvider('a').overrideWith((_) => _agg()),
          conversationsByPartnerProvider('a')
              .overrideWith((_) => const <Conversation>[]),
        ],
        child: const MaterialApp(home: Scaffold(body: PartnerListScreen())),
      ));
      await t.pumpAndSettle();

      await t.tap(find.byIcon(Icons.delete_outline));
      await t.pumpAndSettle();
      await t.tap(find.text('刪除'));
      await t.pumpAndSettle();

      expect(find.textContaining('刪除失敗'), findsOneWidget);
      expect(find.textContaining('4'), findsOneWidget);
    });
  });
}

/// Hermetic stand-in for [PartnerRepository]. We only need `delete` to be
/// observable / throwable; other methods stay no-op via [noSuchMethod].
class _FakePartnerRepo implements PartnerRepository {
  _FakePartnerRepo({this.throwBlockCount});
  final int? throwBlockCount;
  final List<String> deletedIds = [];

  @override
  Future<void> delete(String partnerId) async {
    if (throwBlockCount != null) {
      throw PartnerHasConversationsException(throwBlockCount!);
    }
    deletedIds.add(partnerId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
