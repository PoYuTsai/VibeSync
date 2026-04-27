// test/widget/features/partner/same_name_banner_test.dart
//
// Phase 4 Task 4 — banner detect/dismiss/CTA contract tests.
//
// We pump PartnerListScreen (not just the bare banner widget) so we exercise
// the screen-level wiring: dup-pair helper + uid scoping + provider gating +
// dismissed FutureProvider invalidation.
//
// Hermetic boundary: SharedPreferences is initialised via setMockInitialValues
// so PartnerBannerService.markDismissed flips the underlying flag without IO,
// and the FutureProvider re-emits true on invalidate.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vibesync/features/conversation/data/providers/conversation_providers.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/partner/data/providers/partner_banner_providers.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/domain/extensions/partner_aggregates.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/partner/presentation/screens/partner_list_screen.dart';

const _uid = 'u1';

Partner _p(String id, String name, {DateTime? createdAt}) => Partner(
      id: id,
      name: name,
      ownerUserId: _uid,
      createdAt: createdAt ?? DateTime(2026, 4, 20),
      updatedAt: createdAt ?? DateTime(2026, 4, 20),
    );

Stream<String?> _scopeStream() async* {
  yield _uid;
}

GoRouter _router({void Function(String location)? onPush}) {
  return GoRouter(
    initialLocation: '/',
    observers: const [],
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) =>
            const Scaffold(body: PartnerListScreen()),
      ),
      GoRoute(
        path: '/partner/:partnerId/merge',
        builder: (context, state) {
          onPush?.call(state.uri.toString());
          final from = state.pathParameters['partnerId']!;
          final target = state.uri.queryParameters['target'];
          return Scaffold(
            body: Text('merge-stub-from=$from-target=$target'),
          );
        },
      ),
    ],
  );
}

List<Override> _baseOverrides({
  required List<Partner> partners,
  bool? dismissedSeed, // null = real PartnerBannerService path
}) {
  return [
    authConversationScopeProvider.overrideWith((ref) => _scopeStream()),
    partnerListProvider.overrideWith((_) => partners),
    for (final p in partners)
      partnerAggregateProvider(p.id).overrideWith(
        (_) => _emptyAgg(),
      ),
    for (final p in partners)
      conversationsByPartnerProvider(p.id)
          .overrideWith((_) => const <Conversation>[]),
    if (dismissedSeed != null)
      partnerDedupeBannerDismissedProvider(_uid)
          .overrideWith((_) => Future.value(dismissedSeed)),
  ];
}

PartnerAggregateView _emptyAgg() => PartnerAggregateView.empty();

void main() {
  // Disable SharedPreferences disk IO across the whole suite.
  setUp(() async {
    SharedPreferences.setMockInitialValues(const {});
  });

  testWidgets('shows when ≥2 partners share same name and dismissed=false',
      (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: _baseOverrides(
        partners: [
          _p('a', 'Alice', createdAt: DateTime(2026, 4, 1)),
          _p('b', 'Alice', createdAt: DateTime(2026, 4, 10)),
          _p('c', 'Cara'),
        ],
        dismissedSeed: false,
      ),
      child: MaterialApp.router(routerConfig: _router()),
    ));
    await t.pumpAndSettle();

    expect(find.textContaining('你有兩個'), findsOneWidget);
    expect(find.text('立即合併'), findsOneWidget);
    expect(find.text('以後再說'), findsOneWidget);
  });

  testWidgets('does not show when all partners unique', (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: _baseOverrides(
        partners: [_p('a', 'Alice'), _p('b', 'Bob')],
        dismissedSeed: false,
      ),
      child: MaterialApp.router(routerConfig: _router()),
    ));
    await t.pumpAndSettle();

    expect(find.text('立即合併'), findsNothing);
    expect(find.text('以後再說'), findsNothing);
  });

  testWidgets('does not show when dismissed=true', (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: _baseOverrides(
        partners: [
          _p('a', 'Alice', createdAt: DateTime(2026, 4, 1)),
          _p('b', 'Alice', createdAt: DateTime(2026, 4, 10)),
        ],
        dismissedSeed: true,
      ),
      child: MaterialApp.router(routerConfig: _router()),
    ));
    await t.pumpAndSettle();

    expect(find.text('立即合併'), findsNothing);
  });

  testWidgets('does not show while dismissedProvider is loading', (t) async {
    // Hand a never-completing future so the provider stays loading.
    final never = Completer<bool>();
    addTearDown(() => never.complete(false));

    await t.pumpWidget(ProviderScope(
      overrides: [
        authConversationScopeProvider.overrideWith((ref) => _scopeStream()),
        partnerListProvider.overrideWith(
          (_) => [
            _p('a', 'Alice', createdAt: DateTime(2026, 4, 1)),
            _p('b', 'Alice', createdAt: DateTime(2026, 4, 10)),
          ],
        ),
        partnerAggregateProvider('a').overrideWith((_) => _emptyAgg()),
        partnerAggregateProvider('b').overrideWith((_) => _emptyAgg()),
        conversationsByPartnerProvider('a')
            .overrideWith((_) => const <Conversation>[]),
        conversationsByPartnerProvider('b')
            .overrideWith((_) => const <Conversation>[]),
        partnerDedupeBannerDismissedProvider(_uid)
            .overrideWith((_) => never.future),
      ],
      child: MaterialApp.router(routerConfig: _router()),
    ));
    await t.pump(); // do NOT pumpAndSettle → never future would hang
    await t.pump(const Duration(milliseconds: 100));

    expect(find.text('立即合併'), findsNothing);
    expect(find.text('以後再說'), findsNothing);
  });

  testWidgets(
    'tap "以後再說" calls service.markDismissed(uid) + invalidates provider + hides banner',
    (t) async {
      // Real service path — start with empty prefs.
      SharedPreferences.setMockInitialValues(const {});
      await t.pumpWidget(ProviderScope(
        overrides: _baseOverrides(
          partners: [
            _p('a', 'Alice', createdAt: DateTime(2026, 4, 1)),
            _p('b', 'Alice', createdAt: DateTime(2026, 4, 10)),
          ],
          // no dismissedSeed → real provider runs against mock prefs (false)
        ),
        child: MaterialApp.router(routerConfig: _router()),
      ));
      await t.pumpAndSettle();

      expect(find.text('以後再說'), findsOneWidget);

      await t.tap(find.text('以後再說'));
      await t.pumpAndSettle();

      expect(find.text('以後再說'), findsNothing);
      expect(find.text('立即合併'), findsNothing);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('partner_dedupe_banner_dismissed_$_uid'), isTrue);
    },
  );

  testWidgets(
    'tap "立即合併" pushes /partner/{newer.id}/merge?target={older.id}',
    (t) async {
      String? pushed;
      await t.pumpWidget(ProviderScope(
        overrides: _baseOverrides(
          partners: [
            // older = 'a' (Apr 1), newer = 'b' (Apr 10) — D-P4-2 contract
            _p('a', 'Alice', createdAt: DateTime(2026, 4, 1)),
            _p('b', 'Alice', createdAt: DateTime(2026, 4, 10)),
          ],
          dismissedSeed: false,
        ),
        child: MaterialApp.router(
          routerConfig: _router(onPush: (loc) => pushed = loc),
        ),
      ));
      await t.pumpAndSettle();

      await t.tap(find.text('立即合併'));
      await t.pumpAndSettle();

      expect(pushed, isNotNull);
      expect(pushed, '/partner/b/merge?target=a');
      expect(find.text('merge-stub-from=b-target=a'), findsOneWidget);
    },
  );
}
