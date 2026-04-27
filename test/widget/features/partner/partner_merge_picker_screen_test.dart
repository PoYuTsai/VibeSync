// test/widget/features/partner/partner_merge_picker_screen_test.dart
//
// Hermetic widget tests for PartnerMergePickerScreen.
// Overrides partnerListProvider / partnerByIdProvider /
// partnerAggregateProvider / conversationsByPartnerProvider for the source
// partner; uses RecordingPartnerWriteController to capture merge() args
// without hitting Hive.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/partner/data/providers/partner_write_controller.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/domain/extensions/partner_aggregates.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/partner/presentation/screens/partner_merge_picker_screen.dart';

import '_fakes/recording_partner_write_controller.dart';

Partner _p(String id, String name) => Partner(
      id: id,
      name: name,
      ownerUserId: 'u1',
      createdAt: DateTime(2026, 4, 27),
      updatedAt: DateTime(2026, 4, 27),
    );

Conversation _conv(String id) => Conversation(
      id: id,
      name: '第 $id 段',
      messages: const [],
      createdAt: DateTime(2026, 4, 20),
      updatedAt: DateTime(2026, 4, 20),
    );

PartnerAggregateView _aggWithTraits(int n) => PartnerAggregateView(
      unionInterests: const [],
      unionTraits: List.generate(n, (i) => 't$i'),
      unionNotes: null,
      latestHeat: null,
      totalRounds: 0,
      totalMessages: 0,
      lastInteraction: null,
    );

GoRouter _routerForPicker({
  required String fromId,
  Widget Function(BuildContext, String)? targetBuilder,
}) {
  return GoRouter(
    initialLocation: '/partner/$fromId/merge',
    routes: [
      GoRoute(
        path: '/partner/:partnerId/merge',
        builder: (_, state) => PartnerMergePickerScreen(
          fromPartnerId: state.pathParameters['partnerId']!,
        ),
      ),
      GoRoute(
        path: '/partner/:partnerId',
        builder: (ctx, state) {
          final id = state.pathParameters['partnerId']!;
          return targetBuilder?.call(ctx, id) ??
              Scaffold(body: Text('target-stub-$id'));
        },
      ),
    ],
  );
}

