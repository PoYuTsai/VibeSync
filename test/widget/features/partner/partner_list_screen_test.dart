import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/partner/data/repositories/partner_repository.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/domain/extensions/partner_aggregates.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/partner/presentation/screens/partner_list_screen.dart';
import 'package:vibesync/features/partner/presentation/widgets/partner_list_card.dart';

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

Widget _screen({
  required List<Override> overrides,
}) =>
    ProviderScope(
      overrides: overrides,
      child: const MaterialApp(home: Scaffold(body: PartnerListScreen())),
    );

void main() {
  testWidgets('empty state renders without partner cards', (t) async {
    await t.pumpWidget(_screen(overrides: [
      partnerListProvider.overrideWith((_) => const <Partner>[]),
    ]));
    await t.pumpAndSettle();

    expect(find.byType(PartnerListCard), findsNothing);
  });

  testWidgets('renders one PartnerListCard per partner with premium visuals',
      (t) async {
    await t.pumpWidget(_screen(overrides: [
      partnerListProvider
          .overrideWith((_) => [_p('a', 'Alice'), _p('b', 'Bob')]),
      partnerAggregateProvider('a').overrideWith(
        (_) => _agg(
          rounds: 3,
          heat: 70,
          interests: const ['coffee'],
          traits: const ['bold'],
        ),
      ),
      partnerAggregateProvider('b').overrideWith((_) => _agg(rounds: 1)),
      conversationsByPartnerProvider('a')
          .overrideWith((_) => const <Conversation>[]),
      conversationsByPartnerProvider('b')
          .overrideWith((_) => const <Conversation>[]),
    ]));
    await t.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('AL'), findsOneWidget);
    expect(find.text('BO'), findsOneWidget);
    expect(find.byIcon(Icons.local_fire_department_rounded), findsOneWidget);
    expect(find.text('70'), findsOneWidget);
    expect(find.byIcon(Icons.insights_rounded), findsOneWidget);
    expect(find.text('待分析'), findsOneWidget);
    expect(find.text('coffee · bold'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsNWidgets(2));
  });

  testWidgets('list preserves order from partnerListProvider', (t) async {
    await t.pumpWidget(_screen(overrides: [
      partnerListProvider
          .overrideWith((_) => [_p('z', 'Zoe'), _p('a', 'Alice')]),
      partnerAggregateProvider('z').overrideWith((_) => _agg()),
      partnerAggregateProvider('a').overrideWith((_) => _agg()),
      conversationsByPartnerProvider('z')
          .overrideWith((_) => const <Conversation>[]),
      conversationsByPartnerProvider('a')
          .overrideWith((_) => const <Conversation>[]),
    ]));
    await t.pumpAndSettle();

    final zoe = t.getTopLeft(find.text('Zoe'));
    final alice = t.getTopLeft(find.text('Alice'));
    expect(zoe.dy < alice.dy, isTrue, reason: 'Zoe must render above Alice');
  });

  group('delete dialog two-mode', () {
    testWidgets('tapping delete with conversationCount==0 shows confirm dialog',
        (t) async {
      await t.pumpWidget(_screen(overrides: [
        partnerListProvider.overrideWith((_) => [_p('a', 'Alice')]),
        partnerAggregateProvider('a').overrideWith((_) => _agg()),
        conversationsByPartnerProvider('a')
            .overrideWith((_) => const <Conversation>[]),
      ]));
      await t.pumpAndSettle();

      await t.tap(find.byIcon(Icons.delete_outline));
      await t.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(TextButton), findsNWidgets(2));
    });

    testWidgets(
        'tapping delete with conversationCount>0 shows informational dialog',
        (t) async {
      await t.pumpWidget(_screen(overrides: [
        partnerListProvider.overrideWith((_) => [_p('a', 'Alice')]),
        partnerAggregateProvider('a').overrideWith((_) => _agg(rounds: 0)),
        conversationsByPartnerProvider('a')
            .overrideWith((_) => [_conv('c1', 'a'), _conv('c2', 'a')]),
      ]));
      await t.pumpAndSettle();

      await t.tap(find.byIcon(Icons.delete_outline));
      await t.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(TextButton), findsOneWidget);
    });

    testWidgets('confirm dialog calls controller.delete and shows SnackBar',
        (t) async {
      final fake = _FakePartnerRepo();
      await t.pumpWidget(_screen(overrides: [
        partnerRepositoryProvider.overrideWithValue(fake),
        partnerListProvider.overrideWith((_) => [_p('a', 'Alice')]),
        partnerAggregateProvider('a').overrideWith((_) => _agg()),
        conversationsByPartnerProvider('a')
            .overrideWith((_) => const <Conversation>[]),
      ]));
      await t.pumpAndSettle();

      await t.tap(find.byIcon(Icons.delete_outline));
      await t.pumpAndSettle();
      await t.tap(find.byType(TextButton).last);
      await t.pumpAndSettle();

      expect(fake.deletedIds, ['a']);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets(
        'confirm dialog surfaces defensive SnackBar when repository blocks delete',
        (t) async {
      final throwing = _FakePartnerRepo(throwBlockCount: 4);
      await t.pumpWidget(_screen(overrides: [
        partnerRepositoryProvider.overrideWithValue(throwing),
        partnerListProvider.overrideWith((_) => [_p('a', 'Alice')]),
        partnerAggregateProvider('a').overrideWith((_) => _agg()),
        conversationsByPartnerProvider('a')
            .overrideWith((_) => const <Conversation>[]),
      ]));
      await t.pumpAndSettle();

      await t.tap(find.byIcon(Icons.delete_outline));
      await t.pumpAndSettle();
      await t.tap(find.byType(TextButton).last);
      await t.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('4'), findsOneWidget);
    });
  });
}

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