Future<void> _settle(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('picker lists candidates excluding source partner', (t) async {
    await t.binding.setSurfaceSize(const Size(400, 1200));
    addTearDown(() => t.binding.setSurfaceSize(null));

    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerListProvider.overrideWith(
          (_) => [_p('A', 'Alice'), _p('B', 'Bob'), _p('C', 'Cara')],
        ),
        partnerByIdProvider('A').overrideWith((_) => _p('A', 'Alice')),
        partnerAggregateProvider('A').overrideWith((_) => _aggWithTraits(0)),
        conversationsByPartnerProvider('A')
            .overrideWith((_) => const <Conversation>[]),
      ],
      child: MaterialApp.router(routerConfig: _routerForPicker(fromId: 'A')),
    ));
    await _settle(t);

    expect(find.text('選擇要合併到的對象'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Cara'), findsOneWidget);
    expect(find.text('Alice'), findsNothing);
  });

  testWidgets('selecting target opens confirm dialog with N convs + M traits',
      (t) async {
    await t.binding.setSurfaceSize(const Size(400, 1200));
    addTearDown(() => t.binding.setSurfaceSize(null));

    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerListProvider.overrideWith(
          (_) => [_p('A', 'Alice'), _p('B', 'Bob')],
        ),
        partnerByIdProvider('A').overrideWith((_) => _p('A', 'Alice')),
        partnerAggregateProvider('A').overrideWith((_) => _aggWithTraits(7)),
        conversationsByPartnerProvider('A').overrideWith(
          (_) => [_conv('x'), _conv('y'), _conv('z')],
        ),
      ],
      child: MaterialApp.router(routerConfig: _routerForPicker(fromId: 'A')),
    ));
    await _settle(t);

    await t.tap(find.text('Bob'));
    await _settle(t);

    expect(find.textContaining('Alice'), findsWidgets);
    expect(find.textContaining('Bob'), findsWidgets);
    expect(find.textContaining('3'), findsWidgets); // 3 對話
    expect(find.textContaining('7'), findsWidgets); // 7 個特質
    expect(find.textContaining('不可復原'), findsOneWidget);
    expect(find.text('確認合併'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
  });

  testWidgets(
      'confirm tap calls PartnerWriteController.merge(A → B) + navigates to /partner/B',
      (t) async {
    await t.binding.setSurfaceSize(const Size(400, 1200));
    addTearDown(() => t.binding.setSurfaceSize(null));

    final fake = RecordingPartnerWriteController();
    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerWriteControllerProvider.overrideWith(() => fake),
        partnerListProvider.overrideWith(
          (_) => [_p('A', 'Alice'), _p('B', 'Bob')],
        ),
        partnerByIdProvider('A').overrideWith((_) => _p('A', 'Alice')),
        partnerAggregateProvider('A').overrideWith((_) => _aggWithTraits(2)),
        conversationsByPartnerProvider('A').overrideWith(
          (_) => [_conv('x')],
        ),
      ],
      child: MaterialApp.router(routerConfig: _routerForPicker(fromId: 'A')),
    ));
    await _settle(t);

    await t.tap(find.text('Bob'));
    await _settle(t);

    await t.tap(find.text('確認合併'));
    await _settle(t);

    expect(fake.mergeCalled, isTrue);
    expect(fake.fromId, 'A');
    expect(fake.toId, 'B');
    expect(find.text('target-stub-B'), findsOneWidget);
  });

  testWidgets('cancel tap does not call merge and stays on picker', (t) async {
    await t.binding.setSurfaceSize(const Size(400, 1200));
    addTearDown(() => t.binding.setSurfaceSize(null));

    final fake = RecordingPartnerWriteController();
    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerWriteControllerProvider.overrideWith(() => fake),
        partnerListProvider.overrideWith(
          (_) => [_p('A', 'Alice'), _p('B', 'Bob')],
        ),
        partnerByIdProvider('A').overrideWith((_) => _p('A', 'Alice')),
        partnerAggregateProvider('A').overrideWith((_) => _aggWithTraits(1)),
        conversationsByPartnerProvider('A')
            .overrideWith((_) => const <Conversation>[]),
      ],
      child: MaterialApp.router(routerConfig: _routerForPicker(fromId: 'A')),
    ));
    await _settle(t);

    await t.tap(find.text('Bob'));
    await _settle(t);

    await t.tap(find.text('取消'));
    await _settle(t);

    expect(fake.mergeCalled, isFalse);
    expect(find.text('選擇要合併到的對象'), findsOneWidget);
  });

  testWidgets('merge failure shows snackbar and stays on picker', (t) async {
    await t.binding.setSurfaceSize(const Size(400, 1200));
    addTearDown(() => t.binding.setSurfaceSize(null));

    final fake = RecordingPartnerWriteController()
      ..throwOnMerge = StateError('boom');
    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerWriteControllerProvider.overrideWith(() => fake),
        partnerListProvider.overrideWith(
          (_) => [_p('A', 'Alice'), _p('B', 'Bob')],
        ),
        partnerByIdProvider('A').overrideWith((_) => _p('A', 'Alice')),
        partnerAggregateProvider('A').overrideWith((_) => _aggWithTraits(0)),
        conversationsByPartnerProvider('A')
            .overrideWith((_) => const <Conversation>[]),
      ],
      child: MaterialApp.router(routerConfig: _routerForPicker(fromId: 'A')),
    ));
    await _settle(t);

    await t.tap(find.text('Bob'));
    await _settle(t);
    await t.tap(find.text('確認合併'));
    await _settle(t);

    expect(fake.mergeCalled, isTrue);
    expect(find.textContaining('合併失敗'), findsOneWidget);
    expect(find.text('選擇要合併到的對象'), findsOneWidget);
  });
}
